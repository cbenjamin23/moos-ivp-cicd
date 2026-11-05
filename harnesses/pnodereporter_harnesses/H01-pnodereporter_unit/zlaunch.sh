#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H01-pnodereporter_unit
#   Author: Charles Benjamin
#   LastEd: Jul 2026
#------------------------------------------------------------

need_bash=5.1
if [ -z "${BASH_VERSION:-}" ]; then
    echo "zlaunch.sh: run this harness as ./zlaunch.sh with Bash >= $need_bash." >&2
    exit 2
fi

have_bash51() {
    (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) ))
}

if ! have_bash51; then
    if [ "${HARNESS_DISABLE_BASH_REEXEC:-}" != 1 ]; then
        for bash_candidate in "${HARNESS_BASH:-}" /opt/homebrew/bin/bash /usr/local/bin/bash /home/linuxbrew/.linuxbrew/bin/bash; do
            [ -n "$bash_candidate" ] && [ -x "$bash_candidate" ] || continue
            if "$bash_candidate" -c '(( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) ))' 2>/dev/null; then
                echo "zlaunch.sh: re-running with $bash_candidate for Bash >= $need_bash" >&2
                exec "$bash_candidate" "$0" "$@"
            fi
        done
    fi
    echo "zlaunch.sh: Bash >= $need_bash is required for rolling --jobs scheduling." >&2
    echo "Detected Bash: $BASH_VERSION" >&2
    echo "On macOS, install Homebrew Bash or run: HARNESS_BASH=/opt/homebrew/bin/bash ./zlaunch.sh" >&2
    exit 2
fi

set -u

ME=$(basename "$0")
HARNESS_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$HARNESS_DIR/../../.." && pwd)
MISSION_DIR="$REPO_DIR/missions/pnodereporter_missions/pnodereporter_unit"
TEARDOWN_HELPER="$REPO_DIR/scripts/moos_scoped_teardown.sh"
RESULTS_FILE="$HARNESS_DIR/results.txt"
RUNS_DIR="$HARNESS_DIR/.harness_runs"
RUN_ROOT=""

TIME_WARP=10
MAX_TIME=35
JOBS=1
PORT_BASE=9000
PORT_STRIDE=30
PSHARE_OFFSET=$((PORT_STRIDE / 2))
KEEP_WORKDIRS=no
VERBOSE=no
JUST_MAKE=no
LOG_MODE=minimal
DISPLAY_ARGS=(--nogui)
CASE=""
CLEANED=no
CLEANING=no
CLEANUP_FAILED=no
FINISH_FATAL_REASON=""

CASES=(
    nav_report_baseline_pass
    platform_metadata_pass
    helm_nohelm_mode_pass
    helm_standby_switch_pass
    helm_stale_threshold_pass
    color_change_blocked_pass
    color_change_allowed_pass
    platform_report_pass
    platform_report_gap_pass
    rider_payload_pass
    custom_output_var_pass
    json_only_report_pass
    json_dual_report_pass
    alt_nav_report_pass
    alt_nav_named_absolute_pass
    coord_policy_global_pass
    heading_error_pass
    crossfill_local_to_global_pass
    crossfill_global_to_local_pass
    crossfill_global_terse_pass
    node_group_update_pass
    platform_color_mail_pass
    reverse_load_warning_pass
    blackout_interval_reset_fail
    mhash_odometer_pass
    report_cog_pass
    terse_reports_pass
    vsource_aux_allstop_pass
    pause_resume_pass
    crossfill_fill_empty_pass
    crossfill_use_latest_local_pass
    extrap_gap_metric_pass
    extrap_prune_pass
)

declare -a SELECTED_CASES CASE_RESULT
declare -A PID_CASE PID_RESULT PID_LOG PID_PORT_BASE

usage() {
    local case_name
    cat <<EOF
$ME [OPTIONS] [time_warp]

Options:
  --help, -h         Show this help message
  --verbose, -v      Show rolling scheduler events
  --just_make, -j    Prepare each case without launching it
  --log=<mode>       Logging mode: minimal (default) or full
  --max_time=<secs>  Maximum time passed to each stem mission
  --case=<name>      Run one named case
  --jobs=<n>         Run up to n cases concurrently with rolling scheduling
  --port_base=<n>    Base MOOS port for per-case blocks
  --keep_workdirs    Keep this invocation's isolated case directories
  --gui              Accepted for wrapper parity
  --nogui, -ng       Headless launch, no gui (default)

Cases:
EOF
    for case_name in "${CASES[@]}"; do
        printf '  %s\n' "$case_name"
    done
    cat <<EOF

Examples:
  ./$ME
  ./$ME --case=nav_report_baseline_pass
  ./$ME --jobs=2 --port_base=22000
  ./$ME --just_make --case=extrap_prune_pass
EOF
}

die() {
    echo "$ME: $*" >&2
    exit 2
}

is_uint() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

for arg in "$@"; do
    case "$arg" in
        --case=*)
            CASE="${arg#--case=}"
            [ -n "$CASE" ] || die "--case requires a nonempty case name"
            ;;
        --jobs=*) JOBS="${arg#--jobs=}" ;;
        --port_base=*) PORT_BASE="${arg#--port_base=}" ;;
        --max_time=*) MAX_TIME="${arg#--max_time=}" ;;
        --log=*) LOG_MODE="${arg#--log=}" ;;
        --keep_workdirs) KEEP_WORKDIRS=yes ;;
        --verbose|-v) VERBOSE=yes ;;
        --just_make|-j) JUST_MAKE=yes ;;
        --gui) DISPLAY_ARGS=(--gui) ;;
        --nogui|-ng) DISPLAY_ARGS=(--nogui) ;;
        --help|-h) usage; exit 0 ;;
        *[!0-9]*|'') die "bad argument: $arg" ;;
        *) TIME_WARP="$arg" ;;
    esac
