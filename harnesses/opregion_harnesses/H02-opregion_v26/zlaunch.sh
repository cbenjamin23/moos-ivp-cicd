#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H02-opregion_v26
#   Author: Charles Benjamin
#   LastEd: Oct 2026
#------------------------------------------------------------

need_bash=5.1
if [ -z "${BASH_VERSION:-}" ]; then
    echo "zlaunch.sh: run this harness with Bash >= $need_bash." >&2
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
    exit 2
fi

set -u

ME=$(basename "$0")
HARNESS_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$HARNESS_DIR/../../.." && pwd)
MISSION_DIR="$REPO_DIR/missions/opregion_missions/opregion_motion"
V26_BHV_STEM="$HARNESS_DIR/v26-stem.bhv"
TEARDOWN_HELPER="$REPO_DIR/scripts/moos_scoped_teardown.sh"
RESULTS_FILE="$HARNESS_DIR/results.txt"
RUNS_DIR="$HARNESS_DIR/.harness_runs"
RUN_ROOT=""

TIME_WARP=10
MAX_TIME=60
JOBS=1
PORT_BASE=22000
PORT_STRIDE=30
PSHARE_OFFSET=15
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
    convex_contained_keepin_pass
    nonconvex_contained_keepin_pass
    lapsed_recovery_pass
    entry_gate_start_outside_pass
    dynamic_region_update_pass
    stay_in_disabled_breach_pass
    metric_distance_macro_pass
    delayed_breach_flag_pass
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
  --jobs=<n>         Run up to n cases concurrently
  --port_base=<n>    Base MOOS port for per-case blocks
  --port_stride=<n>  Port spacing between case blocks (minimum 12)
  --keep_workdirs    Keep isolated case directories
  --gui              Launch one selected case with pMarineViewer
  --nogui, -ng       Headless launch, no GUI (default)

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
        --port_stride=*) PORT_STRIDE="${arg#--port_stride=}" ;;
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
is_uint "$PORT_STRIDE" && [ "${#PORT_STRIDE}" -le 5 ] || die "--port_stride must be a bounded integer of at least 12"
is_uint "$MAX_TIME" && [ "${#MAX_TIME}" -le 9 ] || die "--max_time must be a bounded positive integer"

TIME_WARP=$((10#$TIME_WARP))
JOBS=$((10#$JOBS))
PORT_BASE=$((10#$PORT_BASE))
PORT_STRIDE=$((10#$PORT_STRIDE))
MAX_TIME=$((10#$MAX_TIME))
PSHARE_OFFSET=$((PORT_STRIDE / 2))

[ "$TIME_WARP" -gt 0 ] || die "time warp must be positive"
[ "$JOBS" -gt 0 ] || die "--jobs must be positive"
[ "$PORT_BASE" -gt 0 ] && [ "$PORT_BASE" -le 65535 ] || die "--port_base must be from 1 through 65535"
[ "$PORT_STRIDE" -ge 12 ] || die "--port_stride must be at least 12"
[ "$PSHARE_OFFSET" -gt 1 ] || die "--port_stride does not leave room for pShare"
[ "$MAX_TIME" -gt 0 ] || die "--max_time must be positive"

[ -d "$MISSION_DIR" ] || die "mission directory not found: $MISSION_DIR"
[ -f "$V26_BHV_STEM" ] || die "V26 behavior stem not found: $V26_BHV_STEM"
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
        case "$field" in "$key"=*) count=$((count + 1)) ;; esac
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

stop_root() {
    moos_scoped_teardown_stop_root "$1"
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
    local patch_prefix
    CASE_VEH_MOOS_PATCH=""
    case "$case_name" in
        convex_contained_keepin_pass) patch_prefix=convex-contained-keepin-pass ;;
        nonconvex_contained_keepin_pass) patch_prefix=nonconvex-contained-keepin-pass ;;
        lapsed_recovery_pass)
            patch_prefix=lapsed-recovery-pass
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/lapsed-recovery-pass-vehicle.xmoos"
            ;;
        entry_gate_start_outside_pass) patch_prefix=entry-gate-start-outside-pass ;;
        dynamic_region_update_pass)
            patch_prefix=dynamic-region-update-pass
            CASE_VEH_MOOS_PATCH="$HARNESS_DIR/dynamic-region-update-pass-vehicle.xmoos"
            ;;
        stay_in_disabled_breach_pass) patch_prefix=stay-in-disabled-breach-pass ;;
        metric_distance_macro_pass) patch_prefix=metric-distance-macro-pass ;;
        delayed_breach_flag_pass) patch_prefix=delayed-breach-flag-pass ;;
        *) return 1 ;;
    esac
    CASE_SHORE_PATCH="$HARNESS_DIR/$patch_prefix-shoreside.xmoos"
    CASE_VEH_BHV_PATCH="$HARNESS_DIR/$patch_prefix-vehicle.xbhv"
    [ -f "$CASE_SHORE_PATCH" ] && [ -f "$CASE_VEH_BHV_PATCH" ] &&
        { [ -z "$CASE_VEH_MOOS_PATCH" ] || [ -f "$CASE_VEH_MOOS_PATCH" ]; }
}

