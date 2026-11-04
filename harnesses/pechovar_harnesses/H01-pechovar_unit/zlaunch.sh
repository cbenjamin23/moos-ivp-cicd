#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H01-pechovar_unit
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
MISSION_DIR="$REPO_DIR/missions/pechovar_missions/pechovar_unit"
TEARDOWN_HELPER="$REPO_DIR/scripts/moos_scoped_teardown.sh"
RESULTS_FILE="$HARNESS_DIR/results.txt"
RUNS_DIR="$HARNESS_DIR/.harness_runs"
RUN_ROOT=""

TIME_WARP=10
MAX_TIME=20
JOBS=1
PORT_BASE=17600
PORT_STRIDE=30
PSHARE_OFFSET=$((PORT_STRIDE / 2))
CASE=""
JUST_MAKE=no
LOG_MODE=minimal
KEEP_WORKDIRS=no
VERBOSE=no
DISPLAY_ARGS=(--nogui)
CLEANED=no
CLEANING=no
CLEANUP_FAILED=no

CASES=(
    numeric_echo_pass
    string_echo_pass
    bool_switch_true_pass
    bool_switch_mixed_case_pass
    bool_switch_upper_false_pass
    bool_switch_numeric_passthrough_pass
    bool_switch_nonbool_passthrough_pass
    multi_target_echo_pass
    acyclic_chain_echo_pass
    duplicate_mapping_single_post_pass
    default_repeated_source_posts_each_pass
    latest_only_repeated_source_pass
    flip_component_pass
    flip_explicit_param_syntax_pass
    flip_explicit_filter_suppresses_pass
    flip_filter_match_pass
    flip_multiple_filters_match_pass
    flip_filter_case_insensitive_match_pass
    flip_missing_filter_allows_pass
    flip_filter_suppresses_pass
    flip_multiple_filters_suppress_pass
    flip_custom_separator_pass
    flip_component_case_sensitive_pass
    flip_unmapped_component_omitted_pass
    flip_no_mapped_fields_no_output_pass
    flip_duplicate_component_repeats_pass
    flip_empty_value_pass
    cycle_guard_no_echo_pass
    self_cycle_guard_no_echo_pass
    indirect_cycle_blocks_all_pass
    invalid_flip_no_output_pass
    invalid_flip_alias_no_output_pass
    shared_source_dual_flip_pass
    dual_flip_independent_pass
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
        --case=*) CASE="${arg#--case=}"; [ -n "$CASE" ] || die "--case requires a nonempty case name" ;;
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
    local line="$1" key="$2" field
    local -a fields=()
    read -r -a fields <<< "$line"
    for field in "${fields[@]}"; do
        case "$field" in "$key"=*) printf '%s\n' "${field#*=}"; return 0 ;; esac
    done
    return 1
}

field_count() {
    local line="$1" key="$2" field count=0
    local -a fields=()
    read -r -a fields <<< "$line"
    for field in "${fields[@]}"; do
        case "$field" in "$key"=*) count=$((count + 1)) ;; esac
    done
    printf '%s\n' "$count"
}

without_case_field() {
    local line="$1" field output=""
    local -a fields=()
    read -r -a fields <<< "$line"
    for field in "${fields[@]}"; do
        case "$field" in case=*) ;; *) output="${output:+$output }$field" ;; esac
    done
    printf '%s\n' "$output"
}

runner_provenance() {
    local line="$1" field output=""
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
    moos_scoped_teardown_stop_root "$1" || {
        echo "$ME: scoped teardown failed for $1" >&2
        return 1
    }
}

cleanup_runtime() {
    local pid root_stopped=yes
    [ "$CLEANED" = no ] || return 0
    [ "$CLEANING" = no ] || return 0
    CLEANING=yes
    trap '' INT TERM PIPE
    for pid in "${!PID_CASE[@]}"; do kill "$pid" 2>/dev/null || true; done
    wait 2>/dev/null || true
    if [ -n "$RUN_ROOT" ] && [ -d "$RUN_ROOT" ]; then
        if ! stop_root "$RUN_ROOT"; then root_stopped=no; CLEANUP_FAILED=yes; fi
        if [ "$KEEP_WORKDIRS" != yes ] && [ "$root_stopped" = yes ]; then rm -rf "$RUN_ROOT"; fi
    fi
    rmdir "$RUNS_DIR" 2>/dev/null || true
    CLEANED=yes
    CLEANING=no
}

