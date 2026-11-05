#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H02-ufield_broker_bridge
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
MISSION_DIR="$REPO_DIR/missions/ufield_comms_missions/ufield_comms_unit"
TEARDOWN_HELPER="$REPO_DIR/scripts/moos_scoped_teardown.sh"
RESULTS_FILE="$HARNESS_DIR/results.txt"
RUNS_DIR="$HARNESS_DIR/.harness_runs"
RUN_ROOT=""

TIME_WARP=20
MAX_TIME=4000
JOBS=1
PORT_BASE=4000
PORT_STRIDE=30
PSHARE_OFFSET=$((PORT_STRIDE / 2))
KEEP_WORKDIRS=no
VERBOSE=no
JUST_MAKE=no
CORE_ONLY=no
LOG_MODE=minimal
DISPLAY_ARGS=(--nogui)
CASE=""
CLEANED=no
CLEANING=no
CLEANUP_FAILED=no
FINISH_FATAL_REASON=""

CASES=(
    broker_handshake_pass
    shore_qbridge_expansion_pass
    shore_custom_bridge_pass
    node_custom_bridge_pass
    keyword_mismatch_status_pass
    shore_bridge_tokens_pass
    node_mediated_bridge_pass
    shore_try_vnode_pass
    shore_minimal_autobridge_pass
    node_minimal_autobridge_pass
    shore_default_alias_pass
    shore_try_vnode_default_port_pass
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
  --max_time=<secs>  Maximum time passed to each mission wrapper
  --case=<name>      Run one named case
  --core_only        Run the 11 core cases; omit the pMediator extension case
  --jobs=<n>         Run up to n cases concurrently with rolling scheduling
  --port_base=<n>    Base MOOS port for per-case blocks
  --keep_workdirs    Keep this invocation's isolated case directories
  --gui              Launch with pMarineViewer
  --nogui, -ng       Headless launch, no gui (default)

Cases:
EOF
    for case_name in "${CASES[@]}"; do
        printf '  %s\n' "$case_name"
    done
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
        --case=*) CASE="${arg#--case=}" ;;
        --core_only) CORE_ONLY=yes ;;
        --jobs=*) JOBS="${arg#--jobs=}" ;;
        --port_base=*) PORT_BASE="${arg#--port_base=}" ;;
        --max_time=*) MAX_TIME="${arg#--max_time=}" ;;
        --keep_workdirs) KEEP_WORKDIRS=yes ;;
        --verbose|-v) VERBOSE=yes ;;
        --just_make|-j) JUST_MAKE=yes ;;
        --log=*) LOG_MODE="${arg#--log=}" ;;
        --gui) DISPLAY_ARGS=(--gui) ;;
        --nogui|-ng) DISPLAY_ARGS=(--nogui) ;;
        --help|-h) usage; exit 0 ;;
        *[!0-9]*|'') die "bad argument: $arg" ;;
        *) TIME_WARP="$arg" ;;
    esac
done

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
case "$LOG_MODE" in
    minimal|full) ;;
    *) die "--log must be minimal or full" ;;
