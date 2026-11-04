#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H01-utimerscript_unit
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
MISSION_DIR="$REPO_DIR/missions/utimerscript_missions/utimerscript_unit"
TEARDOWN_HELPER="$REPO_DIR/scripts/moos_scoped_teardown.sh"
RESULTS_FILE="$HARNESS_DIR/results.txt"
RUNS_DIR="$HARNESS_DIR/.harness_runs"
RUN_ROOT=""

TIME_WARP=10
MAX_TIME=40
CLIENT_START_TIMEOUT=12
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
    timed_numeric_string_pass
    quoted_comma_payload_pass
    macro_count_nav_pass
    condition_gate_external_pass
    pause_unpause_external_pass
    forward_jump_next_pass
    reset_var_repost_pass
    reset_time_all_posted_pass
    delay_start_pass
    status_var_initial_pass
    silent_status_pass
    randpair_poly_bounds_pass
    block_on_peer_pass
    atomic_condition_drop_pass
    pause_toggle_external_pass
    forward_positive_skip_pass
    custom_control_vars_pass
    time_warp_accelerates_pass
    delay_reset_pass
    reset_max_one_limit_pass
    amount_multiple_posts_pass
    dbtime_utc_macro_pass
    upon_awake_reset_pass
    upon_awake_restart_pass
    math_expression_pass
    idx_amount_expansion_pass
    time_window_event_pass
    reset_time_numeric_pass
    multi_condition_gate_pass
    quit_event_pass
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