on_signal() { exit 130; }
trap cleanup_runtime EXIT
trap on_signal INT TERM PIPE

add_timer_event() {
    local value="$2"
    if [[ "$value" == *","* || "$value" == *"|"* || "$value" == *"#"* || "$value" == *"@"* ]]; then
        value="\"$value\""
    fi
    TIMER_EVENTS+=("  event = var=$1, val=$value, time=$3")
}

get_case_config() {
    CASE_NAME="$1"
    ECHO_LINES=()
    TIMER_EVENTS=()
    PASS_CONDITIONS=()
    REPORT_COLUMNS=()
    REQUIRED_TOKENS=()
    ABSENT_TOKENS=()
    EXPECTED_ALOG_VALUES=()
    COUNT_VAR=""
    COUNT_TARGET=""

    REPORT_COLUMNS=("out_num=\$[ECHO_OUT_NUM]" "out_str=\$[ECHO_OUT_STR]" "out_bool=\$[ECHO_OUT_BOOL]" "out_a=\$[ECHO_OUT_A]" "out_b=\$[ECHO_OUT_B]" "latest=\$[ECHO_OUT_LATEST]" "flip_out=\$[FLIP_OUT]")

    case "$CASE_NAME" in
        numeric_echo_pass)
            ECHO_LINES=("  Echo = ECHO_SRC_NUM -> ECHO_OUT_NUM")
            add_timer_event ECHO_SRC_NUM 42.5 0.5
            PASS_CONDITIONS=("ECHO_OUT_NUM = 42.5")
            ;;
        string_echo_pass)
            ECHO_LINES=("  Echo = ECHO_SRC_STR -> ECHO_OUT_STR")
            add_timer_event ECHO_SRC_STR ready 0.5
            PASS_CONDITIONS=("ECHO_OUT_STR = ready")
            ;;
        bool_switch_true_pass)
            ECHO_LINES=("  Echo = ECHO_SRC_BOOL !-> ECHO_OUT_BOOL")
            add_timer_event ECHO_SRC_BOOL true 0.5
            PASS_CONDITIONS=("ECHO_OUT_BOOL = false")
            ;;
        bool_switch_mixed_case_pass)
            ECHO_LINES=("  Echo = ECHO_SRC_BOOL !-> ECHO_OUT_BOOL")
            add_timer_event ECHO_SRC_BOOL True 0.5
            PASS_CONDITIONS=("ECHO_OUT_BOOL = False")
            ;;
        bool_switch_upper_false_pass)
            ECHO_LINES=("  Echo = ECHO_SRC_BOOL !-> ECHO_OUT_BOOL")
            add_timer_event ECHO_SRC_BOOL FALSE 0.5
            PASS_CONDITIONS=("ECHO_OUT_BOOL = TRUE")
            ;;
        bool_switch_numeric_passthrough_pass)
            ECHO_LINES=("  Echo = ECHO_SRC_NUM !-> ECHO_OUT_NUM")
            add_timer_event ECHO_SRC_NUM 7 0.5
            PASS_CONDITIONS=("ECHO_OUT_NUM = 7")
            ;;
        bool_switch_nonbool_passthrough_pass)
            ECHO_LINES=("  Echo = ECHO_SRC_BOOL !-> ECHO_OUT_BOOL")
            add_timer_event ECHO_SRC_BOOL maybe 0.5
            PASS_CONDITIONS=("ECHO_OUT_BOOL = maybe")
            ;;
        multi_target_echo_pass)
            ECHO_LINES=("  Echo = ECHO_SRC_MULTI -> ECHO_OUT_A" "  Echo = ECHO_SRC_MULTI -> ECHO_OUT_B")
            add_timer_event ECHO_SRC_MULTI alpha 0.5
            PASS_CONDITIONS=("ECHO_OUT_A = alpha" "ECHO_OUT_B = alpha")
            ;;
        acyclic_chain_echo_pass)
            ECHO_LINES=("  Echo = ECHO_SRC_STR -> ECHO_OUT_A" "  Echo = ECHO_OUT_A -> ECHO_OUT_B")
            add_timer_event ECHO_SRC_STR chain 0.5
            PASS_CONDITIONS=("ECHO_OUT_A = chain" "ECHO_OUT_B = chain")
            ;;
        duplicate_mapping_single_post_pass)
            ECHO_LINES=("  Echo = ECHO_SRC_STR -> ECHO_OUT_STR" "  Echo = ECHO_SRC_STR -> ECHO_OUT_STR")
            add_timer_event ECHO_SRC_STR dedupe 0.5
            PASS_CONDITIONS=("ECHO_OUT_STR = dedupe")
            COUNT_VAR="ECHO_OUT_STR"
            COUNT_TARGET="1"
            ;;
        default_repeated_source_posts_each_pass)
            ECHO_LINES=("  Echo = ECHO_SRC_LATEST -> ECHO_OUT_LATEST")
            add_timer_event ECHO_SRC_LATEST first 0.5
            add_timer_event ECHO_SRC_LATEST second 0.5
            PASS_CONDITIONS=("ECHO_OUT_LATEST = second")
            COUNT_VAR="ECHO_OUT_LATEST"
            COUNT_TARGET="2"
            ;;
        latest_only_repeated_source_pass)
            ECHO_LINES=("  echo_latest_only = true" "  Echo = ECHO_SRC_LATEST -> ECHO_OUT_LATEST")
            add_timer_event ECHO_SRC_LATEST first 0.5
            add_timer_event ECHO_SRC_LATEST second 0.5
            PASS_CONDITIONS=("ECHO_OUT_LATEST = second")
            COUNT_VAR="ECHO_OUT_LATEST"
            COUNT_TARGET="1"
            ;;
        flip_component_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = dest_separator = #" "  FLIP:click = x -> xcenter" "  FLIP:click = y -> ycenter")
            add_timer_event FLIP_SRC "x=10,y=20,type=redeploy" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            REQUIRED_TOKENS=("xcenter=10#ycenter=20")
            ;;
        flip_explicit_param_syntax_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = filter = type == redeploy" "  FLIP:click = component = x -> xcenter")
            add_timer_event FLIP_SRC "type=redeploy,x=18" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            REQUIRED_TOKENS=("xcenter=18")
            ;;
        flip_explicit_filter_suppresses_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = filter = type == redeploy" "  FLIP:click = component = x -> xcenter")
            add_timer_event FLIP_SRC "type=loiter,x=18" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            ABSENT_TOKENS=(" FLIP_OUT ")
            ;;
        flip_filter_match_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = dest_separator = #" "  FLIP:click = type == redeploy" "  FLIP:click = x -> xcenter" "  FLIP:click = y -> ycenter")
            add_timer_event FLIP_SRC "type=redeploy,x=11,y=21" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            REQUIRED_TOKENS=("xcenter=11#ycenter=21")
            ;;
        flip_multiple_filters_match_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = type == redeploy" "  FLIP:click = mode == survey" "  FLIP:click = x -> xcenter" "  FLIP:click = y -> ycenter")
            add_timer_event FLIP_SRC "type=redeploy,mode=survey,x=19,y=29" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            REQUIRED_TOKENS=("xcenter=19,ycenter=29")
            ;;
        flip_filter_case_insensitive_match_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = type == redeploy" "  FLIP:click = x -> xcenter" "  FLIP:click = y -> ycenter")
            add_timer_event FLIP_SRC "TYPE=REDEPLOY,x=14,y=24" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            REQUIRED_TOKENS=("xcenter=14,ycenter=24")
            ;;
        flip_missing_filter_allows_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = type == redeploy" "  FLIP:click = x -> xcenter" "  FLIP:click = y -> ycenter")
            add_timer_event FLIP_SRC "x=12,y=22" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            REQUIRED_TOKENS=("xcenter=12,ycenter=22")
            ;;
        flip_filter_suppresses_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = type == redeploy" "  FLIP:click = x -> xcenter" "  FLIP:click = y -> ycenter")
            add_timer_event FLIP_SRC "type=loiter,x=12,y=22" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            ABSENT_TOKENS=(" FLIP_OUT ")
            ;;
        flip_multiple_filters_suppress_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = type == redeploy" "  FLIP:click = mode == survey" "  FLIP:click = x -> xcenter" "  FLIP:click = y -> ycenter")
            add_timer_event FLIP_SRC "type=redeploy,mode=loiter,x=20,y=30" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            ABSENT_TOKENS=(" FLIP_OUT ")
            ;;
        flip_custom_separator_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = source_separator = |" "  FLIP:click = dest_separator = @" "  FLIP:click = mode == survey" "  FLIP:click = x -> xpos" "  FLIP:click = y -> ypos")
            add_timer_event FLIP_SRC "mode=survey|x=5|y=-2" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            REQUIRED_TOKENS=("xpos=5@ypos=-2")
            ;;
        flip_component_case_sensitive_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = X -> xcenter")
            add_timer_event FLIP_SRC "x=15,X=16" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            REQUIRED_TOKENS=("xcenter=16")
            ABSENT_TOKENS=("xcenter=15")
            ;;
        flip_unmapped_component_omitted_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = x -> xcenter")
            add_timer_event FLIP_SRC "x=8,z=99" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            EXPECTED_ALOG_VALUES=("FLIP_OUT=xcenter=8")
            ;;
        flip_no_mapped_fields_no_output_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = x -> xcenter")
            add_timer_event FLIP_SRC "y=33" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            ABSENT_TOKENS=(" FLIP_OUT ")
            ;;
        flip_duplicate_component_repeats_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = x -> xcenter" "  FLIP:click = y -> ycenter")
            add_timer_event FLIP_SRC "x=10,x=11,y=20" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            REQUIRED_TOKENS=("xcenter=10,xcenter=11,ycenter=20")
            ;;
        flip_empty_value_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = x -> xcenter")
            add_timer_event FLIP_SRC "x=" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            EXPECTED_ALOG_VALUES=("FLIP_OUT=xcenter=")
            ;;
        cycle_guard_no_echo_pass)
            ECHO_LINES=("  Echo = CYCLE_A -> CYCLE_B" "  Echo = CYCLE_B -> CYCLE_A")
            add_timer_event CYCLE_A one 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            ABSENT_TOKENS=(" CYCLE_B ")
            ;;
        self_cycle_guard_no_echo_pass)
            ECHO_LINES=("  Echo = CYCLE_A -> CYCLE_A")
            add_timer_event CYCLE_A self 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            COUNT_VAR="CYCLE_A"
            COUNT_TARGET="1"
            ;;
        indirect_cycle_blocks_all_pass)
            ECHO_LINES=("  Echo = CYCLE_A -> CYCLE_B" "  Echo = CYCLE_B -> CYCLE_C" "  Echo = CYCLE_C -> CYCLE_A" "  Echo = ECHO_SRC_STR -> ECHO_OUT_STR")
            add_timer_event CYCLE_A one 0.5
            add_timer_event ECHO_SRC_STR should_not_echo 0.6
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            ABSENT_TOKENS=(" CYCLE_B " " ECHO_OUT_STR ")
            ;;
        invalid_flip_no_output_pass)
            ECHO_LINES=("  FLIP:bad = source_variable = FLIP_SRC" "  FLIP:bad = dest_variable = FLIP_OUT")
            add_timer_event FLIP_SRC "x=13,y=23" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            ABSENT_TOKENS=(" FLIP_OUT ")
            ;;
        invalid_flip_alias_no_output_pass)
            ECHO_LINES=("  FLIP:bad = source_variable = FLIP_SRC" "  FLIP:bad = dest_variable = FLIP_SRC" "  FLIP:bad = x -> xcenter")
            add_timer_event FLIP_SRC "x=17" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            ABSENT_TOKENS=(" FLIP_OUT ")
            COUNT_VAR="FLIP_SRC"
            COUNT_TARGET="1"
            ;;
        shared_source_dual_flip_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = x -> xcenter" "  FLIP:mark = source_variable = FLIP_SRC" "  FLIP:mark = dest_variable = ECHO_OUT_STR" "  FLIP:mark = y -> ypos")
            add_timer_event FLIP_SRC "x=31,y=41" 0.5
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            EXPECTED_ALOG_VALUES=("FLIP_OUT=xcenter=31" "ECHO_OUT_STR=ypos=41")
            ;;
        dual_flip_independent_pass)
            ECHO_LINES=("  FLIP:click = source_variable = FLIP_SRC" "  FLIP:click = dest_variable = FLIP_OUT" "  FLIP:click = x -> xcenter" "  FLIP:alt = source_variable = ECHO_SRC_STR" "  FLIP:alt = dest_variable = ECHO_OUT_STR" "  FLIP:alt = word -> word_out")
            add_timer_event FLIP_SRC "x=44" 0.5
            add_timer_event ECHO_SRC_STR "word=bravo" 0.6
            PASS_CONDITIONS=("TEST_EVAL_READY = true")
            EXPECTED_ALOG_VALUES=("FLIP_OUT=xcenter=44" "ECHO_OUT_STR=word_out=bravo")
            ;;
        *) return 1 ;;
    esac

    # Leave enough room for pEchoVar to publish before pMissionEval's lead flag.
    add_timer_event TEST_EVAL_READY true 2.0
}