prepare_case() {
    local case_name="$1"
    local workdir="$2"
    local patch
    local -a shore_patches=()
    local -a vehicle_patches=()
    rm -rf "$workdir"
    mkdir -p "$workdir" || return 1
    cp -R "$MISSION_DIR"/. "$workdir"/ || return 1
    (
        cd "$workdir" || exit 1
        ./clean.sh >/dev/null 2>&1
    ) || return 1
    get_case_config "$case_name" || return 1
    if [ "$LOG_MODE" = full ]; then
        shore_patches+=("$workdir/full-logging-shoreside.xmoos")
        vehicle_patches+=("$workdir/full-logging-vehicle.xmoos")
    fi
    shore_patches+=("$CASE_SHORE_PATCH")
    if [ -n "$CASE_VEH_MOOS_PATCH" ]; then
        vehicle_patches+=("$CASE_VEH_MOOS_PATCH")
    fi
    for patch in "${shore_patches[@]}"; do
        [ -f "$patch" ] || return 1
    done
    nspatch --stem="$workdir/meta_shoreside.moos" "${shore_patches[@]}" \
        --targ="$workdir/meta_shoreside.moosx" || return 1
    if [ "${#vehicle_patches[@]}" -gt 0 ]; then
        for patch in "${vehicle_patches[@]}"; do
            [ -f "$patch" ] || return 1
        done
        nspatch --stem="$workdir/meta_vehicle.moos" "${vehicle_patches[@]}" \
            --targ="$workdir/meta_vehicle.moosx" || return 1
    fi
    nspatch --stem="$V26_BHV_STEM" "$CASE_VEH_BHV_PATCH" \
        --targ="$workdir/meta_vehicle.bhvx" || return 1
}

write_result() {
    local case_name="$1"
    local result_file="$2"
    local launch_rc="$3"
    local workdir="$4"
    local line
    local grade_count
    local mission_grade
    local row_count

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
    row_count=$(awk 'NF {count++} END {print count+0}' "$workdir/results.txt")
    if [ "$row_count" -ne 1 ]; then
        printf 'case=%s grade=fail reason=invalid_result_rows result_rows=%s launch_rc=%s\n' "$case_name" "$row_count" "$launch_rc" > "$result_file"
        return 0
    fi
    line=$(awk 'NF {print; exit}' "$workdir/results.txt")
    grade_count=$(field_count "$line" grade)
    mission_grade=$(field_value "$line" grade || true)
    if [ "$grade_count" -ne 1 ] || { [ "$mission_grade" != pass ] && [ "$mission_grade" != fail ]; }; then
        printf 'case=%s grade=fail reason=malformed_result grade_fields=%s\n' "$case_name" "$grade_count" > "$result_file"
        return 0
    fi
    if [ "$launch_rc" -ne 0 ]; then
        printf 'case=%s grade=fail reason=launch_error launch_rc=%s mission_grade=%s\n' "$case_name" "$launch_rc" "$mission_grade" > "$result_file"
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
    local -a launch_args=()

    prepare_case "$case_name" "$workdir" || {
        printf 'case=%s grade=fail reason=prepare_error\n' "$case_name" > "$result_file"
        return 1
    }

    (
        cd "$workdir" || exit 1
        : > results.txt
        export LOG_MODE_PREPARED=yes
        export LOG_MODE_PREPARED_VALUE="$LOG_MODE"
        launch_args=(
            --max_time="$MAX_TIME"
            --log="$LOG_MODE"
            "${DISPLAY_ARGS[@]}"
            --shore_mport="$((case_base + 0))"
            --veh_mport="$((case_base + 1))"
            --shore_pshare="$((case_base + PSHARE_OFFSET))"
            --veh_pshare="$((case_base + PSHARE_OFFSET + 1))"
            "$TIME_WARP"
        )
        [ "$JUST_MAKE" = yes ] && launch_args+=(--just_make)
        ./zlaunch.sh "${launch_args[@]}"
    ) || launch_rc=$?

    write_result "$case_name" "$result_file" "$launch_rc" "$workdir"
    if ! stop_root "$workdir"; then
        printf 'case=%s grade=fail reason=teardown_error\n' "$case_name" > "$result_file"
        return 1
    fi
    [ "$(field_value "$(cat "$result_file")" grade || true)" = pass ]
}