esac
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
                if [ "$CORE_ONLY" = yes ] && [ "$case_name" = node_mediated_bridge_pass ]; then
                    die "--core_only excludes node_mediated_bridge_pass; remove --core_only to run it"
                fi
                SELECTED_CASES=("$case_name")
                return 0
            fi
        done
        die "unknown case: $CASE"
    fi
    for case_name in "${CASES[@]}"; do
        if [ "$CORE_ONLY" = yes ] && [ "$case_name" = node_mediated_bridge_pass ]; then
            continue
        fi
        SELECTED_CASES+=("$case_name")
    done
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

    if [ -n "$RUN_ROOT" ] && [ -d "$RUN_ROOT" ]; then
        if ! stop_root "$RUN_ROOT"; then
            root_stopped=no
            CLEANUP_FAILED=yes
        fi
    fi
    for pid in "${!PID_CASE[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    if [ -n "$RUN_ROOT" ] && [ -d "$RUN_ROOT" ]; then
        if ! stop_root "$RUN_ROOT"; then
            root_stopped=no
            CLEANUP_FAILED=yes
        fi
        if [ "$KEEP_WORKDIRS" != yes ] && [ "$root_stopped" = yes ] && [ "$CLEANUP_FAILED" = no ]; then
            rm -rf -- "$RUN_ROOT" || CLEANUP_FAILED=yes
            [ ! -e "$RUN_ROOT" ] || CLEANUP_FAILED=yes
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
    SHORE_PATCH=""
    VEHICLE_PATCH=""
    EVAL_PATCH=""
    EXTRA_CHECK=""
    VEHICLE_ANTLER_PATCH=no
    case "$case_name" in
        broker_handshake_pass)
            EVAL_PATCH="$HARNESS_DIR/normal-summary-eval-shoreside.xmoos"
            EXTRA_CHECK=broker_handshake
            ;;
        shore_qbridge_expansion_pass)
            EVAL_PATCH="$HARNESS_DIR/normal-summary-eval-shoreside.xmoos"
            EXTRA_CHECK=shore_qbridge_expansion
            ;;
        shore_custom_bridge_pass)
            SHORE_PATCH="$HARNESS_DIR/shore-custom-bridge-shoreside.xmoos"
            EVAL_PATCH="$HARNESS_DIR/shore-custom-summary-eval-shoreside.xmoos"
            EXTRA_CHECK=shore_custom_bridge
            ;;
        node_custom_bridge_pass)
            VEHICLE_PATCH="$HARNESS_DIR/node-custom-bridge-vehicle.xmoos"
            EVAL_PATCH="$HARNESS_DIR/node-custom-summary-eval-shoreside.xmoos"
            EXTRA_CHECK=node_custom_bridge
            ;;
        keyword_mismatch_status_pass)
            SHORE_PATCH="$HARNESS_DIR/keyword-mismatch-shoreside.xmoos"
            EVAL_PATCH="$HARNESS_DIR/keyword-rejection-eval-shoreside.xmoos"
            ;;
        shore_bridge_tokens_pass)
            SHORE_PATCH="$HARNESS_DIR/shore-bridge-tokens-shoreside.xmoos"
            EVAL_PATCH="$HARNESS_DIR/bridge-tokens-summary-eval-shoreside.xmoos"
            EXTRA_CHECK=shore_bridge_tokens
            ;;
        node_mediated_bridge_pass)
            VEHICLE_PATCH="$HARNESS_DIR/node-mediated-bridge-vehicle.xmoos"
            VEHICLE_ANTLER_PATCH=yes
            EVAL_PATCH="$HARNESS_DIR/mediated-eval-shoreside.xmoos"
            EXTRA_CHECK=node_mediated_bridge
            ;;
        shore_try_vnode_pass)
            SHORE_PATCH="$HARNESS_DIR/try-vnode-shoreside.xmoos"
            EVAL_PATCH="$HARNESS_DIR/try-vnode-summary-eval-shoreside.xmoos"
            EXTRA_CHECK=shore_try_vnode
            ;;
        shore_minimal_autobridge_pass)
            SHORE_PATCH="$HARNESS_DIR/minimal-autobridge-shoreside.xmoos"
            EVAL_PATCH="$HARNESS_DIR/shore-minimal-summary-eval-shoreside.xmoos"
            ;;
        node_minimal_autobridge_pass)
            VEHICLE_PATCH="$HARNESS_DIR/node-minimal-autobridge-vehicle.xmoos"
            EVAL_PATCH="$HARNESS_DIR/node-minimal-summary-eval-shoreside.xmoos"
            EXTRA_CHECK=node_minimal_autobridge
            ;;
        shore_default_alias_pass)
            SHORE_PATCH="$HARNESS_DIR/shore-default-alias-shoreside.xmoos"
            EVAL_PATCH="$HARNESS_DIR/default-alias-summary-eval-shoreside.xmoos"
            EXTRA_CHECK=shore_default_alias
            ;;
        shore_try_vnode_default_port_pass)
            SHORE_PATCH="$HARNESS_DIR/try-vnode-default-port-shoreside.xmoos"
            EVAL_PATCH="$HARNESS_DIR/try-vnode-summary-eval-shoreside.xmoos"
            EXTRA_CHECK=shore_try_vnode_default_port
            ;;
        *) return 1 ;;
    esac
}