get_case_config() {
    CASE_NAME="$1"
    CASE_MAX_TIME="$MAX_TIME"
    POKE_STEPS=()
    PASS_CONDITIONS=()
    REPORT_COLUMNS=()
    EXTRA_CHECKS=()
    TIMER_LINES=()
    DELAYED_PEER_ALIAS=""
    DELAYED_PEER_DELAY=""

    case "$CASE_NAME" in
        timed_numeric_string_pass)
            TIMER_LINES=(
                "script_name = timed_numeric_string"
                "event = var=UTS_NUM, val=42, time=0.2"
                "event = var=UTS_STR, val=alpha, time=0.3"
                "event = var=TEST_EVAL_READY, val=true, time=0.5"
            )
            PASS_CONDITIONS=("UTS_NUM = 42" "UTS_STR = alpha")
            REPORT_COLUMNS=("uts_num=\$[UTS_NUM]" "uts_str=\$[UTS_STR]")
            ;;
        quoted_comma_payload_pass)
            TIMER_LINES=(
                "script_name = quoted_payload"
                "event = var=UTS_PAYLOAD, val=\"name=alpha,mode=survey\", time=0.2"
                "event = var=TEST_EVAL_READY, val=true, time=0.5"
            )
            EXTRA_CHECKS=("alog:UTS_PAYLOAD:name=alpha,mode=survey")
            REPORT_COLUMNS=("payload=\$[UTS_PAYLOAD]")
            ;;
        macro_count_nav_pass)
            TIMER_LINES=(
                "script_name = macro_count_nav"
                "event = var=NAV_X, val=12.5, time=0.1"
                "event = var=NAV_Y, val=-4.25, time=0.1"
                "event = var=UTS_MACRO, val=\"x=\$[NAV_X],y=\$[NAV_Y],count=\$[COUNT],tcount=\$[TCOUNT]\", time=0.4"
                "event = var=TEST_EVAL_READY, val=true, time=0.7"
            )
            EXTRA_CHECKS=("exact:UTS_MACRO:x=12.50,y=-4.25,count=2,tcount=2")
            REPORT_COLUMNS=("macro=\$[UTS_MACRO]")
            ;;
        condition_gate_external_pass)
            TIMER_LINES=(
                "script_name = condition_gate"
                "condition = UTS_GATE = true"
                "event = var=UTS_GATED, val=released, time=0.2"
                "event = var=TEST_EVAL_READY, val=true, time=0.5"
            )
            POKE_STEPS=("0.8:UTS_GATE=true")
            PASS_CONDITIONS=("UTS_GATED = released")
            REPORT_COLUMNS=("gated=\$[UTS_GATED]" "gate=\$[UTS_GATE]")
            EXTRA_CHECKS=("after:UTS_GATED:UTS_GATE:true:1")
            ;;
        pause_unpause_external_pass)
            TIMER_LINES=(
                "script_name = pause_unpause"
                "paused = true"
                "event = var=UTS_PAUSED_OUT, val=after_pause, time=0.2"
                "event = var=TEST_EVAL_READY, val=true, time=0.5"
            )
            POKE_STEPS=("0.8:UTS_PAUSE=false")
            PASS_CONDITIONS=("UTS_PAUSED_OUT = after_pause")
            REPORT_COLUMNS=("paused_out=\$[UTS_PAUSED_OUT]")
            EXTRA_CHECKS=("after:UTS_PAUSED_OUT:UTS_PAUSE:false:1")
            ;;
        forward_jump_next_pass)
            TIMER_LINES=(
                "script_name = forward_jump"
                "event = var=UTS_LATE, val=jumped, time=100"
            )
            POKE_STEPS=("0.7:UTS_FORWARD=0" "0.7:TEST_EVAL_READY=true")
            PASS_CONDITIONS=("UTS_LATE = jumped")
            REPORT_COLUMNS=("late=\$[UTS_LATE]")
            ;;
        reset_var_repost_pass)
            TIMER_LINES=(
                "script_name = reset_var_repost"
                "event = var=UTS_COUNT, val=\$[TCOUNT], time=0.2"
            )
            POKE_STEPS=("0.7:UTS_RESET=true" "0.7:TEST_EVAL_READY=true")
            PASS_CONDITIONS=("UTS_COUNT >= 1")
            REPORT_COLUMNS=("uts_count=\$[UTS_COUNT]")
            EXTRA_CHECKS=("exact_count:UTS_COUNT:2")
            ;;
        reset_time_all_posted_pass)
            TIMER_LINES=(
                "script_name = reset_time_all_posted"
                "reset_time = all-posted"
                "reset_max = 2"
                "event = var=UTS_REPEAT, val=\$[TCOUNT], time=0.2"
            )
            POKE_STEPS=("1.0:TEST_EVAL_READY=true")
            PASS_CONDITIONS=("UTS_REPEAT = 2")
            REPORT_COLUMNS=("repeat=\$[UTS_REPEAT]")
            ;;
        delay_start_pass)
            TIMER_LINES=(
                "script_name = delay_start"
                "delay_start = 1.0"
                "event = var=UTS_DELAYED, val=true, time=0.1"
                "event = var=TEST_EVAL_READY, val=true, time=1.3"
            )
            PASS_CONDITIONS=("UTS_DELAYED = true")
            REPORT_COLUMNS=("delayed=\$[UTS_DELAYED]")
            EXTRA_CHECKS=("delta:UTS_STATUS:1:UTS_DELAYED:1:0.9:1.4")
            ;;
        status_var_initial_pass)
            TIMER_LINES=(
                "script_name = status_case"
                "status_var = UTS_CUSTOM_STATUS"
                "event = var=TEST_EVAL_READY, val=true, time=0.5"
            )
            EXTRA_CHECKS=("alog:UTS_CUSTOM_STATUS:name=status_case" "alog:UTS_CUSTOM_STATUS:pending=0")
            ;;
        silent_status_pass)
            TIMER_LINES=(
                "script_name = silent_status"
                "status_var = silent"
                "event = var=TEST_EVAL_READY, val=true, time=0.5"
            )
            EXTRA_CHECKS=("absent:UTS_STATUS")
            ;;
        randpair_poly_bounds_pass)
            TIMER_LINES=(
                "script_name = randpair_poly"
                "rand_pair = var1=PX, var2=PY, type=poly, key=at_post, poly=\"pts={0,0:10,0:0,2}\""
                "event = var=UTS_RPAIR, val=\"x=\$[PX],y=\$[PY]\", time=0.2, amt=20"
                "event = var=TEST_EVAL_READY, val=true, time=0.5"
            )
            PASS_CONDITIONS=('UTS_RPAIR != ""')
            REPORT_COLUMNS=("rpair=\$[UTS_RPAIR]")
            EXTRA_CHECKS=("triangle:UTS_RPAIR:10:2:20")
            ;;
        block_on_peer_pass)
            TIMER_LINES=(
                "script_name = block_on_peer"
                "block_on = UTSDelayedPeer"
                "event = var=UTS_BLOCKED_OUT, val=unblocked, time=0.2"
            )
            DELAYED_PEER_ALIAS="UTSDelayedPeer"
            DELAYED_PEER_DELAY="1.2"
            POKE_STEPS=("2.0:TEST_EVAL_READY=true")
            PASS_CONDITIONS=("UTS_BLOCKED_OUT = unblocked")
            REPORT_COLUMNS=("blocked_out=\$[UTS_BLOCKED_OUT]")
            EXTRA_CHECKS=("after_client:UTS_BLOCKED_OUT:UTSDelayedPeer")
            ;;
        atomic_condition_drop_pass)
            CASE_MAX_TIME="50"
            TIMER_LINES=(
                "script_name = atomic_condition_drop"
                "script_atomic = true"
                "condition = UTS_RUN = true"
                "event = var=UTS_ATOMIC_FIRST, val=true, time=1"
                "event = var=UTS_ATOMIC_SECOND, val=true, time=10"
                "event = var=TEST_EVAL_READY, val=true, time=11"
            )
            POKE_STEPS=("0.4:UTS_RUN=true" "0.8:UTS_RUN=false")
            PASS_CONDITIONS=("UTS_ATOMIC_FIRST = true" "UTS_ATOMIC_SECOND = true")
            REPORT_COLUMNS=("atomic_first=\$[UTS_ATOMIC_FIRST]" "atomic_second=\$[UTS_ATOMIC_SECOND]" "run=\$[UTS_RUN]")
            ;;
        pause_toggle_external_pass)
            TIMER_LINES=(
                "script_name = pause_toggle"
                "event = var=UTS_TOGGLE_OUT, val=after_toggle, time=10"
                "event = var=TEST_EVAL_READY, val=true, time=12"
            )
            POKE_STEPS=("0.1:UTS_PAUSE:=toggle" "0.9:UTS_PAUSE:=toggle")
            PASS_CONDITIONS=("UTS_TOGGLE_OUT = after_toggle")
            REPORT_COLUMNS=("toggle_out=\$[UTS_TOGGLE_OUT]")
            EXTRA_CHECKS=("after:UTS_TOGGLE_OUT:UTS_PAUSE:toggle:2")
            ;;
        forward_positive_skip_pass)
            TIMER_LINES=(
                "script_name = forward_positive_skip"
                "event = var=UTS_FORWARD_POS, val=skipped, time=100"
            )
            POKE_STEPS=("0.7:UTS_FORWARD=100" "0.7:TEST_EVAL_READY=true")
            PASS_CONDITIONS=("UTS_FORWARD_POS = skipped")
            REPORT_COLUMNS=("forward_pos=\$[UTS_FORWARD_POS]")
            ;;
        custom_control_vars_pass)
            TIMER_LINES=(
                "script_name = custom_controls"
                "pause_var = UTS_HOLD"
                "forward_var = UTS_SKIP"
                "reset_var = UTS_REDO"
                "paused = true"
                "event = var=UTS_CUSTOM_PROBE, val=released, time=0.2"
                "event = var=UTS_CUSTOM_CTRL, val=\$[COUNT], time=100"
            )
            POKE_STEPS=("0.5:UTS_HOLD:=false" "0.3:UTS_SKIP=100" "0.3:UTS_REDO:=true" "0.3:UTS_SKIP=100" "0.5:TEST_EVAL_READY=true")
            PASS_CONDITIONS=("UTS_CUSTOM_CTRL = 1")
            REPORT_COLUMNS=("custom_probe=\$[UTS_CUSTOM_PROBE]" "custom_ctrl=\$[UTS_CUSTOM_CTRL]")
            EXTRA_CHECKS=(
                "after:UTS_CUSTOM_PROBE:UTS_HOLD:false:1"
                "exact_count:UTS_CUSTOM_PROBE:2"
                "exact_count:UTS_CUSTOM_CTRL:2"
                "alog:UTS_STATUS:resets=1/any"
            )
            ;;
        time_warp_accelerates_pass)
            TIMER_LINES=(
                "script_name = time_warp_accelerates"
                "time_warp = 4"
                "event = var=UTS_WARPED, val=true, time=2"
                "event = var=TEST_EVAL_READY, val=true, time=2.2"
            )
            PASS_CONDITIONS=("UTS_WARPED = true")
            REPORT_COLUMNS=("warped=\$[UTS_WARPED]")
            EXTRA_CHECKS=(
                "alog:UTS_STATUS:time_warp=4"
                "delta:UTS_STATUS:1:UTS_WARPED:1:0.35:0.8"
            )
            ;;
        delay_reset_pass)
            TIMER_LINES=(
                "script_name = delay_reset"
                "reset_time = all-posted"
                "reset_max = 1"
                "delay_reset = 1.0"
                "event = var=UTS_DELAY_RESET, val=\$[TCOUNT], time=0.2"
            )
            POKE_STEPS=("2.0:TEST_EVAL_READY=true")
            PASS_CONDITIONS=("UTS_DELAY_RESET >= 1")
            REPORT_COLUMNS=("delay_reset_out=\$[UTS_DELAY_RESET]")
            EXTRA_CHECKS=(
                "exact_count:UTS_DELAY_RESET:2"
                "alog:UTS_STATUS:delay_reset=1"
                "delta:UTS_DELAY_RESET:1:UTS_DELAY_RESET:2:1.0:1.6"
            )
            ;;
        reset_max_one_limit_pass)
            TIMER_LINES=(
                "script_name = reset_max_one_limit"
                "reset_time = all-posted"
                "reset_max = 1"
                "event = var=UTS_LIMITED_REPEAT, val=\$[TCOUNT], time=0.2"
            )
            POKE_STEPS=("2.0:TEST_EVAL_READY=true")
            PASS_CONDITIONS=("UTS_LIMITED_REPEAT = 1")
            REPORT_COLUMNS=("limited_repeat=\$[UTS_LIMITED_REPEAT]")
            EXTRA_CHECKS=("alog:UTS_STATUS:resets=1/1")
            ;;
        amount_multiple_posts_pass)
            TIMER_LINES=(
                "script_name = amount_multiple_posts"
                "event = var=UTS_AMOUNT, val=burst, time=0.2, amt=3"
                "event = var=TEST_EVAL_READY, val=true, time=0.5"
            )
            PASS_CONDITIONS=("UTS_AMOUNT = burst")
            REPORT_COLUMNS=("amount=\$[UTS_AMOUNT]")
            EXTRA_CHECKS=("alog:UTS_STATUS:posted=4")
            ;;
        dbtime_utc_macro_pass)
            TIMER_LINES=(
                "script_name = dbtime_utc_macro"
                "event = var=UTS_DBTIME, val=\$[DBTIME], time=0.2"
                "event = var=UTS_UTC, val=\$[UTC], time=0.2"
                "event = var=TEST_EVAL_READY, val=true, time=0.5"
            )
            PASS_CONDITIONS=("UTS_DBTIME > 0" "UTS_UTC > 0")
            REPORT_COLUMNS=("dbtime=\$[UTS_DBTIME]" "utc=\$[UTS_UTC]")
            ;;
        upon_awake_reset_pass)
            TIMER_LINES=(
                "script_name = upon_awake_reset"
                "condition = UTS_AWAKE = true"
                "upon_awake = reset"
                "event = var=UTS_AWAKE_RESET, val=\$[TCOUNT], time=0.2"
            )
            POKE_STEPS=("0.1:UTS_AWAKE=true" "0.7:UTS_AWAKE=false" "0.7:UTS_AWAKE=true" "0.8:TEST_EVAL_READY=true")
            PASS_CONDITIONS=("UTS_AWAKE_RESET = 1")
            REPORT_COLUMNS=("awake_reset=\$[UTS_AWAKE_RESET]")
            EXTRA_CHECKS=("alog:UTS_STATUS:resets=1/any")
            ;;
        upon_awake_restart_pass)
            TIMER_LINES=(
                "script_name = upon_awake_restart"
                "condition = UTS_RESTART_GATE = true"
                "upon_awake = restart"
                "event = var=UTS_AWAKE_RESTART, val=\$[TCOUNT], time=0.2"
            )
            POKE_STEPS=("0.1:UTS_RESTART_GATE=true" "0.7:UTS_RESTART_GATE=false" "0.7:UTS_RESTART_GATE=true" "0.8:TEST_EVAL_READY=true")
            PASS_CONDITIONS=("UTS_AWAKE_RESTART = 1")
            REPORT_COLUMNS=("awake_restart=\$[UTS_AWAKE_RESTART]")
            EXTRA_CHECKS=("alog:UTS_STATUS:resets=0/any")
            ;;
        math_expression_pass)
            TIMER_LINES=(
                "script_name = math_expression"
                "event = var=UTS_MATH, val={{3+2}*4}, time=0.2"
                "event = var=TEST_EVAL_READY, val=true, time=0.5"
            )
            PASS_CONDITIONS=("UTS_MATH = 20")
            REPORT_COLUMNS=("math=\$[UTS_MATH]")
            ;;
        idx_amount_expansion_pass)
            TIMER_LINES=(
                "script_name = idx_amount"
                "event = var=UTS_IDX, val=idx_\$[IDX], time=0.2, amt=3"
                "event = var=TEST_EVAL_READY, val=true, time=0.5"
            )
            PASS_CONDITIONS=("UTS_IDX = idx_002")
            REPORT_COLUMNS=("idx=\$[UTS_IDX]")
            EXTRA_CHECKS=("alog:UTS_STATUS:posted=4")
            ;;
        time_window_event_pass)
            TIMER_LINES=(
                "script_name = time_window_event"
                "event = var=UTS_WINDOWED, val=true, time=0.2:0.8"
                "event = var=TEST_EVAL_READY, val=true, time=1.1"
            )
            PASS_CONDITIONS=("UTS_WINDOWED = true")
            REPORT_COLUMNS=("windowed=\$[UTS_WINDOWED]")
            EXTRA_CHECKS=("delta:UTS_STATUS:1:UTS_WINDOWED:1:0.15:0.95")
            ;;
        reset_time_numeric_pass)
            TIMER_LINES=(
                "script_name = reset_time_numeric"
                "reset_time = 0.6"
                "reset_max = 1"
                "event = var=UTS_NUMERIC_RESET, val=\$[TCOUNT], time=0.2"
            )
            POKE_STEPS=("1.4:TEST_EVAL_READY=true")
            PASS_CONDITIONS=("UTS_NUMERIC_RESET = 1")
            REPORT_COLUMNS=("numeric_reset=\$[UTS_NUMERIC_RESET]")
            EXTRA_CHECKS=("alog:UTS_STATUS:resets=1/1")
            ;;
        multi_condition_gate_pass)
            TIMER_LINES=(
                "script_name = multi_condition_gate"
                "condition = UTS_GATE_A = true"
                "condition = UTS_GATE_B = ready"
                "event = var=UTS_MULTI_GATED, val=released, time=0.2"
                "event = var=TEST_EVAL_READY, val=true, time=0.5"
            )
            POKE_STEPS=("0.5:UTS_GATE_A=true" "0.5:UTS_GATE_B:=ready")
            PASS_CONDITIONS=("UTS_MULTI_GATED = released")
            REPORT_COLUMNS=("multi_gated=\$[UTS_MULTI_GATED]" "gate_a=\$[UTS_GATE_A]" "gate_b=\$[UTS_GATE_B]")
            EXTRA_CHECKS=("after:UTS_MULTI_GATED:UTS_GATE_B:ready:1")
            ;;
        quit_event_pass)
            TIMER_LINES=(
                "script_name = quit_event"
                "event = var=UTS_QUIT_READY, val=true, time=0.2"
                "event = quit, time=0.4"
            )
            POKE_STEPS=("1.0:TEST_EVAL_READY=true")
            PASS_CONDITIONS=("UTS_QUIT_READY = true")
            REPORT_COLUMNS=("quit_ready=\$[UTS_QUIT_READY]")
            EXTRA_CHECKS=("client_transition:UTS_QUIT_READY:uTimerScript")
            ;;
    esac
}

