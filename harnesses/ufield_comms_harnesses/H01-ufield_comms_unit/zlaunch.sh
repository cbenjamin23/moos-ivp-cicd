#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H01-ufield_comms_unit
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
LOG_MODE=minimal
DISPLAY_ARGS=(--nogui)
CASE=""
CLEANED=no
CLEANING=no
CLEANUP_FAILED=no
FINISH_FATAL_REASON=""

CASES=(
    baseline_broker_comms_pass
    critical_range_override_pass
    shared_node_reports_pass
    pulse_disabled_pass
    range_block_pass
    zero_range_block_pass
    drop_all_reports_pass
    far_range_block_pass
    no_limit_far_pass
    max_msg_length_block_pass
    dest_specific_message_pass
    dest_group_message_pass
    ack_requested_mediated_pass
    double_val_message_pass
    unknown_dest_block_pass
    ghost_source_block_pass
    invalid_ack_block_pass
    msg_group_filter_pass
    report_group_filter_pass
    stealth_range_block_pass
    earange_extend_pass
    stale_message_block_pass
    min_msg_interval_filter_pass
    runtime_range_extend_pass
    runtime_stealth_block_pass
    runtime_earange_extend_pass
    runtime_drop_all_pass
    runtime_pulse_disabled_pass
    runtime_shared_reports_pass
    shared_node_reports_numeric_pass
    min_rpt_interval_filter_pass
    stale_time_unlimited_pass
    max_msg_length_unlimited_pass
    earrange_alias_extend_pass
    critical_group_override_pass
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
    INIT_FIXTURE=""
    case "$case_name" in
        baseline_broker_comms_pass) ;;
        critical_range_override_pass) SHORE_PATCH="$HARNESS_DIR/critical-range-override-pass-shoreside.xmoos" ;;
        shared_node_reports_pass) SHORE_PATCH="$HARNESS_DIR/shared-node-reports-pass-shoreside.xmoos" ;;
        pulse_disabled_pass) SHORE_PATCH="$HARNESS_DIR/pulse-disabled-pass-shoreside.xmoos" ;;
        range_block_pass) SHORE_PATCH="$HARNESS_DIR/range-block-pass-shoreside.xmoos" ;;
        zero_range_block_pass) SHORE_PATCH="$HARNESS_DIR/zero-range-block-pass-shoreside.xmoos" ;;
        drop_all_reports_pass) SHORE_PATCH="$HARNESS_DIR/drop-all-reports-pass-shoreside.xmoos" ;;
        far_range_block_pass)
            SHORE_PATCH="$HARNESS_DIR/far-range-block-pass-shoreside.xmoos"
            INIT_FIXTURE="$HARNESS_DIR/init-field-far.sh"
            ;;
        no_limit_far_pass)
            SHORE_PATCH="$HARNESS_DIR/no-limit-far-pass-shoreside.xmoos"
            INIT_FIXTURE="$HARNESS_DIR/init-field-far.sh"
            ;;
        max_msg_length_block_pass) SHORE_PATCH="$HARNESS_DIR/max-msg-length-block-pass-shoreside.xmoos" ;;
        dest_specific_message_pass)
            SHORE_PATCH="$HARNESS_DIR/dest-specific-message-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/dest-specific-message-pass-vehicle.xmoos"
            ;;
        dest_group_message_pass)
            SHORE_PATCH="$HARNESS_DIR/dest-group-message-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/dest-group-message-pass-vehicle.xmoos"
            ;;
        ack_requested_mediated_pass)
            SHORE_PATCH="$HARNESS_DIR/ack-requested-mediated-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/ack-requested-mediated-pass-vehicle.xmoos"
            ;;
        double_val_message_pass)
            SHORE_PATCH="$HARNESS_DIR/double-val-message-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/double-val-message-pass-vehicle.xmoos"
            ;;
        unknown_dest_block_pass)
            SHORE_PATCH="$HARNESS_DIR/unknown-dest-block-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/unknown-dest-block-pass-vehicle.xmoos"
            ;;
        ghost_source_block_pass)
            SHORE_PATCH="$HARNESS_DIR/ghost-source-block-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/ghost-source-block-pass-vehicle.xmoos"
            ;;
        invalid_ack_block_pass)
            SHORE_PATCH="$HARNESS_DIR/invalid-ack-block-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/invalid-ack-block-pass-vehicle.xmoos"
            ;;
        msg_group_filter_pass)
            SHORE_PATCH="$HARNESS_DIR/msg-group-filter-pass-shoreside.xmoos"
            INIT_FIXTURE="$HARNESS_DIR/init-field-split-groups.sh"
            ;;
        report_group_filter_pass)
            SHORE_PATCH="$HARNESS_DIR/report-group-filter-pass-shoreside.xmoos"
            INIT_FIXTURE="$HARNESS_DIR/init-field-split-groups.sh"
            ;;
        stealth_range_block_pass) SHORE_PATCH="$HARNESS_DIR/stealth-range-block-pass-shoreside.xmoos" ;;
        earange_extend_pass) SHORE_PATCH="$HARNESS_DIR/earange-extend-pass-shoreside.xmoos" ;;
        stale_message_block_pass)
            SHORE_PATCH="$HARNESS_DIR/stale-message-block-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/stale-reports-vehicle.xmoos"
            ;;
        min_msg_interval_filter_pass)
            SHORE_PATCH="$HARNESS_DIR/min-msg-interval-filter-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/min-msg-interval-filter-pass-vehicle.xmoos"
            ;;
        runtime_range_extend_pass) SHORE_PATCH="$HARNESS_DIR/runtime-range-extend-pass-shoreside.xmoos" ;;
        runtime_stealth_block_pass)
            SHORE_PATCH="$HARNESS_DIR/runtime-stealth-block-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/runtime-before-after-vehicle.xmoos"
            ;;
        runtime_earange_extend_pass)
            SHORE_PATCH="$HARNESS_DIR/runtime-earange-extend-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/runtime-before-after-vehicle.xmoos"
            ;;
        runtime_drop_all_pass)
            SHORE_PATCH="$HARNESS_DIR/runtime-drop-all-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/runtime-before-after-vehicle.xmoos"
            ;;
        runtime_pulse_disabled_pass)
            SHORE_PATCH="$HARNESS_DIR/runtime-pulse-disabled-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/late-reports-vehicle.xmoos"
            ;;
        runtime_shared_reports_pass) SHORE_PATCH="$HARNESS_DIR/runtime-shared-reports-pass-shoreside.xmoos" ;;
        shared_node_reports_numeric_pass) SHORE_PATCH="$HARNESS_DIR/shared-node-reports-numeric-pass-shoreside.xmoos" ;;
        min_rpt_interval_filter_pass) SHORE_PATCH="$HARNESS_DIR/min-rpt-interval-filter-pass-shoreside.xmoos" ;;
        stale_time_unlimited_pass)
            SHORE_PATCH="$HARNESS_DIR/stale-time-unlimited-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/stale-reports-vehicle.xmoos"
            ;;
        max_msg_length_unlimited_pass)
            SHORE_PATCH="$HARNESS_DIR/max-msg-length-unlimited-pass-shoreside.xmoos"
            VEHICLE_PATCH="$HARNESS_DIR/max-msg-length-unlimited-pass-vehicle.xmoos"
            ;;
        earrange_alias_extend_pass) SHORE_PATCH="$HARNESS_DIR/earrange-alias-extend-pass-shoreside.xmoos" ;;
        critical_group_override_pass)
            SHORE_PATCH="$HARNESS_DIR/critical-group-override-pass-shoreside.xmoos"
            INIT_FIXTURE="$HARNESS_DIR/init-field-split-groups.sh"
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
    [ -z "$INIT_FIXTURE" ] || [ -f "$INIT_FIXTURE" ] || return 1
    rm -rf "$workdir"
    mkdir -p "$workdir" || return 1
    cp -R "$MISSION_DIR"/. "$workdir"/ || return 1
    (
        cd "$workdir" || exit 1
        ./clean.sh >/dev/null 2>&1
    ) || return 1
    if [ "$LOG_MODE" = full ]; then
        shore_patches+=("$workdir/full-logging-shoreside.xmoos")
        vehicle_patches+=("$workdir/full-logging-vehicle.xmoos")
    fi
    [ -z "$SHORE_PATCH" ] || shore_patches+=("$SHORE_PATCH")
    [ -z "$VEHICLE_PATCH" ] || vehicle_patches+=("$VEHICLE_PATCH")
    if [ "${#shore_patches[@]}" -gt 0 ]; then
        nspatch "$workdir/meta_shoreside.moos" \
            "${shore_patches[@]}" "$workdir/meta_shoreside.moosx" || return 1
    fi
    if [ "${#vehicle_patches[@]}" -gt 0 ]; then
        nspatch "$workdir/meta_vehicle.moos" \
            "${vehicle_patches[@]}" "$workdir/meta_vehicle.moosx" || return 1
    fi
    if [ "$LOG_MODE" = minimal ]; then
        [ -f "$workdir/meta_shoreside.moosx" ] || \
            cp "$workdir/meta_shoreside.moos" "$workdir/meta_shoreside.moosx" || return 1
        [ -f "$workdir/meta_vehicle.moosx" ] || \
            cp "$workdir/meta_vehicle.moos" "$workdir/meta_vehicle.moosx" || return 1
        (
            cd "$workdir" || exit 1
            ./prepare_logging_mode.sh minimal none \
                meta_shoreside.moosx meta_vehicle.moosx
        ) || return 1
    fi
    if [ -n "$INIT_FIXTURE" ]; then
        cp "$INIT_FIXTURE" "$workdir/init_field.sh" || return 1
        chmod +x "$workdir/init_field.sh" || return 1
    fi
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
