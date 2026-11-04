#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H01-pdeadmanpost_unit
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
MISSION_DIR="$REPO_DIR/missions/pdeadmanpost_missions/pdeadmanpost_unit"
TEARDOWN_HELPER="$REPO_DIR/scripts/moos_scoped_teardown.sh"
RESULTS_FILE="$HARNESS_DIR/results.txt"
RUNS_DIR="$HARNESS_DIR/.harness_runs"
RUN_ROOT=""

TIME_WARP=10
MAX_TIME=30
JOBS=1
PORT_BASE=15800
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

CASES=(
    active_start_once_posts_pass
    active_start_false_no_initial_post_pass
    heartbeat_before_dead_suppresses_pass
    stop_heartbeat_posts_pass
    active_false_after_first_heartbeat_posts_pass
    numeric_deadflag_pass
    string_deadflag_pass
    multiple_deadflags_pass
    once_policy_single_post_pass
    repeat_policy_reposts_pass
    reset_policy_reposts_after_heartbeat_pass
    repeat_policy_inactive_reposts_pass
    reset_policy_no_repost_without_heartbeat_pass
    active_start_keepalive_suppresses_pass
    custom_heartbeat_var_pass
    negative_deadflag_pass
    zero_max_noheart_posts_pass
    false_deadflag_pass
    invalid_post_policy_falls_back_once_pass
    reset_policy_multiple_reposts_pass
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
  --gui              Run one explicit case with GUI enabled
  --nogui, -ng       Headless launch, no gui (default)

Cases:
EOF
    for case_name in "${CASES[@]}"; do
        printf '  %s\n' "$case_name"
    done
    cat <<EOF

Examples:
  ./$ME
  ./$ME --case=active_start_once_posts_pass
  ./$ME --jobs=4 --port_base=15800
  ./$ME --just_make --case=repeat_policy_reposts_pass
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
        if [ "$KEEP_WORKDIRS" != yes ] && [ "$root_stopped" = yes ]; then
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
    HEARTBEAT_EVENTS=()
    DEADFLAGS=()
    PASS_CONDITIONS=()
    FAIL_CONDITIONS=()
    REPORT_COLUMNS=()
    MIN_COUNTS=()
    MAX_COUNTS=()
    AFTER_LAST_TIMINGS=()
    CLIENT_TIMINGS=()
    HEART_VAR="HEARTBEAT"
    MAX_NOHEART="0.5"
    ACTIVE_AT_START="true"
    POST_POLICY="once"
    EVAL_TIME="1.5"


    case "$CASE_NAME" in
        active_start_once_posts_pass)
            DEADFLAGS=("DEAD_ONCE=true")
            PASS_CONDITIONS=("DEAD_ONCE = true")
            REPORT_COLUMNS=("dead_once=\$[DEAD_ONCE]")
            ;;
        active_start_false_no_initial_post_pass)
            ACTIVE_AT_START="false"
            DEADFLAGS=("DEAD_NO_START=true")
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            FAIL_CONDITIONS=("DEAD_NO_START = true")
            REPORT_COLUMNS=("dead_no_start=\$[DEAD_NO_START]")
            ;;
        heartbeat_before_dead_suppresses_pass)
            ACTIVE_AT_START="false"
            MAX_NOHEART="1.0"
            DEADFLAGS=("DEAD_KEEPALIVE=true")
            HEARTBEAT_EVENTS=("0.2" "0.5" "0.8" "1.1" "1.4")
            EVAL_TIME="1.6"
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            FAIL_CONDITIONS=("DEAD_KEEPALIVE = true")
            REPORT_COLUMNS=("dead_keepalive=\$[DEAD_KEEPALIVE]")
            ;;
        stop_heartbeat_posts_pass)
            ACTIVE_AT_START="false"
            MAX_NOHEART="0.45"
            DEADFLAGS=("DEAD_STOP=true")
            HEARTBEAT_EVENTS=("0.2" "0.4")
            EVAL_TIME="1.2"
            PASS_CONDITIONS=("DEAD_STOP = true")
            REPORT_COLUMNS=("dead_stop=\$[DEAD_STOP]")
            AFTER_LAST_TIMINGS=("HEARTBEAT:DEAD_STOP:0.35:0.70")
            ;;
        active_false_after_first_heartbeat_posts_pass)
            ACTIVE_AT_START="false"
            MAX_NOHEART="0.45"
            DEADFLAGS=("DEAD_AFTER_FIRST=true")
            HEARTBEAT_EVENTS=("0.2")
            EVAL_TIME="1.1"
            PASS_CONDITIONS=("DEAD_AFTER_FIRST = true")
            REPORT_COLUMNS=("dead_after_first=\$[DEAD_AFTER_FIRST]")
            ;;
        numeric_deadflag_pass)
            DEADFLAGS=("DEAD_NUM=7.5")
            PASS_CONDITIONS=("DEAD_NUM = 7.5")
            REPORT_COLUMNS=("dead_num=\$[DEAD_NUM]")
            ;;
        string_deadflag_pass)
            DEADFLAGS=("DEAD_STR=halt")
            PASS_CONDITIONS=("DEAD_STR = halt")
            REPORT_COLUMNS=("dead_str=\$[DEAD_STR]")
            ;;
        multiple_deadflags_pass)
            DEADFLAGS=("DEAD_MULTI_A=true" "DEAD_MULTI_B=alpha")
            PASS_CONDITIONS=("DEAD_MULTI_A = true" "DEAD_MULTI_B = alpha")
            REPORT_COLUMNS=("dead_multi_a=\$[DEAD_MULTI_A]" "dead_multi_b=\$[DEAD_MULTI_B]")
            ;;
        once_policy_single_post_pass)
            MAX_NOHEART="0.35"
            DEADFLAGS=("DEAD_ONCE_SINGLE=true")
            PASS_CONDITIONS=("DEAD_ONCE_SINGLE = true")
            REPORT_COLUMNS=("dead_once_single=\$[DEAD_ONCE_SINGLE]")
            MIN_COUNTS=("DEAD_ONCE_SINGLE:1")
            MAX_COUNTS=("DEAD_ONCE_SINGLE:1")
            ;;
        repeat_policy_reposts_pass)
            MAX_NOHEART="0.35"
            POST_POLICY="repeat"
            EVAL_TIME="1.4"
            DEADFLAGS=("DEAD_REPEAT=true")
            PASS_CONDITIONS=("DEAD_REPEAT = true")
            REPORT_COLUMNS=("dead_repeat=\$[DEAD_REPEAT]")
            MIN_COUNTS=("DEAD_REPEAT:2")
            ;;
        reset_policy_reposts_after_heartbeat_pass)
            MAX_NOHEART="0.30"
            POST_POLICY="reset"
            HEARTBEAT_EVENTS=("0.8")
            EVAL_TIME="1.5"
            DEADFLAGS=("DEAD_RESET=true")
            PASS_CONDITIONS=("DEAD_RESET = true")
            REPORT_COLUMNS=("dead_reset=\$[DEAD_RESET]")
            MIN_COUNTS=("DEAD_RESET:2")
            MAX_COUNTS=("DEAD_RESET:2")
            ;;
        repeat_policy_inactive_reposts_pass)
            ACTIVE_AT_START="false"
            MAX_NOHEART="0.35"
            POST_POLICY="repeat"
            HEARTBEAT_EVENTS=("0.2")
            EVAL_TIME="1.2"
            DEADFLAGS=("DEAD_REPEAT_AFTER_FIRST=true")
            PASS_CONDITIONS=("DEAD_REPEAT_AFTER_FIRST = true")
            REPORT_COLUMNS=("dead_repeat_after_first=\$[DEAD_REPEAT_AFTER_FIRST]")
            MIN_COUNTS=("DEAD_REPEAT_AFTER_FIRST:2")
            ;;
        reset_policy_no_repost_without_heartbeat_pass)
            MAX_NOHEART="0.35"
            POST_POLICY="reset"
            EVAL_TIME="1.4"
            DEADFLAGS=("DEAD_RESET_SINGLE=true")
            PASS_CONDITIONS=("DEAD_RESET_SINGLE = true")
            REPORT_COLUMNS=("dead_reset_single=\$[DEAD_RESET_SINGLE]")
            MIN_COUNTS=("DEAD_RESET_SINGLE:1")
            MAX_COUNTS=("DEAD_RESET_SINGLE:1")
            ;;
        active_start_keepalive_suppresses_pass)
            MAX_NOHEART="3.50"
            DEADFLAGS=("DEAD_ACTIVE_KEEPALIVE=true")
            HEARTBEAT_EVENTS=("0.2" "0.6" "1.0" "1.4" "1.8")
            EVAL_TIME="1.6"
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            FAIL_CONDITIONS=("DEAD_ACTIVE_KEEPALIVE = true")
            REPORT_COLUMNS=("dead_active_keepalive=\$[DEAD_ACTIVE_KEEPALIVE]")
            MAX_COUNTS=("DEAD_ACTIVE_KEEPALIVE:0")
            ;;
        custom_heartbeat_var_pass)
            ACTIVE_AT_START="false"
            MAX_NOHEART="0.35"
            HEART_VAR="ALT_HEART"
            HEARTBEAT_EVENTS=("0.2")
            EVAL_TIME="1.1"
            DEADFLAGS=("DEAD_ALT_HEART=true")
            PASS_CONDITIONS=("DEAD_ALT_HEART = true")
            REPORT_COLUMNS=("dead_alt_heart=\$[DEAD_ALT_HEART]")
            MIN_COUNTS=("DEAD_ALT_HEART:1")
            ;;
        negative_deadflag_pass)
            DEADFLAGS=("DEAD_NEG=-3.25")
            PASS_CONDITIONS=("DEAD_NEG = -3.25")
            REPORT_COLUMNS=("dead_neg=\$[DEAD_NEG]")
            ;;
        zero_max_noheart_posts_pass)
            MAX_NOHEART="0"
            EVAL_TIME="0.8"
            DEADFLAGS=("DEAD_ZERO_MAX=true")
            PASS_CONDITIONS=("DEAD_ZERO_MAX = true")
            REPORT_COLUMNS=("dead_zero_max=\$[DEAD_ZERO_MAX]")
            MIN_COUNTS=("DEAD_ZERO_MAX:1")
            CLIENT_TIMINGS=("pDeadManPost:DEAD_ZERO_MAX:0.00:0.90")
            ;;
        false_deadflag_pass)
            DEADFLAGS=("DEAD_FALSE=false")
            PASS_CONDITIONS=("DEAD_FALSE = false")
            REPORT_COLUMNS=("dead_false=\$[DEAD_FALSE]")
            MIN_COUNTS=("DEAD_FALSE:1")
            ;;
        invalid_post_policy_falls_back_once_pass)
            MAX_NOHEART="0.35"
            POST_POLICY="invalid_policy"
            EVAL_TIME="1.3"
            DEADFLAGS=("DEAD_INVALID_POLICY=true")
            PASS_CONDITIONS=("DEAD_INVALID_POLICY = true")
            REPORT_COLUMNS=("dead_invalid_policy=\$[DEAD_INVALID_POLICY]")
            MIN_COUNTS=("DEAD_INVALID_POLICY:1")
            MAX_COUNTS=("DEAD_INVALID_POLICY:1")
            ;;
        reset_policy_multiple_reposts_pass)
            MAX_NOHEART="0.30"
            POST_POLICY="reset"
            HEARTBEAT_EVENTS=("1.2" "2.2")
            EVAL_TIME="3.4"
            DEADFLAGS=("DEAD_RESET_MULTI=true")
            PASS_CONDITIONS=("DEAD_RESET_MULTI = true")
            REPORT_COLUMNS=("dead_reset_multi=\$[DEAD_RESET_MULTI]")
            MIN_COUNTS=("DEAD_RESET_MULTI:3")
            MAX_COUNTS=("DEAD_RESET_MULTI:3")
            ;;
        *) return 1 ;;
    esac
}