prepare_case() {
    local case_name="$1"
    local workdir="$2"
    local -a shore_patches=()
    local -a vehicle_patches=()

    get_case_config "$case_name" || return 1
    [ -z "$SHORE_PATCH" ] || [ -f "$SHORE_PATCH" ] || return 1
    [ -z "$VEHICLE_PATCH" ] || [ -f "$VEHICLE_PATCH" ] || return 1
    [ -n "$EVAL_PATCH" ] && [ -f "$EVAL_PATCH" ] || return 1
    rm -rf "$workdir"
    mkdir -p "$workdir" || return 1
    cp -R "$MISSION_DIR"/. "$workdir"/ || return 1
    (
        cd "$workdir" || exit 1
        ./clean.sh >/dev/null 2>&1
    ) || return 1
    shore_patches+=("$workdir/full-logging-shoreside.xmoos")
    if [ "$VEHICLE_ANTLER_PATCH" = no ]; then
        vehicle_patches+=("$workdir/full-logging-vehicle.xmoos")
    fi
    [ -z "$SHORE_PATCH" ] || shore_patches+=("$SHORE_PATCH")
    shore_patches+=("$EVAL_PATCH")
    nspatch "$workdir/meta_shoreside.moos" \
        "${shore_patches[@]}" "$workdir/meta_shoreside.moosx" || return 1
    [ -z "$VEHICLE_PATCH" ] || vehicle_patches+=("$VEHICLE_PATCH")
    nspatch "$workdir/meta_vehicle.moos" \
        "${vehicle_patches[@]}" "$workdir/meta_vehicle.moosx" || return 1
    if [ "$LOG_MODE" = minimal ]; then
        (
            cd "$workdir" || exit 1
            ./prepare_logging_mode.sh minimal grading \
                meta_shoreside.moosx meta_vehicle.moosx
        ) || return 1
    fi
}

shore_alog() {
    find "$1" -path '*XLOG_SHORESIDE*/*.alog' -print | sort | tail -n 1
}

vehicle_alog() {
    local workdir="$1"
    local vname="$2"
    find "$workdir" -path "*LOG_${vname}*/*.alog" -print | sort | tail -n 1
}

alog_var_has_pattern() {
    local alog="$1"
    local var="$2"
    local pattern="$3"
    [ -n "$alog" ] || return 1
    aloggrep "$alog" "$var" --v --quiet 2>/dev/null | rg "$pattern" >/dev/null
}

alog_var_lacks_pattern() {
    local alog="$1"
    local var="$2"
    local pattern="$3"
    [ -n "$alog" ] || return 1
    ! aloggrep "$alog" "$var" --v --quiet 2>/dev/null | rg "$pattern" >/dev/null
}

vehicle_has() {
    local workdir="$1" vname="$2" var="$3" pattern="$4"
    local alog
    alog=$(vehicle_alog "$workdir" "$vname")
    alog_var_has_pattern "$alog" "$var" "$pattern"
}

vehicle_lacks() {
    local workdir="$1" vname="$2" var="$3" pattern="$4"
    local alog
    alog=$(vehicle_alog "$workdir" "$vname")
    alog_var_lacks_pattern "$alog" "$var" "$pattern"
}

shore_has() {
    local workdir="$1" var="$2" pattern="$3"
    local alog
    alog=$(shore_alog "$workdir")
    alog_var_has_pattern "$alog" "$var" "$pattern"
}