write_case_files() {
    local case_dir="$1"
    local line

    {
        echo "//-------------------------------------------------"
        echo "// FILE: case_echo.moos"
        echo "// NAME: Charles Benjamin"
        echo "//-------------------------------------------------"
        echo ""
        echo "ProcessConfig = pEchoVar"
        echo "{"
        echo "  AppTick   = 10"
        echo "  CommsTick = 10"
        echo ""
        for line in "${ECHO_LINES[@]}"; do
            echo "$line"
        done
        echo "}"
    } > "$case_dir/case_echo.moos"

    {
        echo "//-------------------------------------------------"
        echo "// FILE: case_timer.moos"
        echo "// NAME: Charles Benjamin"
        echo "//-------------------------------------------------"
        echo ""
        echo "ProcessConfig = uTimerScript"
        echo "{"
        echo "  AppTick   = 10"
        echo "  CommsTick = 10"
        echo ""
        for line in "${TIMER_EVENTS[@]}"; do
            echo "$line"
        done
        echo "}"
    } > "$case_dir/case_timer.moos"

    {
        echo "//-------------------------------------------------"
        echo "// FILE: case_eval.moos"
        echo "// NAME: Charles Benjamin"
        echo "//-------------------------------------------------"
        echo ""
        echo "ProcessConfig = pMissionEval"
        echo "{"
        echo "  AppTick   = 4"
        echo "  CommsTick = 4"
        echo ""
        echo "  lead_condition = TEST_EVAL_READY = true"
        for line in "${PASS_CONDITIONS[@]}"; do
            echo "  pass_condition = $line"
        done
        echo ""
        echo "  result_flag  = MISSION_EVALUATED = true"
        echo "  mission_form = pechovar_unit"
        echo "  mission_mod  = $CASE_NAME"
        echo ""
        echo "  report_column    = form=\$[MISSION_FORM]"
        echo "  report_column    = mmod=\$[MMOD]"
        echo "  report_column    = grade=\$[GRADE]"
        echo "  report_column    = eval=\$[TEST_EVAL_READY]"
        for line in "${REPORT_COLUMNS[@]}"; do
            echo "  report_column    = $line"
        done
        echo "  report_column    = mhash=\$[MHASH_SHORT]"
        echo "  report_file      = results.txt"
        echo "}"
    } > "$case_dir/case_eval.moos"
}