write_case_files() {
    local workdir="$1"
    local item
    {
        echo "ProcessConfig = pDeadManPost"
        echo "{"
        echo "  AppTick   = 10"
        echo "  CommsTick = 10"
        echo ""
        echo "  heartbeat_var   = $HEART_VAR"
        echo "  max_noheart     = $MAX_NOHEART"
        echo "  active_at_start = $ACTIVE_AT_START"
        echo "  post_policy     = $POST_POLICY"
        for item in "${DEADFLAGS[@]}"; do
            echo "  deadflag        = $item"
        done
        echo "}"
    } > "$workdir/case_deadman.moos"

    {
        echo "ProcessConfig = uTimerScript"
        echo "{"
        echo "  AppTick   = 10"
        echo "  CommsTick = 10"
        echo ""
        for item in "${HEARTBEAT_EVENTS[@]}"; do
            echo "  event = var=$HEART_VAR, val=alive, time=$item"
        done
        echo "  event = var=TEST_EVAL_READY, val=true, time=$EVAL_TIME"
        echo "}"
    } > "$workdir/case_timer.moos"

    {
        echo "ProcessConfig = pMissionEval"
        echo "{"
        echo "  AppTick   = 4"
        echo "  CommsTick = 4"
        echo ""
        echo "  lead_condition = TEST_EVAL_READY = true"
        for item in "${PASS_CONDITIONS[@]}"; do
            echo "  pass_condition = $item"
        done
        for item in "${FAIL_CONDITIONS[@]}"; do
            echo "  fail_condition = $item"
        done
        echo ""
        echo "  result_flag  = MISSION_EVALUATED = true"
        echo "  mission_form = pdeadmanpost_unit"
        echo ""
        echo "  report_column = form=\$[MISSION_FORM]"
        echo "  report_column    = grade=\$[GRADE]"
        echo "  report_column    = eval=\$[TEST_EVAL_READY]"
        for item in "${REPORT_COLUMNS[@]}"; do
            echo "  report_column    = $item"
        done
        echo "  report_column    = mhash=\$[MHASH_SHORT]"
        echo "  report_file      = results.txt"
        echo "}"
    } > "$workdir/case_eval.moos"
}