supplemental_check_ok() {
    local check="$1"
    local workdir="$2"

    case "$check" in
        broker_handshake)
            shore_has "$workdir" NODE_BROKER_PING 'community=abe' &&
            shore_has "$workdir" NODE_BROKER_PING 'community=ben' &&
            shore_has "$workdir" NODE_BROKER_ACK_ABE 'status=ok,key=0' &&
            shore_has "$workdir" NODE_BROKER_ACK_BEN 'status=ok,key=0' &&
            shore_has "$workdir" NODE_BROKER_VACK 'abe' &&
            shore_has "$workdir" NODE_BROKER_VACK 'ben' &&
            vehicle_has "$workdir" ABE NODE_BROKER_ACK 'status=ok,key=0' &&
            vehicle_has "$workdir" BEN NODE_BROKER_ACK 'status=ok,key=0' &&
            vehicle_has "$workdir" ABE NODE_PSHARE_VARS '^ACK_MESSAGE,NODE_MESSAGE,NODE_REPORT,REALMCAST,WATCHCAST,REALMCAST_CHANNELS,APPCAST,NODE_PSHARE_VARS$' &&
            vehicle_has "$workdir" BEN NODE_PSHARE_VARS '^ACK_MESSAGE,NODE_MESSAGE,NODE_REPORT,REALMCAST,WATCHCAST,REALMCAST_CHANNELS,APPCAST,NODE_PSHARE_VARS$'
            ;;
        shore_qbridge_expansion)
            shore_has "$workdir" PSHARE_CMD 'src_name=NODE_REPORT_ALL,dest_name=NODE_REPORT' &&
            shore_has "$workdir" PSHARE_CMD 'src_name=NODE_REPORT_ABE,dest_name=NODE_REPORT' &&
            shore_has "$workdir" PSHARE_CMD 'src_name=NODE_REPORT_BEN,dest_name=NODE_REPORT' &&
            shore_has "$workdir" PSHARE_CMD 'src_name=NODE_MESSAGE_BEN,dest_name=NODE_MESSAGE' &&
            shore_has "$workdir" PSHARE_CMD 'src_name=ACK_MESSAGE_ABE,dest_name=ACK_MESSAGE'
            ;;
        shore_custom_bridge)
            shore_has "$workdir" PSHARE_CMD 'src_name=DEPLOY_ABE,dest_name=DEPLOY' &&
            shore_has "$workdir" PSHARE_CMD 'src_name=DEPLOY_BEN,dest_name=DEPLOY'
            ;;
        node_custom_bridge)
            vehicle_has "$workdir" ABE PSHARE_CMD 'src_name=CUSTOM_LOCAL,dest_name=CUSTOM_SHARED' &&
            vehicle_has "$workdir" BEN PSHARE_CMD 'src_name=CUSTOM_LOCAL,dest_name=CUSTOM_SHARED'
            ;;
        shore_bridge_tokens)
            shore_has "$workdir" PSHARE_CMD 'src_name=STATUS_abe,dest_name=STATUS' &&
            shore_has "$workdir" PSHARE_CMD 'src_name=STATUS_ben,dest_name=STATUS' &&
            shore_has "$workdir" PSHARE_CMD 'src_name=INDEX_1,dest_name=INDEXED_STATUS' &&
            shore_has "$workdir" PSHARE_CMD 'src_name=INDEX_2,dest_name=INDEXED_STATUS'
            ;;
        node_mediated_bridge)
            vehicle_has "$workdir" ABE PSHARE_CMD 'src_name=MEDIATED_MESSAGE_LOCAL,dest_name=MEDIATED_MESSAGE' &&
            vehicle_has "$workdir" BEN PSHARE_CMD 'src_name=MEDIATED_MESSAGE_LOCAL,dest_name=MEDIATED_MESSAGE' &&
            vehicle_lacks "$workdir" ABE PSHARE_CMD 'src_name=NODE_MESSAGE_LOCAL,dest_name=NODE_MESSAGE' &&
            vehicle_lacks "$workdir" BEN PSHARE_CMD 'src_name=NODE_MESSAGE_LOCAL,dest_name=NODE_MESSAGE'
            ;;
        shore_try_vnode)
            shore_has "$workdir" PSHARE_CMD 'src_name=TRY_SHORE_HOST,dest_name=TRY_SHORE_HOST,route=127.0.0.1:4999'
            ;;
        node_minimal_autobridge)
            vehicle_has "$workdir" ABE NODE_PSHARE_VARS '^ACK_MESSAGE,NODE_MESSAGE,NODE_REPORT$' &&
            vehicle_has "$workdir" BEN NODE_PSHARE_VARS '^ACK_MESSAGE,NODE_MESSAGE,NODE_REPORT$' &&
            vehicle_lacks "$workdir" ABE PSHARE_CMD 'src_name=NODE_PSHARE_VARS,dest_name=NODE_PSHARE_VARS' &&
            vehicle_lacks "$workdir" BEN PSHARE_CMD 'src_name=NODE_PSHARE_VARS,dest_name=NODE_PSHARE_VARS'
            ;;
        shore_default_alias)
            shore_has "$workdir" PSHARE_CMD 'src_name=FLEET_ALERT,dest_name=FLEET_ALERT,route=localhost:[0-9]+'
            ;;
        shore_try_vnode_default_port)
            shore_has "$workdir" PSHARE_CMD 'src_name=TRY_SHORE_HOST,dest_name=TRY_SHORE_HOST,route=127.0.0.1:9200'
            ;;
        '') return 0 ;;
        *) return 1 ;;
    esac
}