write_timer_config() {
    local case_dir="$1"
    local timer_file="$case_dir/case_utimerscript.moos"
    {
        echo "//-------------------------------------------------"
        echo "// FILE: case_utimerscript.moos"
        echo "// NAME: Charles Benjamin"
        echo "//-------------------------------------------------"
        echo ""
        echo "ProcessConfig = uTimerScript"
        echo "{"
        echo "  AppTick   = 10"
        echo "  CommsTick = 10"
        echo ""
        for line in "${TIMER_LINES[@]}"; do
            echo "  $line"
        done
        echo "}"
    } > "$timer_file"
}

write_eval_config() {
    local case_dir="$1"
    local eval_file="$case_dir/case_eval.moos"
    {
        echo "//-------------------------------------------------"
        echo "// FILE: case_eval.moos"
        echo "// NAME: Charles Benjamin"
        echo "//-------------------------------------------------"
        echo ""
        echo "ProcessConfig = pMissionHash"
        echo "{"
        echo "  AppTick   = 4"
        echo "  CommsTick = 4"
        echo ""
        echo "  mission_hash_var = MISSION_HASH"
        echo "  mhash_short_var  = MHASH"
        echo "}"
        echo ""
        echo "//----------------------------------------------------"
        echo "ProcessConfig = pMissionEval"
        echo "{"
        echo "  AppTick   = 4"
        echo "  CommsTick = 4"
        echo ""
        echo "  lead_condition = TEST_EVAL_READY = true"
        for cond in "${PASS_CONDITIONS[@]}"; do
            echo "  pass_condition = $cond"
        done
        echo ""
        echo "  result_flag  = MISSION_EVALUATED = true"
        echo "  mission_form = utimerscript_unit"
        echo "  mission_mod  = $CASE_NAME"
        echo ""
        echo "  report_column    = grade=\$[GRADE]"
        echo "  report_column    = form=\$[MISSION_FORM]"
        echo "  report_column    = mmod=\$[MMOD]"
        echo "  report_column    = eval=\$[TEST_EVAL_READY]"
        for col in "${REPORT_COLUMNS[@]}"; do
            echo "  report_column    = $col"
        done
        echo "  report_column    = mhash=\$[MHASH_SHORT]"
        echo "  report_file      = results.txt"
        echo "}"
    } > "$eval_file"
}