evaluation_cutoff() {
    aloggrep MISSION_EVALUATED "$1" 2>/dev/null |
        awk '$2 == "MISSION_EVALUATED" && $4 == "true" {print $1; exit}'
}

validate_alog_windows() {
    local root="$1" alog cutoff found=no
    while IFS= read -r -d '' alog; do
        found=yes
        cutoff=$(evaluation_cutoff "$alog")
        [ -n "$cutoff" ] || return 1
    done < <(find "$root" -type f -name '*.alog' -print0)
    [ "$found" = yes ]
}

alog_window_has_token() {
    local root="$1" token="$2" alog cutoff
    while IFS= read -r -d '' alog; do
        cutoff=$(evaluation_cutoff "$alog")
        awk -v end="$cutoff" -v token="$token" \
            '$1 ~ /^[0-9.]+$/ && $1 <= end && index($0, token) {found=1; exit} END {exit !found}' \
            "$alog" && return 0
    done < <(find "$root" -type f -name '*.alog' -print0)
    return 1
}

alog_window_has_value() {
    local root="$1" var="$2" expected="$3" alog cutoff
    while IFS= read -r -d '' alog; do
        cutoff=$(evaluation_cutoff "$alog")
        aloggrep "$var" "$alog" 2>/dev/null |
            awk -v v="$var" -v expected="$expected" -v end="$cutoff" \
                '$2 == v && $1 <= end && $4 == expected {found=1; exit} END {exit !found}' &&
            return 0
    done < <(find "$root" -type f -name '*.alog' -print0)
    return 1
}