write_result() {
    local case_name="$1"
    local result_file="$2"
    local launch_rc="$3"
    local workdir="$4"
    local line grade_count mission_grade mission_rows provenance

    if [ "$JUST_MAKE" = yes ]; then
        if [ "$launch_rc" -eq 0 ]; then
            printf 'case=%s grade=pass mode=just_make\n' "$case_name" > "$result_file"
        else
            printf 'case=%s grade=fail reason=launch_error launch_rc=%s mode=just_make\n' "$case_name" "$launch_rc" > "$result_file"
        fi
        return 0
    fi
    if [ ! -f "$workdir/results.txt" ]; then
        printf 'case=%s grade=fail reason=missing_result_file launch_rc=%s\n' "$case_name" "$launch_rc" > "$result_file"
        return 0
    fi
    mission_rows=$(awk 'NF {count++} END {print count+0}' "$workdir/results.txt")
    if [ "$mission_rows" -eq 0 ]; then
        printf 'case=%s grade=fail reason=missing_result launch_rc=%s\n' "$case_name" "$launch_rc" > "$result_file"
        return 0
    fi
    if [ "$mission_rows" -ne 1 ]; then
        printf 'case=%s grade=fail reason=duplicate_results result_rows=%s\n' "$case_name" "$mission_rows" > "$result_file"
        return 0
    fi
    line=$(awk 'NF {print; exit}' "$workdir/results.txt")
    grade_count=$(field_count "$line" grade)
    if [ "$grade_count" -ne 1 ]; then
        printf 'case=%s grade=fail reason=malformed_result grade_fields=%s\n' "$case_name" "$grade_count" > "$result_file"
        return 0
    fi
    mission_grade=$(field_value "$line" grade || true)
    if [ "$mission_grade" != pass ] && [ "$mission_grade" != fail ]; then
        printf 'case=%s grade=fail reason=malformed_result mission_grade=%s\n' "$case_name" "${mission_grade:-missing}" > "$result_file"
        return 0
    fi
    if [ "$launch_rc" -ne 0 ]; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=launch_error launch_rc=%s%s\n' \
            "$case_name" "$launch_rc" "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi
    if [ "$mission_grade" = pass ] && ! supplemental_check_ok "$EXTRA_CHECK" "$workdir"; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=supplemental_route_check_failed%s\n' \
            "$case_name" "${provenance:+ $provenance}" > "$result_file"
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
    local result_line grade
    local -a launch_args

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
            --shore_mport="$case_base"
            --veh1_mport="$((case_base + 1))"
            --veh2_mport="$((case_base + 2))"
            --shore_pshare="$((case_base + PSHARE_OFFSET))"
            --veh1_pshare="$((case_base + PSHARE_OFFSET + 1))"
            --veh2_pshare="$((case_base + PSHARE_OFFSET + 2))"
            "$TIME_WARP"
        )
        [ "$JUST_MAKE" = yes ] && launch_args+=(--just_make)
        LOG_MODE_PREPARED=yes LOG_MODE_PREPARED_VALUE="$LOG_MODE" \
            ./zlaunch.sh --log="$LOG_MODE" "${launch_args[@]}"
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
    local case_dir workdir result_file log_file case_base pid

    case_base=$((PORT_BASE + case_idx * PORT_STRIDE))
    case_dir="$RUN_ROOT/case_$(printf '%03d' "$case_idx")_$case_name"
    workdir="$case_dir/mission"
    result_file="$case_dir/result.row"
    log_file="$case_dir/run.log"
    CASE_RESULT[case_idx]="$result_file"
    mkdir -p "$case_dir" || return 1
    (
        local rc=0
        set +e
        run_case "$case_name" "$workdir" "$result_file" "$case_base" > "$log_file" 2>&1
        rc=$?
        if [ ! -s "$result_file" ]; then
            printf 'case=%s grade=fail reason=missing_result launch_rc=%s\n' "$case_name" "$rc" > "$result_file"
        fi
        exit "$rc"
    ) &
    pid=$!
    PID_CASE[$pid]="$case_name"
    PID_RESULT[$pid]="$result_file"
    PID_LOG[$pid]="$log_file"
    PID_PORT_BASE[$pid]="$case_base"
    [ "$VERBOSE" != yes ] || printf 'event=start epoch=%s pid=%s case=%s port_base=%s workdir=%s\n' \
        "$(date +%s)" "$pid" "$case_name" "$case_base" "$workdir"
}