find_alog() {
    local case_dir="$1"
    find "$case_dir" -name '*.alog' -print | sort | tail -n 1
}

evaluation_cutoff() {
    local alog="$1"
    awk '$2 == "MISSION_EVALUATED" && $4 == "true" {print $1; exit}' "$alog"
}

alog_var_line_matches_before_eval() {
    local case_dir="$1"
    local var="$2"
    local pattern="$3"
    local alog
    local cutoff
    alog=$(find_alog "$case_dir")
    [ -n "$alog" ] || return 1
    cutoff=$(evaluation_cutoff "$alog")
    [ -n "$cutoff" ] || return 1
    awk -v var="$var" -v cutoff="$cutoff" \
        '$2 == var && ($1 + 0) <= (cutoff + 0) {print}' "$alog" | grep -Fq -- "$pattern"
}

alog_var_exact_before_eval() {
    local case_dir="$1"
    local var="$2"
    local expected="$3"
    local alog
    local cutoff
    alog=$(find_alog "$case_dir")
    [ -n "$alog" ] || return 1
    cutoff=$(evaluation_cutoff "$alog")
    [ -n "$cutoff" ] || return 1
    awk -v var="$var" -v expected="$expected" -v cutoff="$cutoff" '
        $2 == var && ($1 + 0) <= (cutoff + 0) {
            value = $4
            for(i=5; i<=NF; i++)
                value = value " " $i
            if(value == expected)
                found = 1
        }
        END {exit(found ? 0 : 1)}
    ' "$alog"
}