count_alog_posts() {
    local root="$1"
    local var="$2"
    local alog
    local count
    local cutoff
    local total=0
    local found=no

    while IFS= read -r -d '' alog; do
        found=yes
        cutoff=$(aloggrep MISSION_EVALUATED "$alog" 2>/dev/null |
            awk '$2 == "MISSION_EVALUATED" && $4 == "true" {print $1; exit}')
        [ -n "$cutoff" ] || return 1
        count=$(aloggrep "$var" "$alog" 2>/dev/null |
            awk -v v="$var" -v end="$cutoff" \
                '$2 == v && $1 <= end {count++} END {print count+0}')
        total=$((total + count))
    done < <(find "$root" -type f -name '*.alog' -print0)

    [ "$found" = yes ] || return 1
    printf '%s\n' "$total"
}

alog_post_time() {
    local root="$1"
    local var="$2"
    local which="$3"
    local alog
    local cutoff
    local found=no
    local -a times=()

    while IFS= read -r -d '' alog; do
        cutoff=$(aloggrep MISSION_EVALUATED "$alog" 2>/dev/null |
            awk '$2 == "MISSION_EVALUATED" && $4 == "true" {print $1; exit}')
        [ -n "$cutoff" ] || return 1
        while IFS= read -r timestamp; do
            [ -n "$timestamp" ] && times+=("$timestamp")
        done < <(aloggrep "$var" "$alog" 2>/dev/null |
            awk -v v="$var" -v end="$cutoff" '$2 == v && $1 <= end {print $1}')
        found=yes
    done < <(find "$root" -type f -name '*.alog' -print0)

    [ "$found" = yes ] && [ "${#times[@]}" -gt 0 ] || return 1
    if [ "$which" = first ]; then
        printf '%s\n' "${times[@]}" | sort -n | head -1
    else
        printf '%s\n' "${times[@]}" | sort -n | tail -1
    fi
}