finish_one() {
    local done_pid="" wait_rc=0 case_name line grade reason

    FINISH_FATAL_REASON=""
    wait -p done_pid -n || wait_rc=$?
    if [ -z "${done_pid:-}" ] || [ -z "${PID_CASE[$done_pid]:-}" ]; then
        echo "$ME: scheduler could not identify completed worker rc=$wait_rc" >&2
        FINISH_FATAL_REASON=scheduler_state_error
        return 2
    fi
    case_name="${PID_CASE[$done_pid]}"
    line=$(awk 'NF {print; exit}' "${PID_RESULT[$done_pid]}" 2>/dev/null)
    grade=$(field_value "$line" grade || true)
    reason=$(field_value "$line" reason || true)
    if [ "$wait_rc" -ne 0 ] && [ "$grade" = pass ]; then
        printf 'case=%s grade=fail reason=worker_error worker_rc=%s\n' "$case_name" "$wait_rc" > "${PID_RESULT[$done_pid]}"
        grade=fail
    fi
    [ "$VERBOSE" != yes ] || printf 'event=finish epoch=%s pid=%s case=%s rc=%s grade=%s port_base=%s log=%s\n' \
        "$(date +%s)" "$done_pid" "$case_name" "$wait_rc" "${grade:-missing}" \
        "${PID_PORT_BASE[$done_pid]}" "${PID_LOG[$done_pid]}"
    unset 'PID_CASE[$done_pid]' 'PID_RESULT[$done_pid]' 'PID_LOG[$done_pid]' 'PID_PORT_BASE[$done_pid]'
    if [ "$reason" = teardown_error ]; then
        FINISH_FATAL_REASON=teardown_error
        return 2
    fi
    [ "$grade" = pass ]
}