alog_var_count_before_eval() {
    local case_dir="$1"
    local var="$2"
    local alog
    local cutoff
    alog=$(find_alog "$case_dir")
    [ -n "$alog" ] || return 1
    cutoff=$(evaluation_cutoff "$alog")
    [ -n "$cutoff" ] || return 1
    awk -v var="$var" -v cutoff="$cutoff" \
        '$2 == var && ($1 + 0) <= (cutoff + 0) {seen[$0] = 1}
         END {for(line in seen) count++; print count+0}' "$alog"
}

alog_var_after_value_before_eval() {
    local case_dir="$1"
    local var="$2"
    local release_var="$3"
    local release_value="$4"
    local release_occurrence="$5"
    local alog
    local cutoff
    alog=$(find_alog "$case_dir")
    [ -n "$alog" ] || return 1
    cutoff=$(evaluation_cutoff "$alog")
    [ -n "$cutoff" ] || return 1
    awk -v var="$var" -v release_var="$release_var" \
        -v release_value="$release_value" -v occurrence="$release_occurrence" \
        -v cutoff="$cutoff" '
        ($1 + 0) <= (cutoff + 0) && $2 == release_var && $4 == release_value {
            seen++
            if(seen == occurrence)
                release_time = $1 + 0
        }
        ($1 + 0) <= (cutoff + 0) && $2 == var && first_var_time == "" {
            first_var_time = $1 + 0
        }
        END {exit(release_time != "" && first_var_time != "" &&
                  first_var_time > release_time ? 0 : 1)}
    ' "$alog"
}