count_alog_posts() {
    local root="$1" var="$2" alog cutoff count total=0 found=no
    while IFS= read -r -d '' alog; do
        found=yes
        cutoff=$(evaluation_cutoff "$alog")
        count=$(aloggrep "$var" "$alog" 2>/dev/null |
            awk -v v="$var" -v end="$cutoff" \
                '$2 == v && $1 <= end {count++} END {print count+0}')
        total=$((total + count))
    done < <(find "$root" -type f -name '*.alog' -print0)
    [ "$found" = yes ] || return 1
    printf '%s\n' "$total"
}

check_alog_evidence() {
    local root="$1" token value_spec var expected count evidence=mission_owned
    if [ "${#REQUIRED_TOKENS[@]}" -eq 0 ] && [ "${#ABSENT_TOKENS[@]}" -eq 0 ] &&
       [ "${#EXPECTED_ALOG_VALUES[@]}" -eq 0 ] && [ -z "$COUNT_VAR" ]; then
        printf 'evidence=%s\n' "$evidence"
        return 0
    fi

    validate_alog_windows "$root" || { echo 'evidence=missing_evaluation_window'; return 1; }
    evidence=alog_window_ok
    for token in "${REQUIRED_TOKENS[@]}"; do
        alog_window_has_token "$root" "$token" || { echo 'evidence=missing_required_token'; return 1; }
    done
    for token in "${ABSENT_TOKENS[@]}"; do
        if alog_window_has_token "$root" "$token"; then
            echo 'evidence=unexpected_token'
            return 1
        fi
    done
    for value_spec in "${EXPECTED_ALOG_VALUES[@]}"; do
        var=${value_spec%%=*}
        expected=${value_spec#*=}
        alog_window_has_value "$root" "$var" "$expected" || {
            echo 'evidence=missing_exact_publication'
            return 1
        }
    done
    if [ -n "$COUNT_VAR" ]; then
        count=$(count_alog_posts "$root" "$COUNT_VAR") || { echo 'evidence=missing_count_log'; return 1; }
        evidence="$evidence count_${COUNT_VAR}=$count target_${COUNT_VAR}=$COUNT_TARGET"
        [ "$count" = "$COUNT_TARGET" ] || { printf 'evidence=%s\n' "$evidence"; return 1; }
    fi
    printf 'evidence=%s\n' "$evidence"
}

prepare_case() {
    local case_name="$1" workdir="$2"
    rm -rf "$workdir"
    mkdir -p "$workdir" || return 1
    cp -R "$MISSION_DIR"/. "$workdir"/ || return 1
    (cd "$workdir" && ./clean.sh >/dev/null 2>&1) || return 1
    if [ "$LOG_MODE" = full ]; then
        nspatch "$workdir/meta_shoreside.moos" \
            "$workdir/full-logging-shoreside.xmoos" \
            "$workdir/meta_shoreside.moosx" || return 1
    fi
    get_case_config "$case_name" || return 1
    write_case_files "$workdir"
}

write_result() {
    local case_name="$1" result_file="$2" launch_rc="$3" workdir="$4"
    local evidence="$5" evidence_rc="$6" line grade_count mission_grade mission_rows provenance

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
        printf 'case=%s grade=fail reason=launch_error launch_rc=%s%s\n' "$case_name" "$launch_rc" "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi
    if [ "$evidence_rc" -ne 0 ]; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=evidence_check_failed%s%s\n' "$case_name" "${evidence:+ $evidence}" "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi
    line=$(without_case_field "$line")
    printf 'case=%s %s%s\n' "$case_name" "$line" "${evidence:+ $evidence}" > "$result_file"
}

run_case() {
    local case_name="$1" workdir="$2" result_file="$3" case_base="$4"
    local launch_rc=0 evidence='' evidence_rc=0 result_line grade
    local -a launch_args

    prepare_case "$case_name" "$workdir" || {
        printf 'case=%s grade=fail reason=prepare_error\n' "$case_name" > "$result_file"
        return 1
    }
    (
        cd "$workdir" || exit 1
        : > results.txt
        launch_args=(--max_time="$MAX_TIME" --mmod="$case_name" "${DISPLAY_ARGS[@]}"
            --shore_mport="$case_base" --shore_pshare="$((case_base + PSHARE_OFFSET))" "$TIME_WARP")
        [ "$JUST_MAKE" = yes ] && launch_args+=(--just_make)
        LOG_MODE_PREPARED=yes ./zlaunch.sh --log="$LOG_MODE" "${launch_args[@]}"
    ) || launch_rc=$?

    if [ "$JUST_MAKE" != yes ] && [ "$launch_rc" -eq 0 ]; then
        evidence=$(check_alog_evidence "$workdir") || evidence_rc=$?
    fi
    write_result "$case_name" "$result_file" "$launch_rc" "$workdir" "$evidence" "$evidence_rc"
    if ! stop_root "$workdir"; then
        printf 'case=%s grade=fail reason=teardown_error\n' "$case_name" > "$result_file"
    fi
    result_line=$(awk 'NF {print; exit}' "$result_file" 2>/dev/null)
    grade=$(field_value "$result_line" grade || true)
    [ "$grade" = pass ]
}

start_case() {
    local case_idx="$1" case_name="${SELECTED_CASES[$1]}" case_dir workdir result_file log_file case_base pid
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
        [ -s "$result_file" ] || printf 'case=%s grade=fail reason=missing_result launch_rc=%s\n' "$case_name" "$rc" > "$result_file"
        exit "$rc"
    ) &
    pid=$!
    PID_CASE[$pid]="$case_name"
    PID_RESULT[$pid]="$result_file"
    PID_LOG[$pid]="$log_file"
    PID_PORT_BASE[$pid]="$case_base"
    if [ "$VERBOSE" = yes ]; then
        printf 'event=start epoch=%s pid=%s case=%s port_base=%s workdir=%s\n' "$(date +%s)" "$pid" "$case_name" "$case_base" "$workdir"
    fi
}