done

case "$LOG_MODE" in
    minimal|full) ;;
    *) die "--log must be minimal or full" ;;
esac

is_uint "$TIME_WARP" && [ "${#TIME_WARP}" -le 9 ] || die "time warp must be a bounded positive integer"
is_uint "$JOBS" && [ "${#JOBS}" -le 9 ] || die "--jobs must be a bounded positive integer"
is_uint "$PORT_BASE" && [ "${#PORT_BASE}" -le 5 ] || die "--port_base must be an integer from 1 through 65535"
is_uint "$MAX_TIME" && [ "${#MAX_TIME}" -le 9 ] || die "--max_time must be a bounded positive integer"

TIME_WARP=$((10#$TIME_WARP))
JOBS=$((10#$JOBS))
PORT_BASE=$((10#$PORT_BASE))
MAX_TIME=$((10#$MAX_TIME))

[ "$TIME_WARP" -gt 0 ] || die "time warp must be a positive integer"
[ "$JOBS" -gt 0 ] || die "--jobs must be a positive integer"
[ "$PORT_BASE" -gt 0 ] && [ "$PORT_BASE" -le 65535 ] || die "--port_base must be an integer from 1 through 65535"
[ "$MAX_TIME" -gt 0 ] || die "--max_time must be a positive integer"

[ -d "$MISSION_DIR" ] || die "mission directory not found: $MISSION_DIR"
[ -f "$TEARDOWN_HELPER" ] || die "missing teardown helper: $TEARDOWN_HELPER"
# shellcheck source=/dev/null
. "$TEARDOWN_HELPER"

select_cases() {
    local case_name
    SELECTED_CASES=()
    if [ -n "$CASE" ]; then
        for case_name in "${CASES[@]}"; do
            if [ "$case_name" = "$CASE" ]; then
                SELECTED_CASES=("$case_name")
                return 0
            fi
        done
        die "unknown case: $CASE"
    fi
    SELECTED_CASES=("${CASES[@]}")
    [ "${#SELECTED_CASES[@]}" -gt 0 ] || die "no cases selected"
}

field_value() {
    local line="$1"
    local key="$2"
    local field
    local -a fields=()
    read -r -a fields <<< "$line"
    for field in "${fields[@]}"; do
        case "$field" in
            "$key"=*) printf '%s\n' "${field#*=}"; return 0 ;;
        esac
    done
    return 1
}

field_count() {
    local line="$1"
    local key="$2"
    local field
    local count=0
    local -a fields=()
    read -r -a fields <<< "$line"
    for field in "${fields[@]}"; do
        case "$field" in
            "$key"=*) count=$((count + 1)) ;;
        esac
    done
    printf '%s\n' "$count"
}

without_case_field() {
    local line="$1"
    local field
    local output=""
    local -a fields=()
    read -r -a fields <<< "$line"
    for field in "${fields[@]}"; do
        case "$field" in
            case=*) ;;
            *) output="${output:+$output }$field" ;;
        esac
    done
    printf '%s\n' "$output"
}

runner_provenance() {
    local line="$1"
    local field
    local output=""
    local -a fields=()
    read -r -a fields <<< "$line"
    for field in "${fields[@]}"; do
        case "$field" in
            case=*) field="mission_case=${field#*=}" ;;
            grade=*) field="mission_grade=${field#*=}" ;;
            reason=*) field="mission_reason=${field#*=}" ;;
            launch_rc=*) field="mission_launch_rc=${field#*=}" ;;
        esac
        output="${output:+$output }$field"
    done
    printf '%s\n' "$output"
}

stop_root() {
    if ! moos_scoped_teardown_stop_root "$1"; then
        echo "$ME: scoped teardown failed for $1" >&2
        return 1
    fi
}

cleanup_runtime() {
    local pid
    local root_stopped=yes
    [ "$CLEANED" = no ] || return 0
    [ "$CLEANING" = no ] || return 0
    CLEANING=yes
    trap '' INT TERM PIPE
    for pid in "${!PID_CASE[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    if [ -n "$RUN_ROOT" ] && [ -d "$RUN_ROOT" ]; then
        if ! stop_root "$RUN_ROOT"; then
            root_stopped=no
            CLEANUP_FAILED=yes
        fi
        if [ "$KEEP_WORKDIRS" != yes ] && [ "$root_stopped" = yes ] &&
           [ "$CLEANUP_FAILED" = no ]; then
            rm -rf "$RUN_ROOT"
        fi
    fi
    rmdir "$RUNS_DIR" 2>/dev/null || true
    CLEANED=yes
    CLEANING=no
}

on_signal() {
    exit 130
}

trap cleanup_runtime EXIT
trap on_signal INT TERM PIPE

payload_has() {
    local line="$1"
    local token="$2"
    echo "$line" | grep -Fq "$token"
}