alog_triangle_samples_before_eval() {
    local case_dir="$1"
    local var="$2"
    local width="$3"
    local height="$4"
    local expected_count="$5"
    local alog
    local cutoff
    alog=$(find_alog "$case_dir")
    [ -n "$alog" ] || return 1
    cutoff=$(evaluation_cutoff "$alog")
    [ -n "$cutoff" ] || return 1
    awk -v var="$var" -v width="$width" -v height="$height" \
        -v expected_count="$expected_count" -v cutoff="$cutoff" '
        $2 == var && ($1 + 0) <= (cutoff + 0) && !seen[$0]++ {
            count++
            value = $4
            if(value !~ /^x=-?[0-9]+([.][0-9]+)?,y=-?[0-9]+([.][0-9]+)?$/) {
                bad = 1
                next
            }
            sub(/^x=/, "", value)
            split(value, coords, ",y=")
            x = coords[1] + 0
            y = coords[2] + 0
            if(x < 0 || x > width || y < 0 || y > height ||
               (x / width) + (y / height) > 1.001)
                bad = 1
        }
        END {exit(!bad && count == expected_count ? 0 : 1)}
    ' "$alog"
}

alog_client_transition_before_eval() {
    local case_dir="$1"
    local marker_var="$2"
    local client="$3"
    local alog
    local cutoff
    alog=$(find_alog "$case_dir")
    [ -n "$alog" ] || return 1
    cutoff=$(evaluation_cutoff "$alog")
    [ -n "$cutoff" ] || return 1
    awk -v marker_var="$marker_var" -v client="$client" -v cutoff="$cutoff" '
        ($1 + 0) <= (cutoff + 0) && $2 == marker_var && $3 == client && marker_time == "" {
            marker_time = $1 + 0
            marker_owned = 1
        }
        ($1 + 0) <= (cutoff + 0) && $2 == "DB_CLIENTS" {
            value = $4
            for(i=5; i<=NF; i++)
                value = value " " $i
            if(marker_time != "" && ($1 + 0) > marker_time && index(value, client) == 0)
                disconnected = 1
        }
        END {exit(marker_owned && disconnected ? 0 : 1)}
    ' "$alog"
}

alog_var_after_client_before_eval() {
    local case_dir="$1"
    local var="$2"
    local client="$3"
    local alog
    local cutoff
    alog=$(find_alog "$case_dir")
    [ -n "$alog" ] || return 1
    cutoff=$(evaluation_cutoff "$alog")
    [ -n "$cutoff" ] || return 1
    awk -v var="$var" -v client="$client" -v cutoff="$cutoff" '
        ($1 + 0) <= (cutoff + 0) && $2 == "DB_CLIENTS" {
            value = $4
            for(i=5; i<=NF; i++)
                value = value " " $i
            if(client_time == "" && index(value, client) > 0) {
                client_time = $1 + 0
                client_line = NR
            }
        }
        ($1 + 0) <= (cutoff + 0) && $2 == var && var_time == "" {
            var_time = $1 + 0
            var_line = NR
        }
        END {
            ordered = (var_time > client_time) ||
                      (var_time == client_time && var_line > client_line)
            exit(client_time != "" && var_time != "" && ordered ? 0 : 1)
        }
    ' "$alog"
}

