#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H01-zigzag_behavior_motion
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
MISSION_DIR="$REPO_DIR/missions/zigzag_behavior_missions/zigzag_behavior_motion"
TEARDOWN_HELPER="$REPO_DIR/scripts/moos_scoped_teardown.sh"
RESULTS_FILE="$HARNESS_DIR/results.txt"
RUNS_DIR="$HARNESS_DIR/.harness_runs"
RUN_ROOT=""

TIME_WARP=10
MAX_TIME=90
JOBS=1
PORT_BASE=9000
PORT_STRIDE=30
PSHARE_OFFSET=10
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
    baseline_port_first_pass
    star_first_pass
    zig_first_right_alias_pass
    zig_first_starboard_alias_pass
    stem_hdg_wrap_pass
    stem_hdg_negative_wrap_pass
    hdg_thresh_loose_pass
    small_angle_pass
    wide_angle_pass
    max_zig_zags_pass
    single_leg_complete_pass
    zero_leg_limit_pass
    stem_odo_complete_pass
    short_stem_odo_complete_pass
    stem_on_active_pass
    speed_on_active_pass
    mod_speed_increase_pass
    mod_speed_reset_pass
    mod_speed_clip_high_pass
    mod_speed_clip_low_pass
    bad_runtime_update_recover_pass
    fierce_zigging_pass
    delta_heading_alias_pass
    bad_zig_angle_low_fail
    bad_zig_angle_high_fail
    bad_zig_first_fail
    bad_max_zig_zags_fail
    bad_max_stem_odo_fail
    bad_speed_fail
    bad_delta_heading_fail
    bad_stale_nav_thresh_fail
    bad_hdg_thresh_fail
    bad_visual_hint_fail
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
  --port_stride=<n>  Port spacing between case blocks (minimum 12)
  --keep_workdirs    Keep this invocation's isolated case directories
  --gui              Launch with pMarineViewer
  --nogui, -ng       Headless launch, no gui (default)

Cases:
EOF
    for case_name in "${CASES[@]}"; do
        printf '  %s\n' "$case_name"
    done
    cat <<EOF

Examples:
  ./$ME
  ./$ME --log=full
  ./$ME --case=baseline_port_first_pass
  ./$ME --jobs=4 --port_base=15000 --port_stride=12
  ./$ME --just_make --case=bad_zig_angle_low_fail
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
        --port_stride=*) PORT_STRIDE="${arg#--port_stride=}" ;;
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
is_uint "$PORT_STRIDE" && [ "${#PORT_STRIDE}" -le 5 ] || die "--port_stride must be a bounded integer of at least 12"
is_uint "$MAX_TIME" && [ "${#MAX_TIME}" -le 9 ] || die "--max_time must be a bounded positive integer"