finish_one() {
    local done_pid='' wait_rc=0 case_name line grade
    wait -p done_pid -n || wait_rc=$?
    [ -n "${done_pid:-}" ] || { echo "$ME: wait returned without a completed pid rc=$wait_rc" >&2; return 1; }
    case_name="${PID_CASE[$done_pid]:-}"
    [ -n "$case_name" ] || { echo "$ME: unknown completed pid $done_pid rc=$wait_rc" >&2; return 1; }
    line=$(awk 'NF {print; exit}' "${PID_RESULT[$done_pid]}" 2>/dev/null)
    grade=$(field_value "$line" grade || true)
    if [ "$wait_rc" -ne 0 ] && [ "$grade" = pass ]; then
        printf 'case=%s grade=fail reason=worker_error worker_rc=%s\n' "$case_name" "$wait_rc" > "${PID_RESULT[$done_pid]}"
        grade=fail
    fi
    if [ "$VERBOSE" = yes ]; then
        printf 'event=finish epoch=%s pid=%s case=%s rc=%s grade=%s port_base=%s log=%s\n' "$(date +%s)" "$done_pid" "$case_name" "$wait_rc" "${grade:-missing}" "${PID_PORT_BASE[$done_pid]}" "${PID_LOG[$done_pid]}"
    fi
    unset 'PID_CASE[$done_pid]' 'PID_RESULT[$done_pid]' 'PID_LOG[$done_pid]' 'PID_PORT_BASE[$done_pid]'
    [ "$grade" = pass ]
}