alog_client_time() {
    local root="$1"
    local client="$2"
    local alog
    local cutoff
    local found=no
    local -a times=()

    while IFS= read -r -d '' alog; do
        cutoff=$(aloggrep MISSION_EVALUATED "$alog" 2>/dev/null |
            awk '$2 == "MISSION_EVALUATED" && $4 == "true" {print $1; exit}')
        [ -n "$cutoff" ] || return 1
        while IFS= read -r timestamp; do
            [ -n "$timestamp" ] && times+=("$timestamp")
        done < <(aloggrep DB_CLIENTS "$alog" 2>/dev/null |
            awk -v client="$client" -v end="$cutoff" \
                '$2 == "DB_CLIENTS" && $1 <= end && index($0, client) {print $1}')
        found=yes
    done < <(find "$root" -type f -name '*.alog' -print0)

    [ "$found" = yes ] && [ "${#times[@]}" -gt 0 ] || return 1
    printf '%s\n' "${times[@]}" | sort -n | head -1
}

check_deadman_counts() {
    local root="$1"
    local check
    local var
    local limit
    local observed
    local source_var
    local target_var
    local source_time
    local target_time
    local min_delta
    local max_delta
    local delta
    local evidence="evidence=count_contract"
    local required=no
    local ok=yes

    for check in "${MIN_COUNTS[@]}"; do
        required=yes
        var="${check%%:*}"
        limit="${check#*:}"
        if observed=$(count_alog_posts "$root" "$var"); then
            evidence="$evidence min_${var}=$limit count_${var}=$observed"
            [ "$observed" -ge "$limit" ] || ok=no
        else
            evidence="$evidence min_${var}=$limit count_${var}=missing"
            ok=no
        fi
    done
    for check in "${MAX_COUNTS[@]}"; do
        required=yes
        var="${check%%:*}"
        limit="${check#*:}"
        if observed=$(count_alog_posts "$root" "$var"); then
            evidence="$evidence max_${var}=$limit count_${var}=$observed"
            [ "$observed" -le "$limit" ] || ok=no
        else
            evidence="$evidence max_${var}=$limit count_${var}=missing"
            ok=no
        fi
    done
    for check in "${AFTER_LAST_TIMINGS[@]}"; do
        required=yes
        IFS=: read -r source_var target_var min_delta max_delta <<< "$check"
        source_time=$(alog_post_time "$root" "$source_var" last || true)
        target_time=$(alog_post_time "$root" "$target_var" first || true)
        if [ -n "$source_time" ] && [ -n "$target_time" ]; then
            delta=$(awk -v start="$source_time" -v end="$target_time" 'BEGIN {printf "%.3f", end-start}')
            evidence="$evidence last_${source_var}=$source_time first_${target_var}=$target_time delta_${source_var}_${target_var}=$delta min_delta=$min_delta max_delta=$max_delta"
            awk -v d="$delta" -v min="$min_delta" -v max="$max_delta" \
                'BEGIN {exit !(d >= min && d <= max)}' || ok=no
        else
            evidence="$evidence last_${source_var}=${source_time:-missing} first_${target_var}=${target_time:-missing}"
            ok=no
        fi
    done
    for check in "${CLIENT_TIMINGS[@]}"; do
        required=yes
        IFS=: read -r source_var target_var min_delta max_delta <<< "$check"
        source_time=$(alog_client_time "$root" "$source_var" || true)
        target_time=$(alog_post_time "$root" "$target_var" first || true)
        if [ -n "$source_time" ] && [ -n "$target_time" ]; then
            delta=$(awk -v start="$source_time" -v end="$target_time" 'BEGIN {printf "%.3f", end-start}')
            evidence="$evidence connected_${source_var}=$source_time first_${target_var}=$target_time delta_${source_var}_${target_var}=$delta min_delta=$min_delta max_delta=$max_delta"
            awk -v d="$delta" -v min="$min_delta" -v max="$max_delta" \
                'BEGIN {exit !(d >= min && d <= max)}' || ok=no
        else
            evidence="$evidence connected_${source_var}=${source_time:-missing} first_${target_var}=${target_time:-missing}"
            ok=no
        fi
    done

    [ "$required" = yes ] && printf '%s\n' "$evidence"
    [ "$ok" = yes ]
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
    write_case_files "$workdir"
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
    local count_evidence="$5"
    local count_rc="$6"

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

    if [ "$count_rc" -ne 0 ]; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=artifact_check_failed%s%s\n' \
            "$case_name" "${count_evidence:+ $count_evidence}" \
            "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi

    line=$(without_case_field "$line")
    printf 'case=%s %s%s\n' "$case_name" "$line" \
        "${count_evidence:+ $count_evidence}" > "$result_file"
}