alog_occurrence_delta_before_eval() {
    local case_dir="$1"
    local from_var="$2"
    local from_occurrence="$3"
    local to_var="$4"
    local to_occurrence="$5"
    local min_delta="$6"
    local max_delta="$7"
    local alog
    local cutoff
    alog=$(find_alog "$case_dir")
    [ -n "$alog" ] || return 1
    cutoff=$(evaluation_cutoff "$alog")
    [ -n "$cutoff" ] || return 1
    awk -v from_var="$from_var" -v from_occurrence="$from_occurrence" \
        -v to_var="$to_var" -v to_occurrence="$to_occurrence" \
        -v min_delta="$min_delta" -v max_delta="$max_delta" \
        -v cutoff="$cutoff" '
        ($1 + 0) <= (cutoff + 0) && !seen[$0]++ {
            if($2 == from_var) {
                from_count++
                if(from_count == from_occurrence)
                    from_time = $1 + 0
            }
            if($2 == to_var) {
                to_count++
                if(to_count == to_occurrence)
                    to_time = $1 + 0
            }
        }
        END {
            delta = to_time - from_time
            exit(from_time != "" && to_time != "" &&
                 delta >= min_delta && delta <= max_delta ? 0 : 1)
        }
    ' "$alog"
}

stop_client() {
    local pid="$1"
    local attempt

    kill -TERM "$pid" 2>/dev/null || true
    for ((attempt = 0; attempt < 20; attempt++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

start_delayed_peer() {
    local workdir="$1"
    local port="$2"
    local alias="$3"
    local delay="$4"

    (
        sleep "$delay"
        cd "$workdir" || exit 1
        exec uXMS --alias="$alias" --serverhost=localhost \
            --serverport="$port" DB_CLIENTS
    ) > "$workdir/delayed_peer.log" 2>&1 &
    DELAYED_PEER_PID=$!
}

run_bounded_poke() {
    local port="$1"
    shift
    local poke_pid
    local deadline=$((SECONDS + CLIENT_START_TIMEOUT))

    uPokeDB --quiet --host=localhost --port="$port" "$@" >/dev/null 2>&1 &
    poke_pid=$!
    while kill -0 "$poke_pid" 2>/dev/null; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            stop_client "$poke_pid"
            return 124
        fi
        sleep 0.1
    done
    wait "$poke_pid"
}

run_pokes() {
    local port="$1"
    local step
    local delay
    local batch
    local -a batch_args=()

    [ "${#POKE_STEPS[@]}" -gt 0 ] || return 0
    sleep 0.5

    for step in "${POKE_STEPS[@]}"; do
        delay="${step%%:*}"
        batch="${step#*:}"
        sleep "$delay"
        read -r -a batch_args <<< "$batch"
        run_bounded_poke "$port" "${batch_args[@]}" || return 1
    done
}

extra_checks_ok() {
    local case_dir="$1"
    local check
    local kind
    local rest
    local var
    local pattern
    local min_count
    local actual_count
    local expected_count
    local release_var
    local release_value
    local release_occurrence
    local width
    local height
    local marker_var
    local client
    local from_var
    local from_occurrence
    local to_var
    local to_occurrence
    local min_delta
    local max_delta

    for check in "${EXTRA_CHECKS[@]}"; do
        kind="${check%%:*}"
        rest="${check#*:}"
        case "$kind" in
            alog)
                var="${rest%%:*}"
                pattern="${rest#*:}"
                alog_var_line_matches_before_eval "$case_dir" "$var" "$pattern" || return 1
                ;;
            exact)
                var="${rest%%:*}"
                pattern="${rest#*:}"
                alog_var_exact_before_eval "$case_dir" "$var" "$pattern" || return 1
                ;;
            absent)
                var="$rest"
                actual_count=$(alog_var_count_before_eval "$case_dir" "$var") || return 1
                [ "$actual_count" -eq 0 ] || return 1
                ;;
            count)
                var="${rest%%:*}"
                min_count="${rest#*:}"
                actual_count=$(alog_var_count_before_eval "$case_dir" "$var") || return 1
                [ "$actual_count" -ge "$min_count" ] || return 1
                ;;
            exact_count)
                var="${rest%%:*}"
                expected_count="${rest#*:}"
                actual_count=$(alog_var_count_before_eval "$case_dir" "$var") || return 1
                [ "$actual_count" -eq "$expected_count" ] || return 1
                ;;
            after)
                var="${rest%%:*}"
                rest="${rest#*:}"
                release_var="${rest%%:*}"
                rest="${rest#*:}"
                release_value="${rest%%:*}"
                release_occurrence="${rest#*:}"
                alog_var_after_value_before_eval "$case_dir" "$var" "$release_var" \
                    "$release_value" "$release_occurrence" || return 1
                ;;
            triangle)
                var="${rest%%:*}"
                rest="${rest#*:}"
                width="${rest%%:*}"
                rest="${rest#*:}"
                height="${rest%%:*}"
                expected_count="${rest#*:}"
                alog_triangle_samples_before_eval "$case_dir" "$var" "$width" \
                    "$height" "$expected_count" || return 1
                ;;
            client_transition)
                marker_var="${rest%%:*}"
                client="${rest#*:}"
                alog_client_transition_before_eval "$case_dir" "$marker_var" "$client" || return 1
                ;;
            after_client)
                var="${rest%%:*}"
                client="${rest#*:}"
                alog_var_after_client_before_eval "$case_dir" "$var" "$client" || return 1
                ;;
            delta)
                from_var="${rest%%:*}"
                rest="${rest#*:}"
                from_occurrence="${rest%%:*}"
                rest="${rest#*:}"
                to_var="${rest%%:*}"
                rest="${rest#*:}"
                to_occurrence="${rest%%:*}"
                rest="${rest#*:}"
                min_delta="${rest%%:*}"
                max_delta="${rest#*:}"
                alog_occurrence_delta_before_eval "$case_dir" "$from_var" \
                    "$from_occurrence" "$to_var" "$to_occurrence" \
                    "$min_delta" "$max_delta" || return 1
                ;;
            *)
                return 1
                ;;
        esac
    done
    return 0
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
    if [ "$LOG_MODE" = full ]; then
        nspatch "$workdir/meta_shoreside.moos" \
            "$workdir/full-logging-shoreside.xmoos" \
            "$workdir/meta_shoreside.moosx" || return 1
    fi
    get_case_config "$case_name" || return 1
    write_timer_config "$workdir"
    write_eval_config "$workdir"
}

