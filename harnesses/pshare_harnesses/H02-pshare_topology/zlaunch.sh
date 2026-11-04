#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H02-pshare_topology
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
MISSION_DIR="$REPO_DIR/missions/pshare_missions/pshare_topology"
TEARDOWN_HELPER="$REPO_DIR/scripts/moos_scoped_teardown.sh"
RESULTS_FILE="$HARNESS_DIR/results.txt"
RUNS_DIR="$HARNESS_DIR/.harness_runs"
RUN_ROOT=""

TIME_WARP=10
MAX_TIME=65
JOBS=1
PORT_BASE=9000
PORT_STRIDE=50
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
    pshare_topology_fanin_pass
    pshare_topology_competing_update_pass
    pshare_topology_multi_input_port_pass
    pshare_topology_input_route_list_pass
    pshare_topology_multicast_multi_listener_pass
    pshare_topology_dynamic_input_route_pass
    pshare_topology_dynamic_multicast_input_pass
    pshare_topology_custom_multicast_base_pass
    pshare_topology_unicast_relay_branch_pass
    pshare_topology_route_list_branch_pass
    pshare_topology_alias_cmd_route_pass
    pshare_topology_runtime_route_pass
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
  --gui              Run one explicit case without headless mode
  --nogui, -ng       Headless launch, no gui (default)

Cases:
EOF
    for case_name in "${CASES[@]}"; do
        printf '  %s\n' "$case_name"
    done
    cat <<EOF

Examples:
  ./$ME
  ./$ME --case=pshare_topology_fanin_pass
  ./$ME --log=full --case=pshare_topology_fanin_pass
  ./$ME --jobs=2 --port_base=9000
  ./$ME --just_make --case=pshare_topology_multicast_multi_listener_pass
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

get_case_config() {
    local case_name="$1"
    CASE_SHORE_PATCH=""
    CASE_ALPHA_PATCH=""
    CASE_BRAVO_PATCH=""
    CASE_RELAY_PATCH=""
    CASE_ALPHA_FULL_LOG_PATCH=""
    CASE_RELAY_FULL_LOG_PATCH=""

    case "$case_name" in
        pshare_topology_fanin_pass)
            ;;
        pshare_topology_competing_update_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/pshare-topology-competing-update-pass-shoreside.xmoos"
            CASE_ALPHA_PATCH="$HARNESS_DIR/pshare-topology-competing-update-pass-alpha.xmoos"
            CASE_BRAVO_PATCH="$HARNESS_DIR/pshare-topology-competing-update-pass-bravo.xmoos"
            ;;
        pshare_topology_multi_input_port_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/pshare-topology-multi-input-port-pass-shoreside.xmoos"
            CASE_ALPHA_PATCH="$HARNESS_DIR/pshare-topology-multi-input-port-pass-alpha.xmoos"
            CASE_BRAVO_PATCH="$HARNESS_DIR/pshare-topology-multi-input-port-pass-bravo.xmoos"
            ;;
        pshare_topology_input_route_list_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/pshare-topology-input-route-list-pass-shoreside.xmoos"
            CASE_ALPHA_PATCH="$HARNESS_DIR/pshare-topology-input-route-list-pass-alpha.xmoos"
            CASE_BRAVO_PATCH="$HARNESS_DIR/pshare-topology-input-route-list-pass-bravo.xmoos"
            ;;
        pshare_topology_multicast_multi_listener_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/pshare-topology-multicast-multi-listener-pass-shoreside.xmoos"
            CASE_ALPHA_PATCH="$HARNESS_DIR/pshare-topology-multicast-multi-listener-pass-alpha.xmoos"
            CASE_RELAY_PATCH="$HARNESS_DIR/pshare-topology-multicast-multi-listener-pass-relay.xmoos"
            CASE_RELAY_FULL_LOG_PATCH="$HARNESS_DIR/pshare-topology-multicast-multi-listener-pass-full-logging-relay.xmoos"
            ;;
        pshare_topology_dynamic_input_route_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/pshare-topology-dynamic-input-route-pass-shoreside.xmoos"
            CASE_BRAVO_PATCH="$HARNESS_DIR/pshare-topology-dynamic-input-route-pass-bravo.xmoos"
            ;;
        pshare_topology_dynamic_multicast_input_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/pshare-topology-dynamic-multicast-input-pass-shoreside.xmoos"
            CASE_ALPHA_PATCH="$HARNESS_DIR/pshare-topology-dynamic-multicast-input-pass-alpha.xmoos"
            ;;
        pshare_topology_custom_multicast_base_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/pshare-topology-custom-multicast-base-pass-shoreside.xmoos"
            CASE_ALPHA_PATCH="$HARNESS_DIR/pshare-topology-custom-multicast-base-pass-alpha.xmoos"
            ;;
        pshare_topology_unicast_relay_branch_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/pshare-topology-unicast-relay-branch-pass-shoreside.xmoos"
            CASE_ALPHA_PATCH="$HARNESS_DIR/pshare-topology-unicast-relay-branch-pass-alpha.xmoos"
            CASE_RELAY_PATCH="$HARNESS_DIR/pshare-topology-unicast-relay-branch-pass-relay.xmoos"
            CASE_RELAY_FULL_LOG_PATCH="$HARNESS_DIR/pshare-topology-unicast-relay-branch-pass-full-logging-relay.xmoos"
            ;;
        pshare_topology_route_list_branch_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/pshare-topology-route-list-branch-pass-shoreside.xmoos"
            CASE_ALPHA_PATCH="$HARNESS_DIR/pshare-topology-route-list-branch-pass-alpha.xmoos"
            CASE_RELAY_PATCH="$HARNESS_DIR/pshare-topology-route-list-branch-pass-relay.xmoos"
            CASE_RELAY_FULL_LOG_PATCH="$HARNESS_DIR/pshare-topology-route-list-branch-pass-full-logging-relay.xmoos"
            ;;
        pshare_topology_alias_cmd_route_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/pshare-topology-alias-cmd-route-pass-shoreside.xmoos"
            CASE_ALPHA_PATCH="$HARNESS_DIR/pshare-topology-alias-cmd-route-pass-alpha.xmoos"
            CASE_ALPHA_FULL_LOG_PATCH="$HARNESS_DIR/pshare-topology-alias-cmd-route-pass-full-logging-alpha.xmoos"
            ;;
        pshare_topology_runtime_route_pass)
            CASE_SHORE_PATCH="$HARNESS_DIR/pshare-topology-runtime-route-pass-shoreside.xmoos"
            CASE_ALPHA_PATCH="$HARNESS_DIR/pshare-topology-runtime-route-pass-alpha.xmoos"
            ;;
        *) return 1 ;;
    esac
}