check_payload() {
    local line="$1"
    local missing=""
    local forbidden=""
    local token

    for token in $CHECK_TOKENS; do
        if ! payload_has "$line" "$token"; then
            missing="${missing}${missing:+,}$token"
        fi
    done

    for token in $ABSENT_TOKENS; do
        if payload_has "$line" "$token"; then
            forbidden="${forbidden}${forbidden:+,}$token"
        fi
    done

    if [ "$missing" = "" ] && [ "$forbidden" = "" ]; then
        echo "pass"
        return 0
    fi

    echo "fail:missing=${missing:-none}:forbidden=${forbidden:-none}"
    return 1
}

payload_matches() {
    local line="$1"
    local token

    for token in $CHECK_TOKENS; do
        case "$line" in
            *"$token"*) ;;
            *) return 1 ;;
        esac
    done
    for token in $ABSENT_TOKENS; do
        case "$line" in
            *"$token"*) return 1 ;;
            *) ;;
        esac
    done
    return 0
}

alog_payload_matches() {
    local line="$1"
    local token

    for token in $CHECK_TOKENS; do
        case "$token" in
            node_seen=true) continue ;;
        esac
        case "$line" in
            *"$token"*) ;;
            *) return 1 ;;
        esac
    done
    for token in $ABSENT_TOKENS; do
        case "$line" in
            *"$token"*) return 1 ;;
            *) ;;
        esac
    done
    return 0
}

check_alog_payload() {
    local mission_root="$1"
    local alog
    local line

    while IFS= read -r -d '' alog; do
        while IFS= read -r line; do
            case "$line" in
                *NODE_REPORT_LOCAL*) ;;
                *) continue ;;
            esac
            if alog_payload_matches "$line"; then
                echo "pass"
                return 0
            fi
        done < "$alog"
    done < <(find "$mission_root" -type f -name '*.alog' -print0)

    echo "fail:missing=matching_NODE_REPORT_LOCAL:forbidden=none"
    return 1
}

payload_component_value() {
    local payload="$1"
    local key="$2"
    local component
    local -a components

    IFS=',' read -r -a components <<< "$payload"
    for component in "${components[@]}"; do
        case "$component" in
            "$key="*) printf '%s\n' "${component#*=}"; return 0 ;;
        esac
    done
    return 1
}

numeric_in_range() {
    local value="$1"
    local lower="$2"
    local upper="$3"

    awk -v value="$value" -v lower="$lower" -v upper="$upper" \
        'BEGIN {exit !(value ~ /^-?[0-9]+([.][0-9]+)?$/ && value >= lower && value <= upper)}'
}

require_component_range() {
    local payload="$1"
    local key="$2"
    local lower="$3"
    local upper="$4"
    local value

    value=$(payload_component_value "$payload" "$key" || true)
    [ -n "$value" ] && numeric_in_range "$value" "$lower" "$upper"
}

reject_component() {
    local payload="$1"
    local key="$2"

    ! payload_component_value "$payload" "$key" >/dev/null
}

check_coordinate_payload() {
    local case_name="$1"
    local line="$2"
    local payload
    local valid=no

    payload=$(field_value "$line" node_report || true)
    [ -n "$payload" ] || {
        echo "fail:missing=node_report"
        return 1
    }

    case "$case_name" in
        coord_policy_global_pass)
            require_component_range "$payload" LAT 43.825349 43.825351 &&
                require_component_range "$payload" LON -70.330451 -70.330449 &&
                reject_component "$payload" X && reject_component "$payload" Y &&
                valid=yes
            ;;
        crossfill_local_to_global_pass)
            require_component_range "$payload" X 12 12 &&
                require_component_range "$payload" Y -8 -8 &&
                require_component_range "$payload" LAT 43.825229 43.825231 &&
                require_component_range "$payload" LON -70.330250 -70.330248 &&
                valid=yes
            ;;
        crossfill_global_to_local_pass|crossfill_global_terse_pass)
            require_component_range "$payload" LAT 43.825359 43.825361 &&
                require_component_range "$payload" LON -70.330461 -70.330459 &&
                require_component_range "$payload" X -4.73 -4.71 &&
                require_component_range "$payload" Y 6.73 6.75 &&
                valid=yes
            ;;
        crossfill_fill_empty_pass)
            require_component_range "$payload" LAT 43.825369 43.825371 &&
                require_component_range "$payload" LON -70.330471 -70.330469 &&
                require_component_range "$payload" X -5.51 -5.49 &&
                require_component_range "$payload" Y 7.86 7.88 &&
                valid=yes
            ;;
        crossfill_use_latest_local_pass)
            require_component_range "$payload" X 25 25 &&
                require_component_range "$payload" Y 5 5 &&
                require_component_range "$payload" LAT 43.825348 43.825350 &&
                require_component_range "$payload" LON -70.330091 -70.330089 &&
                valid=yes
            ;;
        *) return 1 ;;
    esac
    if [ "$valid" = yes ]; then
        echo "pass"
        return 0
    fi

    echo "fail:coordinate_contract"
    return 1
}