write_result() {
    local case_name="$1"
    local result_file="$2"
    local launch_rc="$3"
    local stimulus_rc="$4"
    local workdir="$5"
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
        printf 'case=%s grade=fail reason=missing_result_file launch_rc=%s stimulus_rc=%s\n' \
            "$case_name" "$launch_rc" "$stimulus_rc" > "$result_file"
        return 0
    fi

    mission_rows=$(awk 'NF {count++} END {print count+0}' "$workdir/results.txt")
    if [ "$mission_rows" -eq 0 ]; then
        printf 'case=%s grade=fail reason=missing_result launch_rc=%s stimulus_rc=%s\n' \
            "$case_name" "$launch_rc" "$stimulus_rc" > "$result_file"
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
        printf 'case=%s grade=fail reason=missing_result launch_rc=%s stimulus_rc=%s\n' \
            "$case_name" "$launch_rc" "$stimulus_rc" > "$result_file"
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

    if [ "$stimulus_rc" -ne 0 ]; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=stimulus_error stimulus_rc=%s%s\n' \
            "$case_name" "$stimulus_rc" "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi

    if [ "$launch_rc" -ne 0 ]; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=launch_error launch_rc=%s%s\n' \
            "$case_name" "$launch_rc" "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi

    if [ "$mission_grade" = pass ] && ! extra_checks_ok "$workdir"; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=artifact_check_failed%s\n' \
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
    local stimulus_rc=0
    local stem_pid=0
    local delayed_peer_pid=0
    local -a launch_args=()
    local result_line
    local grade

    prepare_case "$case_name" "$workdir" || {
        printf 'case=%s grade=fail reason=prepare_error\n' "$case_name" > "$result_file"
        return 1
    }

    if [ "$JUST_MAKE" = yes ]; then
        (
            cd "$workdir" || exit 1
            launch_args=(
                --just_make
                --max_time="$CASE_MAX_TIME"
                "${DISPLAY_ARGS[@]}"
                --shore_mport="$((case_base + 0))"
                --shore_pshare="$((case_base + PSHARE_OFFSET))"
                "$TIME_WARP"
            )
            LOG_MODE_PREPARED=yes ./zlaunch.sh --log="$LOG_MODE" "${launch_args[@]}"
        ) || launch_rc=$?
    else
        (
            cd "$workdir" || exit 1
            : > results.txt
            launch_args=(
                --max_time="$CASE_MAX_TIME"
                "${DISPLAY_ARGS[@]}"
                --shore_mport="$((case_base + 0))"
                --shore_pshare="$((case_base + PSHARE_OFFSET))"
                "$TIME_WARP"
            )
            LOG_MODE_PREPARED=yes ./zlaunch.sh --log="$LOG_MODE" "${launch_args[@]}"
        ) &
        stem_pid=$!
        if [ -n "$DELAYED_PEER_ALIAS" ]; then
            start_delayed_peer "$workdir" "$((case_base + 0))" \
                "$DELAYED_PEER_ALIAS" "$DELAYED_PEER_DELAY"
            delayed_peer_pid=$DELAYED_PEER_PID
        fi
        run_pokes "$((case_base + 0))" || stimulus_rc=$?
        wait "$stem_pid" || launch_rc=$?
        if [ "$delayed_peer_pid" -gt 0 ]; then
            stop_client "$delayed_peer_pid"
        fi
    fi

    write_result "$case_name" "$result_file" "$launch_rc" "$stimulus_rc" "$workdir"
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