start_case() {
    local case_idx="$1"
    local case_name="${SELECTED_CASES[$case_idx]}"
    local case_dir
    local workdir
    local result_file
    local log_file
    local case_base=$((PORT_BASE + case_idx * PORT_STRIDE))
    local pid

    case_dir="$RUN_ROOT/case_$(printf '%03d' "$case_idx")_$case_name"
    workdir="$case_dir/mission"
    result_file="$case_dir/result.row"
    log_file="$case_dir/run.log"
    CASE_RESULT[case_idx]="$result_file"
    mkdir -p "$case_dir"
    (
        set +e
        run_case "$case_name" "$workdir" "$result_file" "$case_base" > "$log_file" 2>&1
        rc=$?
        [ -s "$result_file" ] || printf 'case=%s grade=fail reason=missing_result launch_rc=%s\n' "$case_name" "$rc" > "$result_file"
        exit "$rc"
    ) &
    pid=$!
    PID_CASE[$pid]="$case_name"
    PID_RESULT[$pid]="$result_file"
    PID_LOG[$pid]="$log_file"
    PID_PORT_BASE[$pid]="$case_base"
    [ "$VERBOSE" = yes ] && printf 'event=start pid=%s case=%s port_base=%s workdir=%s\n' "$pid" "$case_name" "$case_base" "$workdir"
}

finish_one() {
    local done_pid=""
    local wait_rc=0
    local case_name
    local line
    local grade

    FINISH_FATAL_REASON=""
    wait -p done_pid -n || wait_rc=$?
    if [ -z "${done_pid:-}" ] || [ -z "${PID_CASE[$done_pid]:-}" ]; then
        FINISH_FATAL_REASON=scheduler_state_error
        return 2
    fi
    case_name="${PID_CASE[$done_pid]}"
    line=$(awk 'NF {print; exit}' "${PID_RESULT[$done_pid]}" 2>/dev/null)
    grade=$(field_value "$line" grade || true)
    if [ "$wait_rc" -ne 0 ] && [ "$grade" = pass ]; then
        printf 'case=%s grade=fail reason=worker_error worker_rc=%s\n' "$case_name" "$wait_rc" > "${PID_RESULT[$done_pid]}"
        grade=fail
    fi
    [ "$VERBOSE" = yes ] && printf 'event=finish pid=%s case=%s rc=%s grade=%s port_base=%s log=%s\n' "$done_pid" "$case_name" "$wait_rc" "${grade:-missing}" "${PID_PORT_BASE[$done_pid]}" "${PID_LOG[$done_pid]}"
    unset 'PID_CASE[$done_pid]' 'PID_RESULT[$done_pid]' 'PID_LOG[$done_pid]' 'PID_PORT_BASE[$done_pid]'
    [ "$grade" = pass ]
}

aggregate_results() {
    local total="${#SELECTED_CASES[@]}"
    local case_idx
    local case_name
    local result_file
    local line
    local grade
    FINAL_FAILURES=0
    : > "$RESULTS_FILE"
    for ((case_idx = 0; case_idx < total; case_idx++)); do
        case_name="${SELECTED_CASES[$case_idx]}"
        result_file="${CASE_RESULT[$case_idx]:-}"
        line=$(awk 'NF {print; exit}' "$result_file" 2>/dev/null)
        [ -n "$line" ] || line="case=$case_name grade=fail reason=missing_result_file"
        if [ "$(field_value "$line" case || true)" != "$case_name" ]; then
            line="case=$case_name grade=fail reason=result_case_mismatch"
        fi
        printf '%s\n' "$line" >> "$RESULTS_FILE"
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

active=0
next=0
while [ "$next" -lt "$total" ] || [ "$active" -gt 0 ]; do
    while [ "$next" -lt "$total" ] && [ "$active" -lt "$JOBS" ]; do
        start_case "$next"
        next=$((next + 1))
        active=$((active + 1))
    done
    if [ "$active" -gt 0 ]; then
        finish_rc=0
        finish_one || finish_rc=$?
        active=$((active - 1))
        if [ "$finish_rc" -eq 2 ]; then
            CLEANUP_FAILED=yes
            break
        fi
    fi
done

aggregate_results
cleanup_runtime
trap - EXIT INT TERM PIPE

echo "results=$RESULTS_FILE failures=$FINAL_FAILURES total=$total jobs=$JOBS bash=$BASH_VERSION"
[ "$FINAL_FAILURES" -eq 0 ] && [ "$CLEANUP_FAILED" = no ]