check_alog_contract() {
    local case_name="$1"
    local mission_root="$2"
    local alog

    while IFS= read -r -d '' alog; do
        case "$case_name" in
            platform_report_gap_pass)
                awk '
                    $2 == "PLATFORM_REPORT_LOCAL" && index("," $4 ",", ",batt=12.7,") {
                        first_time=$1; first_seen=1
                    }
                    $2 == "PLATFORM_REPORT_LOCAL" && first_seen &&
                        index("," $4 ",", ",batt=12.8,") {
                        delay=$1-first_time; second_seen=1
                    }
                    END {exit !(first_seen && second_seen && delay >= 1.8 && delay <= 2.4)}
                ' "$alog" && { echo "pass"; return 0; }
                ;;
            report_cog_pass)
                awk '
                    $2 == "NODE_REPORT_LOCAL" {
                        payload="," $4 ","
                        if(index(payload, ",X=8,") && index(payload, ",Y=0,") &&
                           index(payload, ",COG=90,"))
                            found=1
                    }
                    END {exit !found}
                ' "$alog" && { echo "pass"; return 0; }
                ;;
            pause_resume_pass)
                awk '
                    $2 == "NODE_REPORT_LOCAL" {
                        payload="," $4 ","
                        count++
                        if(index(payload, ",X=1,") || index(payload, ",Y=1,"))
                            paused_report=1
                        if(count == 1 && index(payload, ",X=30,") &&
                           index(payload, ",Y=-10,"))
                            resumed_first=1
                    }
                    END {exit !(count > 0 && resumed_first && !paused_report)}
                ' "$alog" && { echo "pass"; return 0; }
                ;;
            extrap_gap_metric_pass)
                awk '
                    $2 == "PNR_EXTRAP_POS_GAP" && $4 >= 2.4 && $4 <= 2.9 {pos_seen=1}
                    $2 == "PNR_EXTRAP_HDG_GAP" && $4 >= 0 && $4 <= 0.01 {hdg_seen=1}
                    END {exit !(pos_seen && hdg_seen)}
                ' "$alog" && { echo "pass"; return 0; }
                ;;
        esac
    done < <(find "$mission_root" -type f -name '*.alog' -print0)

    echo "fail:history_contract"
    return 1
}

check_case_payload() {
    local case_name="$1"
    local line="$2"
    local mission_root="$3"

    case "$case_name" in
        coord_policy_global_pass|crossfill_local_to_global_pass|crossfill_global_to_local_pass|crossfill_global_terse_pass|crossfill_fill_empty_pass|crossfill_use_latest_local_pass)
            check_coordinate_payload "$case_name" "$line"
            ;;
        platform_report_gap_pass|report_cog_pass|pause_resume_pass|extrap_gap_metric_pass)
            if ! payload_matches "$line"; then
                check_payload "$line"
            else
                check_alog_contract "$case_name" "$mission_root"
            fi
            ;;
        alt_nav_report_pass|alt_nav_named_absolute_pass|reverse_load_warning_pass)
            if payload_matches "$line"; then
                echo "pass"
            else
                check_alog_payload "$mission_root"
            fi
            ;;
        *)
            check_payload "$line"
            ;;
    esac
}