TIME_WARP=$((10#$TIME_WARP))
JOBS=$((10#$JOBS))
PORT_BASE=$((10#$PORT_BASE))
PORT_STRIDE=$((10#$PORT_STRIDE))
MAX_TIME=$((10#$MAX_TIME))

[ "$TIME_WARP" -gt 0 ] || die "time warp must be a positive integer"
[ "$JOBS" -gt 0 ] || die "--jobs must be a positive integer"
[ "$PORT_BASE" -gt 0 ] && [ "$PORT_BASE" -le 65535 ] || die "--port_base must be an integer from 1 through 65535"
[ "$PORT_STRIDE" -ge 12 ] || die "--port_stride must be at least 12"
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

get_case_config() {
    local case_name="$1"
    CASE_NAME="$case_name"
    CASE_SHORE_PATCH=""
    CASE_VEH_MOOS_PATCH=""
    CASE_VEH_BHV_PATCH=""

    case "$CASE_NAME" in
        baseline_port_first_pass)
            ;;
        star_first_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-star-first-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/star-first-pass-vehicle.xbhv"
            ;;
        zig_first_right_alias_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-star-first-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/zig-first-right-alias-pass-vehicle.xbhv"
            ;;
        zig_first_starboard_alias_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-star-first-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/zig-first-starboard-alias-pass-vehicle.xbhv"
            ;;
        stem_hdg_wrap_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-stem-hdg-wrap-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/stem-hdg-wrap-pass-vehicle.xbhv"
            ;;
        stem_hdg_negative_wrap_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-stem-hdg-wrap-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/stem-hdg-negative-wrap-pass-vehicle.xbhv"
            ;;
        hdg_thresh_loose_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-hdg-thresh-loose-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/hdg-thresh-loose-pass-vehicle.xbhv"
            ;;
        small_angle_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-small-angle-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/small-angle-pass-vehicle.xbhv"
            ;;
        wide_angle_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-wide-angle-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/wide-angle-pass-vehicle.xbhv"
            ;;
        max_zig_zags_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-max-zig-zags-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/max-zig-zags-pass-vehicle.xbhv"
            ;;
        single_leg_complete_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-short-complete-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/single-leg-complete-pass-vehicle.xbhv"
            ;;
        zero_leg_limit_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-zero-leg-complete-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/zero-leg-limit-pass-vehicle.xbhv"
            ;;
        stem_odo_complete_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-stem-odo-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/stem-odo-complete-pass-vehicle.xbhv"
            ;;
        short_stem_odo_complete_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-short-stem-odo-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/short-stem-odo-complete-pass-vehicle.xbhv"
            ;;
        stem_on_active_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-stem-on-active-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/stem-on-active-pass-vehicle.xbhv"
            ;;
        speed_on_active_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-speed-on-active-pass-shoreside.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/speed-on-active-pass-vehicle.xbhv"
            ;;
        mod_speed_increase_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-mod-speed-pass-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/mod-speed-increase-pass-vehicle.xmoos"
            ;;
        mod_speed_reset_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-mod-speed-reset-pass-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/mod-speed-reset-pass-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/mod-speed-reset-pass-vehicle.xbhv"
            ;;
        mod_speed_clip_high_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-mod-speed-clip-high-pass-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/mod-speed-clip-high-pass-vehicle.xmoos"
            ;;
        mod_speed_clip_low_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-mod-speed-clip-low-pass-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/mod-speed-clip-low-pass-vehicle.xmoos"
            ;;
        bad_runtime_update_recover_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-bad-runtime-update-recover-pass-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/bad-runtime-update-recover-pass-vehicle.xmoos"
            ;;
        fierce_zigging_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-fierce-zigging-pass-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/fierce-heading-sample-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/fierce-zigging-pass-vehicle.xbhv"
            ;;
        delta_heading_alias_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-fierce-zigging-pass-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/fierce-heading-sample-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/delta-heading-alias-pass-vehicle.xbhv"
            ;;
        bad_zig_angle_low_fail)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-quick-fail-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/helm-malconfig-fail-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-zig-angle-low-fail-vehicle.xbhv"
            ;;
        bad_zig_angle_high_fail)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-quick-fail-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/helm-malconfig-fail-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-zig-angle-high-fail-vehicle.xbhv"
            ;;
        bad_zig_first_fail)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-quick-fail-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/helm-malconfig-fail-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-zig-first-fail-vehicle.xbhv"
            ;;
        bad_max_zig_zags_fail)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-quick-fail-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/helm-malconfig-fail-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-max-zig-zags-fail-vehicle.xbhv"
            ;;
        bad_max_stem_odo_fail)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-quick-fail-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/helm-malconfig-fail-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-max-stem-odo-fail-vehicle.xbhv"
            ;;
        bad_speed_fail)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-quick-fail-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/helm-malconfig-fail-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-speed-fail-vehicle.xbhv"
            ;;
        bad_delta_heading_fail)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-quick-fail-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/helm-malconfig-fail-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-delta-heading-fail-vehicle.xbhv"
            ;;
        bad_stale_nav_thresh_fail)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-quick-fail-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/helm-malconfig-fail-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-stale-nav-thresh-fail-vehicle.xbhv"
            ;;
        bad_hdg_thresh_fail)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-quick-fail-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/helm-malconfig-fail-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-hdg-thresh-fail-vehicle.xbhv"
            ;;
        bad_visual_hint_fail)
            CASE_SHORE_PATCH="$HARNESS_DIR/eval-quick-fail-shoreside.xmoos"
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/helm-malconfig-fail-vehicle.xmoos"
            CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-visual-hint-fail-vehicle.xbhv"
            ;;
        *)
            echo "$ME: Unknown case: [$CASE_NAME]"
            return 1
            ;;
    esac
    return 0
}

apply_case_overlays() {
    local case_name="$1"
    local workdir="$2"
    local patch
    local -a shore_patches=()
    local -a vehicle_patches=()

    get_case_config "$case_name" || return 1

    if [ "$LOG_MODE" = full ]; then
        shore_patches+=("$workdir/full-logging-shoreside.xmoos")
        vehicle_patches+=("$workdir/full-logging-vehicle.xmoos")
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
    if [ -n "$CASE_VEH_MOOS_PATCH" ]; then
        vehicle_patches+=("$CASE_VEH_MOOS_PATCH")
    fi
    if [ "${#vehicle_patches[@]}" -gt 0 ]; then
        for patch in "${vehicle_patches[@]}"; do
            [ -f "$patch" ] || return 1
        done
        nspatch "$workdir/meta_vehicle.moos" \
            "${vehicle_patches[@]}" "$workdir/meta_vehicle.moosx" || return 1
    fi
    if [ -n "$CASE_VEH_BHV_PATCH" ]; then
        [ -f "$CASE_VEH_BHV_PATCH" ] || return 1
        nspatch "$workdir/meta_vehicle.bhv" \
            "$CASE_VEH_BHV_PATCH" "$workdir/meta_vehicle.bhvx" || return 1
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

    line=$(without_case_field "$line")
    printf 'case=%s %s\n' "$case_name" "$line" > "$result_file"
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
            --veh_mport="$((case_base + 1))"
            --shore_pshare="$((case_base + PSHARE_OFFSET))"
            --veh_pshare="$((case_base + PSHARE_OFFSET + 1))"
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
last_port=$((PORT_BASE + (total - 1) * PORT_STRIDE + PSHARE_OFFSET + 1))
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