apply_case_overlays() {
    local case_name="$1"
    local workdir="$2"
    local patch
    local -a shore_patches=()
    local -a alpha_patches=()
    local -a bravo_patches=()
    local -a relay_patches=()

    get_case_config "$case_name" || return 1

    if [ "$LOG_MODE" = full ]; then
        shore_patches+=("$workdir/full-logging-shoreside.xmoos")
        if [ -z "$CASE_ALPHA_FULL_LOG_PATCH" ]; then
            alpha_patches+=("$workdir/full-logging-alpha.xmoos")
        fi
        bravo_patches+=("$workdir/full-logging-bravo.xmoos")
        if [ -z "$CASE_RELAY_FULL_LOG_PATCH" ]; then
            relay_patches+=("$workdir/full-logging-relay.xmoos")
        fi
    fi
    if [ -n "$CASE_SHORE_PATCH" ]; then
        shore_patches+=("$CASE_SHORE_PATCH")
    fi
    if [ -n "$CASE_ALPHA_PATCH" ] && \
       { [ "$LOG_MODE" != full ] || [ -z "$CASE_ALPHA_FULL_LOG_PATCH" ]; }; then
        alpha_patches+=("$CASE_ALPHA_PATCH")
    fi
    if [ -n "$CASE_BRAVO_PATCH" ]; then
        bravo_patches+=("$CASE_BRAVO_PATCH")
    fi
    if [ -n "$CASE_RELAY_PATCH" ] && \
       { [ "$LOG_MODE" != full ] || [ -z "$CASE_RELAY_FULL_LOG_PATCH" ]; }; then
        relay_patches+=("$CASE_RELAY_PATCH")
    fi
    if [ "$LOG_MODE" = full ] && [ -n "$CASE_ALPHA_FULL_LOG_PATCH" ]; then
        alpha_patches+=("$CASE_ALPHA_FULL_LOG_PATCH")
    fi
    if [ "$LOG_MODE" = full ] && [ -n "$CASE_RELAY_FULL_LOG_PATCH" ]; then
        relay_patches+=("$CASE_RELAY_FULL_LOG_PATCH")
    fi
    if [ "${#shore_patches[@]}" -gt 0 ]; then
        for patch in "${shore_patches[@]}"; do
            [ -f "$patch" ] || return 1
        done
        nspatch "$workdir/meta_shoreside.moos" \
            "${shore_patches[@]}" "$workdir/meta_shoreside.moosx" || return 1
    fi
    if [ "${#alpha_patches[@]}" -gt 0 ]; then
        for patch in "${alpha_patches[@]}"; do
            [ -f "$patch" ] || return 1
        done
        nspatch "$workdir/meta_alpha.moos" \
            "${alpha_patches[@]}" "$workdir/meta_alpha.moosx" || return 1
    fi
    if [ "${#bravo_patches[@]}" -gt 0 ]; then
        for patch in "${bravo_patches[@]}"; do
            [ -f "$patch" ] || return 1
        done
        nspatch "$workdir/meta_bravo.moos" \
            "${bravo_patches[@]}" "$workdir/meta_bravo.moosx" || return 1
    fi
    if [ "${#relay_patches[@]}" -gt 0 ]; then
        for patch in "${relay_patches[@]}"; do
            [ -f "$patch" ] || return 1
        done
        nspatch "$workdir/meta_relay.moos" \
            "${relay_patches[@]}" "$workdir/meta_relay.moosx" || return 1
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
            --alpha_mport="$((case_base + 1))"
            --bravo_mport="$((case_base + 2))"
            --relay_mport="$((case_base + 3))"
            --shore_pshare="$((case_base + 10))"
            --alpha_pshare="$((case_base + 11))"
            --bravo_pshare="$((case_base + 12))"
            --relay_pshare="$((case_base + 13))"
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
last_port=$((PORT_BASE + (total - 1) * PORT_STRIDE + 13))
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