aggregate_results() {
    local total="${#SELECTED_CASES[@]}" case_idx case_name result_file row_count line row_case grade_count grade
    FINAL_FAILURES=0
    RESULT_ROWS=0
    : > "$RESULTS_FILE"
    for ((case_idx = 0; case_idx < total; case_idx++)); do
        case_name="${SELECTED_CASES[$case_idx]}"
        result_file="${CASE_RESULT[$case_idx]:-}"
        line=''
        if [ -n "$result_file" ] && [ -f "$result_file" ]; then
            row_count=$(awk 'NF {count++} END {print count+0}' "$result_file")
            if [ "$row_count" -eq 1 ]; then line=$(awk 'NF {print; exit}' "$result_file"); else line="case=$case_name grade=fail reason=invalid_row_count result_rows=$row_count"; fi
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
            if [ "$grade" != pass ] && [ "$grade" != fail ]; then line="case=$case_name grade=fail reason=malformed_result mission_grade=${grade:-missing}"; fi
        fi
        printf '%s\n' "$line" >> "$RESULTS_FILE"
        RESULT_ROWS=$((RESULT_ROWS + 1))
        grade=$(field_value "$line" grade || true)
        [ "$grade" = pass ] || FINAL_FAILURES=$((FINAL_FAILURES + 1))
    done
}