run_case() {
    local case_name="$1"
    local workdir="$2"
    local result_file="$3"
    local case_base="$4"
    local launch_rc=0
    local launch_args
    local count_evidence=""
    local count_rc=0
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

    if [ "$JUST_MAKE" != yes ] && [ "$launch_rc" -eq 0 ]; then
        count_evidence=$(check_deadman_counts "$workdir") || count_rc=$?
    fi

    write_result "$case_name" "$result_file" "$launch_rc" "$workdir" \
        "$count_evidence" "$count_rc"
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

    wait -p done_pid -n || wait_rc=$?
    if [ -z "${done_pid:-}" ]; then
        echo "$ME: wait returned without a completed pid rc=$wait_rc" >&2
        return 1
    fi

    case_name="${PID_CASE[$done_pid]:-}"
    if [ -z "$case_name" ]; then
        echo "$ME: unknown completed pid $done_pid rc=$wait_rc" >&2
        return 1
    fi

    line=$(awk 'NF {print; exit}' "${PID_RESULT[$done_pid]}" 2>/dev/null)
    grade=$(field_value "$line" grade || true)
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
    [ "$grade" = pass ]
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

while [ "$next" -lt "$total" ] || [ "$active" -gt 0 ]; do
    while [ "$next" -lt "$total" ] && [ "$active" -lt "$JOBS" ]; do
        start_case "$next"
        next=$((next + 1))
        active=$((active + 1))
    done
    if [ "$active" -gt 0 ]; then
        finish_one || true
        active=$((active - 1))
    fi
done

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