get_case_config() {
    local case_name="$1"
    CASE_SHORE_PATCH=""
    CHECK_TOKENS=""
    ABSENT_TOKENS=""

    case "$case_name" in
        nav_report_baseline_pass)
            ;;
        platform_metadata_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/platform-metadata-pass.xmoos"
            ;;
        helm_nohelm_mode_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/helm-nohelm-mode-pass.xmoos"
            ;;
        helm_standby_switch_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/helm-standby-switch-pass.xmoos"
            ;;
        helm_stale_threshold_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/helm-stale-threshold-pass.xmoos"
            ;;
        color_change_blocked_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/color-change-blocked-pass.xmoos"
            ;;
        color_change_allowed_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/color-change-allowed-pass.xmoos"
            ;;
        platform_report_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/platform-report-pass.xmoos"
            ;;
        platform_report_gap_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/platform-report-gap-pass.xmoos"
            ;;
        rider_payload_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/rider-payload-pass.xmoos"
            ;;
        custom_output_var_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/custom-output-var-pass.xmoos"
            ;;
        json_only_report_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/json-only-report-pass.xmoos"
            ;;
        json_dual_report_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/json-dual-report-pass.xmoos"
            ;;
        alt_nav_report_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/alt-nav-report-pass.xmoos"
            ;;
        alt_nav_named_absolute_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/alt-nav-named-absolute-pass.xmoos"
            ;;
        coord_policy_global_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/coord-policy-global-pass.xmoos"
            ;;
        heading_error_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/heading-error-pass.xmoos"
            ;;
        crossfill_local_to_global_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/crossfill-local-to-global-pass.xmoos"
            ;;
        crossfill_global_to_local_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/crossfill-global-to-local-pass.xmoos"
            ;;
        crossfill_global_terse_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/crossfill-global-terse-pass.xmoos"
            ;;
        node_group_update_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/node-group-update-pass.xmoos"
            ;;
        platform_color_mail_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/platform-color-mail-pass.xmoos"
            ;;
        reverse_load_warning_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/reverse-load-warning-pass.xmoos"
            ;;
        blackout_interval_reset_fail)
            CASE_SHORE_PATCH="$HARNESS_DIR/blackout-interval-reset-fail.xmoos"
            ;;
        mhash_odometer_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/mhash-odometer-pass.xmoos"
            ;;
        report_cog_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/report-cog-pass.xmoos"
            ;;
        terse_reports_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/terse-reports-pass.xmoos"
            ;;
        vsource_aux_allstop_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/vsource-aux-allstop-pass.xmoos"
            ;;
        pause_resume_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/pause-resume-pass.xmoos"
            ;;
        crossfill_fill_empty_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/crossfill-fill-empty-pass.xmoos"
            ;;
        crossfill_use_latest_local_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/crossfill-use-latest-local-pass.xmoos"
            ;;
        extrap_gap_metric_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/extrap-gap-metric-pass.xmoos"
            ;;
        extrap_prune_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/extrap-prune-pass.xmoos"
            ;;
        *) return 1 ;;
    esac

    if [ "$case_name" = "nav_report_baseline_pass" ]; then
        CHECK_TOKENS="node_seen=true first_seen=true NAME=reporter TYPE=kayak COLOR=red X=10 Y=-5 SPD=2.5 HDG=123 DEP=7 LENGTH=4.2 BEAM=1.4 MODE=MODE@ACTIVE:TRANSIT first_report=NAME=reporter"
    elif [ "$case_name" = "platform_metadata_pass" ]; then
        CHECK_TOKENS="NAME=reporter TYPE=uuv COLOR=blue LENGTH=9.5 BEAM=2.1 GROUP=survey PAYLOAD=ctd ROLE=lead"
    elif [ "$case_name" = "helm_nohelm_mode_pass" ]; then
        CHECK_TOKENS="NAME=reporter MODE=NOHELM-EVER"
    elif [ "$case_name" = "helm_standby_switch_pass" ]; then
        CHECK_TOKENS="NAME=reporter MODE=MODE@ACTIVE:STANDBY_TRACK"
    elif [ "$case_name" = "helm_stale_threshold_pass" ]; then
        CHECK_TOKENS="NAME=reporter MODE=NOHELM-"
    elif [ "$case_name" = "color_change_blocked_pass" ]; then
        CHECK_TOKENS="NAME=reporter COLOR=red"
        ABSENT_TOKENS="COLOR=yellow"
    elif [ "$case_name" = "color_change_allowed_pass" ]; then
        CHECK_TOKENS="NAME=reporter COLOR=yellow"
    elif [ "$case_name" = "platform_report_pass" ]; then
        CHECK_TOKENS="platform_seen=true platform_report=platform=reporter batt=12.7 sats=9"
    elif [ "$case_name" = "platform_report_gap_pass" ]; then
        CHECK_TOKENS="platform_seen=true platform_report=platform=reporter batt=12.8"
        ABSENT_TOKENS="batt=12.7"
    elif [ "$case_name" = "rider_payload_pass" ]; then
        CHECK_TOKENS="NAME=reporter batt=12.7 payload=armed"
    elif [ "$case_name" = "custom_output_var_pass" ]; then
        CHECK_TOKENS="my_seen=true my_first_seen=true my_report=NAME=reporter"
        ABSENT_TOKENS="node_report=NAME=reporter"
    elif [ "$case_name" = "json_only_report_pass" ]; then
        CHECK_TOKENS='node_seen=true node_report={"NAME":"reporter" "TYPE":"kayak"'
        ABSENT_TOKENS="node_report=NAME=reporter"
    elif [ "$case_name" = "json_dual_report_pass" ]; then
        CHECK_TOKENS='node_seen=true json_seen=true node_report=NAME=reporter json_report={"NAME":"reporter"'
    elif [ "$case_name" = "alt_nav_report_pass" ]; then
        CHECK_TOKENS="node_seen=true NAME=reporter_GT GROUP=truth X=20 Y=-15 SPD=3.1 HDG=210"
    elif [ "$case_name" = "alt_nav_named_absolute_pass" ]; then
        CHECK_TOKENS="node_seen=true NAME=truth_node GROUP=truth_abs X=22 Y=-12 DEP=4 ALTITUDE=40"
    elif [ "$case_name" = "coord_policy_global_pass" ]; then
        CHECK_TOKENS="NAME=reporter LAT=43.82535 LON=-70.33045"
    elif [ "$case_name" = "heading_error_pass" ]; then
        CHECK_TOKENS="NAME=reporter HDG=128"
        ABSENT_TOKENS="HDG=123"
    elif [ "$case_name" = "crossfill_local_to_global_pass" ]; then
        CHECK_TOKENS="NAME=reporter X=12 Y=-8"
    elif [ "$case_name" = "crossfill_global_to_local_pass" ]; then
        CHECK_TOKENS="NAME=reporter LAT=43.82536 LON=-70.33046"
    elif [ "$case_name" = "crossfill_global_terse_pass" ]; then
        CHECK_TOKENS="NAME=reporter LAT=43.82536 LON=-70.33046"
    elif [ "$case_name" = "node_group_update_pass" ]; then
        CHECK_TOKENS="NAME=reporter GROUP=dynamic"
    elif [ "$case_name" = "platform_color_mail_pass" ]; then
        CHECK_TOKENS="NAME=reporter COLOR=orange"
    elif [ "$case_name" = "reverse_load_warning_pass" ]; then
        CHECK_TOKENS="NAME=reporter THRUST_MODE_REVERSE=true LOAD_WARNING=pHelmIvP:5"
    elif [ "$case_name" = "blackout_interval_reset_fail" ]; then
        CHECK_TOKENS="evidence=blackout_gap_below_threshold node_seen=true pnr_gap="
    elif [ "$case_name" = "mhash_odometer_pass" ]; then
        CHECK_TOKENS="pnr_mhash_seen=true pnr_mhash=mhash= ext=20"
    elif [ "$case_name" = "report_cog_pass" ]; then
        CHECK_TOKENS="node_seen=true NAME=reporter X=8 Y=0"
    elif [ "$case_name" = "terse_reports_pass" ]; then
        CHECK_TOKENS="NAME=reporter X=10 Y=-5 SPD=2.5 HDG=123 TYPE=kayak COLOR=red"
        ABSENT_TOKENS="DEP= LAT= LON= YAW="
    elif [ "$case_name" = "vsource_aux_allstop_pass" ]; then
        CHECK_TOKENS="NAME=reporter VSOURCE=ais MODE_AUX=survey ALLSTOP=manual"
    elif [ "$case_name" = "pause_resume_pass" ]; then
        CHECK_TOKENS="NAME=reporter X=30 Y=-10"
        ABSENT_TOKENS="X=1,Y=1"
    elif [ "$case_name" = "crossfill_fill_empty_pass" ]; then
        CHECK_TOKENS="NAME=reporter LAT=43.82537 LON=-70.33047"
    elif [ "$case_name" = "crossfill_use_latest_local_pass" ]; then
        CHECK_TOKENS="NAME=reporter X=25 Y=5"
    elif [ "$case_name" = "extrap_gap_metric_pass" ]; then
        CHECK_TOKENS="node_seen=true extrap_pos= extrap_hdg="
    elif [ "$case_name" = "extrap_prune_pass" ]; then
        CHECK_TOKENS="node_seen=true X=0 Y=0 extrap_pos= extrap_hdg="
        ABSENT_TOKENS="X=12"
    fi
}