select_cases
total=${#SELECTED_CASES[@]}
if [ "${DISPLAY_ARGS[0]}" = --gui ] && [ "$total" -ne 1 ]; then die "--gui requires one explicit --case"; fi
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
    if [ "$active" -gt 0 ]; then finish_one || true; active=$((active - 1)); fi
done

aggregate_results
if [ "$RESULT_ROWS" -ne "$total" ] || { [ "$total" -gt 0 ] && [ "$RESULT_ROWS" -eq 0 ]; }; then
    echo "$ME: expected $total result rows but wrote $RESULT_ROWS" >&2
    FINAL_FAILURES=$((FINAL_FAILURES + 1))
fi
cleanup_runtime
elapsed_seconds=$SECONDS
if [ -d "$RUN_ROOT" ]; then kept_root="$RUN_ROOT"; else kept_root=none; fi
[ "$CLEANUP_FAILED" = yes ] && FINAL_FAILURES=$((FINAL_FAILURES + 1))
trap - EXIT INT TERM PIPE

printf 'results=%s failures=%s total=%s jobs=%s log_mode=%s elapsed_seconds=%s bash=%s workdirs=%s\n' "$RESULTS_FILE" "$FINAL_FAILURES" "$total" "$JOBS" "$LOG_MODE" "$elapsed_seconds" "$BASH_VERSION" "$kept_root"
[ "$FINAL_FAILURES" -eq 0 ]