abort_pending() {
    local next_idx="$1" total="$2" fatal_reason="$3" case_idx case_name case_dir result_file
    CLEANUP_FAILED=yes
    echo "$ME: stopping scheduler refill after $fatal_reason" >&2
    for ((case_idx = next_idx; case_idx < total; case_idx++)); do
        case_name="${SELECTED_CASES[$case_idx]}"
        case_dir="$RUN_ROOT/case_$(printf '%03d' "$case_idx")_$case_name"
        result_file="$case_dir/result.row"
        CASE_RESULT[case_idx]="$result_file"
        mkdir -p "$case_dir" || continue
        printf 'case=%s grade=fail reason=scheduler_aborted_after_%s\n' "$case_name" "$fatal_reason" > "$result_file"
    done
}

aggregate_results() {
    local total="${#SELECTED_CASES[@]}" case_idx case_name result_file row_count line row_case grade_count grade
    FINAL_FAILURES=0
    RESULT_ROWS=0
    : > "$RESULTS_FILE"
    for ((case_idx = 0; case_idx < total; case_idx++)); do
        case_name="${SELECTED_CASES[$case_idx]}"
        result_file="${CASE_RESULT[$case_idx]:-}"
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
if [ "$JUST_MAKE" != yes ]; then
    for selected_case in "${SELECTED_CASES[@]}"; do
        if [ "$selected_case" = node_mediated_bridge_pass ] && ! command -v pMediator >/dev/null 2>&1; then
            die "node_mediated_bridge_pass requires pMediator from moos-ivp-swarm on PATH; build that dependency or use --core_only"
        fi
    done
    command -v rg >/dev/null 2>&1 || die "live broker checks require ripgrep (rg) on PATH"
fi
total=${#SELECTED_CASES[@]}
if [ "${DISPLAY_ARGS[0]}" = --gui ] && [ "$total" -ne 1 ]; then
    die "--gui requires one explicit --case"
fi
last_port=$((PORT_BASE + (total - 1) * PORT_STRIDE + PSHARE_OFFSET + 2))
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
        start_case "$next" && active=$((active + 1))
        next=$((next + 1))
    done
    if [ "$active" -gt 0 ]; then
        finish_rc=0
        finish_one || finish_rc=$?
        if [ "$finish_rc" -eq 2 ] && [ "$FINISH_FATAL_REASON" = scheduler_state_error ]; then
            abort_pending "$next" "$total" "$FINISH_FATAL_REASON"
            next=$total
            scheduler_broken=yes
            break
        fi
        active=$((active - 1))
        if [ "$finish_rc" -eq 2 ]; then
            abort_pending "$next" "$total" "$FINISH_FATAL_REASON"
            next=$total
        fi
    fi
done

[ "$scheduler_broken" != yes ] || cleanup_runtime
aggregate_results
if [ "$RESULT_ROWS" -ne "$total" ] || { [ "$total" -gt 0 ] && [ "$RESULT_ROWS" -eq 0 ]; }; then
    echo "$ME: expected $total result rows but wrote $RESULT_ROWS" >&2
    FINAL_FAILURES=$((FINAL_FAILURES + 1))
fi

cleanup_runtime
elapsed_seconds=$SECONDS
[ -d "$RUN_ROOT" ] && kept_root="$RUN_ROOT" || kept_root=none
[ "$CLEANUP_FAILED" != yes ] || FINAL_FAILURES=$((FINAL_FAILURES + 1))
trap - EXIT INT TERM PIPE

printf 'results=%s failures=%s total=%s jobs=%s log_mode=%s elapsed_seconds=%s bash=%s workdirs=%s\n' \
    "$RESULTS_FILE" "$FINAL_FAILURES" "$total" "$JOBS" "$LOG_MODE" "$elapsed_seconds" "$BASH_VERSION" "$kept_root"

[ "$FINAL_FAILURES" -eq 0 ]