apply_case_overlays() {
    local case_name="$1"
    local workdir="$2"
    local patch
    local -a shore_patches=()

    get_case_config "$case_name" || return 1

    if [ "$LOG_MODE" = full ]; then
        shore_patches+=("$workdir/full-logging-shoreside.xmoos")
    fi
    if [ -n "$CASE_SHORE_PATCH" ]; then
        shore_patches+=("$CASE_SHORE_PATCH")
    fi
    if [ "${#shore_patches[@]}" -gt 0 ]; then
        for patch in "${shore_patches[@]}"; do
            [ -f "$patch" ] || return 1
        done
        nspatch "$workdir/meta_shoreside.moos" \
            "${shore_patches[@]}" "$workdir/meta_shoreside.moosx" || return 1
    fi
}

prepare_case() {
    local case_name="$1"
    local workdir="$2"

    rm -rf "$workdir"
    mkdir -p "$workdir" || return 1
    cp -R "$MISSION_DIR"/. "$workdir"/ || return 1
    (
        cd "$workdir" || exit 1
        ./clean.sh >/dev/null 2>&1
    ) || return 1
    apply_case_overlays "$case_name" "$workdir"
}

write_result() {
    local case_name="$1"
    local result_file="$2"
    local launch_rc="$3"
    local workdir="$4"
    local line
    local grade_count
    local mission_grade
    local mission_rows
    local provenance
    local token_status

    if [ "$JUST_MAKE" = yes ]; then
        if [ "$launch_rc" -eq 0 ]; then
            printf 'case=%s grade=pass mode=just_make\n' "$case_name" > "$result_file"
        else
            printf 'case=%s grade=fail reason=launch_error launch_rc=%s mode=just_make\n' \
                "$case_name" "$launch_rc" > "$result_file"
        fi
        return 0
    fi

    if [ ! -f "$workdir/results.txt" ]; then
        printf 'case=%s grade=fail reason=missing_result_file launch_rc=%s\n' \
            "$case_name" "$launch_rc" > "$result_file"
        return 0
    fi

    mission_rows=$(awk 'NF {count++} END {print count+0}' "$workdir/results.txt")
    if [ "$mission_rows" -eq 0 ]; then
        printf 'case=%s grade=fail reason=missing_result launch_rc=%s\n' \
            "$case_name" "$launch_rc" > "$result_file"
        return 0
    fi
    if [ "$mission_rows" -ne 1 ]; then
        printf 'case=%s grade=fail reason=duplicate_results result_rows=%s\n' \
            "$case_name" "$mission_rows" > "$result_file"
        return 0
    fi

    line=$(awk 'NF {print; exit}' "$workdir/results.txt")
    grade_count=$(field_count "$line" grade)
    if [ "$grade_count" -eq 0 ]; then
        printf 'case=%s grade=fail reason=missing_result launch_rc=%s\n' \
            "$case_name" "$launch_rc" > "$result_file"
        return 0
    fi
    if [ "$grade_count" -ne 1 ]; then
        printf 'case=%s grade=fail reason=malformed_result grade_fields=%s\n' \
            "$case_name" "$grade_count" > "$result_file"
        return 0
    fi

    mission_grade=$(field_value "$line" grade || true)
    if [ "$mission_grade" != pass ] && [ "$mission_grade" != fail ]; then
        printf 'case=%s grade=fail reason=malformed_result mission_grade=%s\n' \
            "$case_name" "${mission_grade:-missing}" > "$result_file"
        return 0
    fi

    if [ "$launch_rc" -ne 0 ]; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=launch_error launch_rc=%s%s\n' \
            "$case_name" "$launch_rc" "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi

    if [ "$mission_grade" = pass ]; then
        token_status=$(check_case_payload "$case_name" "$line" "$workdir")
        if [ "$token_status" != pass ]; then
            provenance=$(runner_provenance "$line")
            printf 'case=%s grade=fail reason=payload_check_failed token_check=%s%s\n' \
                "$case_name" "$token_status" "${provenance:+ $provenance}" > "$result_file"
            return 0
        fi
    fi

    line=$(without_case_field "$line")
    if [ "$mission_grade" = pass ]; then
        printf 'case=%s %s token_check=pass\n' "$case_name" "$line" > "$result_file"
    else
        printf 'case=%s %s\n' "$case_name" "$line" > "$result_file"
    fi
}

run_case() {
    local case_name="$1"
    local workdir="$2"
    local result_file="$3"
    local case_base="$4"
    local launch_rc=0
    local launch_args
    local result_line
    local grade

    prepare_case "$case_name" "$workdir" || {
        printf 'case=%s grade=fail reason=prepare_error\n' "$case_name" > "$result_file"
        return 1
    }

    (
        cd "$workdir" || exit 1
        : > results.txt
        launch_args=(
            --max_time="$MAX_TIME"
            "${DISPLAY_ARGS[@]}"
            --shore_mport="$((case_base + 0))"
            --shore_pshare="$((case_base + PSHARE_OFFSET))"
            "$TIME_WARP"
        )
        [ "$JUST_MAKE" = yes ] && launch_args+=(--just_make)
        LOG_MODE_PREPARED=yes ./zlaunch.sh --log="$LOG_MODE" "${launch_args[@]}"
    ) || launch_rc=$?

    write_result "$case_name" "$result_file" "$launch_rc" "$workdir"
    if ! stop_root "$workdir"; then
        printf 'case=%s grade=fail reason=teardown_error\n' "$case_name" > "$result_file"
    fi

    result_line=$(awk 'NF {print; exit}' "$result_file" 2>/dev/null)
    grade=$(field_value "$result_line" grade || true)
    [ "$grade" = pass ]
}

start_case() {
    local case_idx="$1"
    local case_name="${SELECTED_CASES[$case_idx]}"
    local case_dir
    local workdir
    local result_file
    local log_file
    local case_base
    local pid

    case_base=$((PORT_BASE + case_idx * PORT_STRIDE))
    case_dir="$RUN_ROOT/case_$(printf '%03d' "$case_idx")_$case_name"
    workdir="$case_dir/mission"
    result_file="$case_dir/result.row"
    log_file="$case_dir/run.log"

    mkdir -p "$case_dir"
    CASE_RESULT[case_idx]="$result_file"

    (
        local rc=0
        set +e
        run_case "$case_name" "$workdir" "$result_file" "$case_base" > "$log_file" 2>&1
        rc=$?
        if [ ! -s "$result_file" ]; then
            printf 'case=%s grade=fail reason=missing_result launch_rc=%s\n' \
                "$case_name" "$rc" > "$result_file"
        fi
        exit "$rc"
    ) &

    pid=$!
    PID_CASE[$pid]="$case_name"
    PID_RESULT[$pid]="$result_file"
    PID_LOG[$pid]="$log_file"
    PID_PORT_BASE[$pid]="$case_base"

    if [ "$VERBOSE" = yes ]; then
        printf 'event=start epoch=%s pid=%s case=%s port_base=%s workdir=%s\n' \
            "$(date +%s)" "$pid" "$case_name" "$case_base" "$workdir"
    fi
}

finish_one() {
    local done_pid=""
    local wait_rc=0
    local case_name
    local line
    local grade
    local reason

    FINISH_FATAL_REASON=""
    wait -p done_pid -n || wait_rc=$?
    if [ -z "${done_pid:-}" ]; then
        echo "$ME: wait returned without a completed pid rc=$wait_rc" >&2
        FINISH_FATAL_REASON=scheduler_state_error
        return 2
    fi

    case_name="${PID_CASE[$done_pid]:-}"
    if [ -z "$case_name" ]; then
        echo "$ME: unknown completed pid $done_pid rc=$wait_rc" >&2
        FINISH_FATAL_REASON=scheduler_state_error
        return 2
    fi

    line=$(awk 'NF {print; exit}' "${PID_RESULT[$done_pid]}" 2>/dev/null)
    grade=$(field_value "$line" grade || true)
    reason=$(field_value "$line" reason || true)
    if [ "$wait_rc" -ne 0 ] && [ "$grade" = pass ]; then
        printf 'case=%s grade=fail reason=worker_error worker_rc=%s\n' \
            "$case_name" "$wait_rc" > "${PID_RESULT[$done_pid]}"
        grade=fail
    fi
    if [ "$VERBOSE" = yes ]; then
        printf 'event=finish epoch=%s pid=%s case=%s rc=%s grade=%s port_base=%s log=%s\n' \
            "$(date +%s)" "$done_pid" "$case_name" "$wait_rc" "${grade:-missing}" \
            "${PID_PORT_BASE[$done_pid]}" "${PID_LOG[$done_pid]}"
    fi

    unset 'PID_CASE[$done_pid]' 'PID_RESULT[$done_pid]' 'PID_LOG[$done_pid]'
    unset 'PID_PORT_BASE[$done_pid]'
    if [ "$reason" = teardown_error ]; then
        FINISH_FATAL_REASON=teardown_error
        return 2
    fi
    [ "$grade" = pass ]
}

stop_refill_after_infrastructure_error() {
    local next_idx="$1"
    local total="$2"
    local fatal_reason="$3"
    local case_idx
    local case_name
    local case_dir
    local result_file

    CLEANUP_FAILED=yes
    echo "$ME: stopping scheduler refill after $fatal_reason" >&2

    for ((case_idx = next_idx; case_idx < total; case_idx++)); do
        case_name="${SELECTED_CASES[$case_idx]}"
        case_dir="$RUN_ROOT/case_$(printf '%03d' "$case_idx")_$case_name"
        result_file="$case_dir/result.row"
        CASE_RESULT[case_idx]="$result_file"
        if mkdir -p "$case_dir"; then
            printf 'case=%s grade=fail reason=scheduler_aborted_after_%s\n' \
                "$case_name" "$fatal_reason" > "$result_file"
        else
            echo "$ME: unable to record aborted case: $case_name" >&2
        fi
    done
}

aggregate_results() {
    local total="${#SELECTED_CASES[@]}"
    local case_idx
    local case_name
    local result_file
    local row_count
    local line
    local row_case
    local grade_count
    local grade

    FINAL_FAILURES=0
    RESULT_ROWS=0
    : > "$RESULTS_FILE"

    for ((case_idx = 0; case_idx < total; case_idx++)); do
        case_name="${SELECTED_CASES[$case_idx]}"
        result_file="${CASE_RESULT[$case_idx]:-}"
        line=""

        if [ -n "$result_file" ] && [ -f "$result_file" ]; then
            row_count=$(awk 'NF {count++} END {print count+0}' "$result_file")
            if [ "$row_count" -eq 1 ]; then
                line=$(awk 'NF {print; exit}' "$result_file")
            else
                line="case=$case_name grade=fail reason=invalid_row_count result_rows=$row_count"
            fi
        else
            line="case=$case_name grade=fail reason=missing_result_file"
        fi

        row_case=$(field_value "$line" case || true)
        grade_count=$(field_count "$line" grade)
        if [ "$row_case" != "$case_name" ]; then
            line="case=$case_name grade=fail reason=result_case_mismatch"
        elif [ "$grade_count" -ne 1 ]; then
            line="case=$case_name grade=fail reason=malformed_result grade_fields=$grade_count"
        else
            grade=$(field_value "$line" grade || true)
            if [ "$grade" != pass ] && [ "$grade" != fail ]; then
                line="case=$case_name grade=fail reason=malformed_result mission_grade=${grade:-missing}"
            fi
        fi

        printf '%s\n' "$line" >> "$RESULTS_FILE"
        RESULT_ROWS=$((RESULT_ROWS + 1))
        grade=$(field_value "$line" grade || true)
        [ "$grade" = pass ] || FINAL_FAILURES=$((FINAL_FAILURES + 1))
    done
}

select_cases
total=${#SELECTED_CASES[@]}
if [ "${DISPLAY_ARGS[0]}" = --gui ] && [ "$total" -ne 1 ]; then
    die "--gui requires one explicit --case"
fi
last_port=$((PORT_BASE + (total - 1) * PORT_STRIDE + PSHARE_OFFSET))
[ "$last_port" -le 65535 ] || die "selected cases require ports through $last_port"

mkdir -p "$RUNS_DIR" || die "unable to create run directory: $RUNS_DIR"
RUN_ROOT="$RUNS_DIR/run_$(date +%Y%m%dT%H%M%S)_$$"
mkdir -p "$RUN_ROOT" || die "unable to create run root: $RUN_ROOT"
: > "$RESULTS_FILE"

SECONDS=0
active=0
next=0
scheduler_broken=no

while [ "$next" -lt "$total" ] || [ "$active" -gt 0 ]; do
    while [ "$next" -lt "$total" ] && [ "$active" -lt "$JOBS" ]; do
        start_case "$next"
        next=$((next + 1))
        active=$((active + 1))
    done
    if [ "$active" -gt 0 ]; then
        finish_rc=0
        finish_one || finish_rc=$?
        if [ "$finish_rc" -eq 2 ] && [ "$FINISH_FATAL_REASON" = scheduler_state_error ]; then
            stop_refill_after_infrastructure_error "$next" "$total" "$FINISH_FATAL_REASON"
            next=$total
            scheduler_broken=yes
            break
        fi
        active=$((active - 1))
        if [ "$finish_rc" -eq 2 ]; then
            stop_refill_after_infrastructure_error "$next" "$total" "$FINISH_FATAL_REASON"
            next=$total
        fi
    fi
done

if [ "$scheduler_broken" = yes ]; then
    cleanup_runtime
fi

aggregate_results

if [ "$RESULT_ROWS" -ne "$total" ] || { [ "$total" -gt 0 ] && [ "$RESULT_ROWS" -eq 0 ]; }; then
    echo "$ME: expected $total result rows but wrote $RESULT_ROWS" >&2
    FINAL_FAILURES=$((FINAL_FAILURES + 1))
fi

cleanup_runtime
elapsed_seconds=$SECONDS
if [ -d "$RUN_ROOT" ]; then
    kept_root="$RUN_ROOT"
else
    kept_root="none"
fi
if [ "$CLEANUP_FAILED" = yes ]; then
    FINAL_FAILURES=$((FINAL_FAILURES + 1))
fi
trap - EXIT INT TERM PIPE

printf 'results=%s failures=%s total=%s jobs=%s log_mode=%s elapsed_seconds=%s bash=%s workdirs=%s\n' \
    "$RESULTS_FILE" "$FINAL_FAILURES" "$total" "$JOBS" "$LOG_MODE" "$elapsed_seconds" "$BASH_VERSION" "$kept_root"

[ "$FINAL_FAILURES" -eq 0 ]
