#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H01-psearchgrid_unit
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
MISSION_DIR="$REPO_DIR/missions/psearchgrid_missions/psearchgrid_unit"
TEARDOWN_HELPER="$REPO_DIR/scripts/moos_scoped_teardown.sh"
RESULTS_FILE="$HARNESS_DIR/results.txt"
RUNS_DIR="$HARNESS_DIR/.harness_runs"
RUN_ROOT=""

TIME_WARP=10
MAX_TIME=30
JOBS=1
PORT_BASE=9000
PORT_STRIDE=20
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
FINISH_FATAL_REASON=""

CASES=(
    initial_grid_publish_pass
    node_local_delta_pass
    node_global_delta_pass
    boundary_origin_delta_pass
    outside_grid_no_delta_pass
    negative_outside_no_delta_pass
    full_grid_report_pass
    custom_var_label_pass
    lowercase_var_name_pass
    custom_full_grid_var_pass
    invalid_report_deltas_default_delta_pass
    reset_grid_clears_pass
    reset_false_payload_clears_pass
    two_cell_delta_pass
    repeated_cell_delta_pass
    sequential_delta_cleared_pass
    match_community_allows_pass
    match_list_allows_pass
    match_community_blocks_pass
    ignore_other_allows_pass
    ignore_community_blocks_pass
    ignore_list_blocks_pass
    malformed_report_absent_pass
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
    if ! moos_scoped_teardown_stop_root "$1"; then
        echo "$ME: scoped teardown failed for $1" >&2
        return 1
    fi
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
        if [ "$KEEP_WORKDIRS" != yes ] && [ "$root_stopped" = yes ] && [ "$CLEANUP_FAILED" = no ]; then rm -rf "$RUN_ROOT"; fi
    fi
    rmdir "$RUNS_DIR" 2>/dev/null || true
    CLEANED=yes
    CLEANING=no
}

on_signal() { exit 130; }
trap cleanup_runtime EXIT
trap on_signal INT TERM PIPE

base_node_report() {
    local name="$1"
    local x="$2"
    local y="$3"
    echo "NAME=$name,X=$x,Y=$y,SPD=0,HDG=90,TYPE=kayak,TIME=1,LENGTH=5"
}

get_case_config() {
    CASE_NAME="$1"
    grid_lines=("report_deltas = true" "grid_label = psg" "grid_var_name = VIEW_GRID")
    grid_config_lines=("grid_config = pts={0,0:20,0:20,20:0,20}" "grid_config = cell_size=10" "grid_config = cell_vars=x:0")
    timer_events=()
    required_var_tokens=()
    required_var_count_tokens=()
    absent_var_tokens=()
    absent_vars=()
    absent_after_marker=""
    absent_after_time="0.2"
    required_after_var_tokens=()
    absent_after_var_tokens=()
    GRID_APP_TICK="10"
    EVAL_TIME="1.8"

    case "$CASE_NAME" in
        initial_grid_publish_pass)
            required_var_tokens=("VIEW_GRID:pts={" "VIEW_GRID:cell_size=10" "VIEW_GRID:cell_vars=x:0" "VIEW_GRID:label=psg")
            ;;
        node_local_delta_pass)
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report abe 5 5)\", time=0.4")
            required_var_tokens=("VIEW_GRID_DELTA:psg@" "VIEW_GRID_DELTA:,x,1")
            ;;
        node_global_delta_pass)
            timer_events=("event = var=NODE_REPORT, val=\"$(base_node_report ben 15 5)\", time=0.4")
            required_var_tokens=("VIEW_GRID_DELTA:psg@" "VIEW_GRID_DELTA:,x,1")
            ;;
        boundary_origin_delta_pass)
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report edge 0 0)\", time=0.4")
            required_var_tokens=("VIEW_GRID_DELTA:psg@" "VIEW_GRID_DELTA:,x,1")
            ;;
        outside_grid_no_delta_pass)
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report far 50 50)\", time=0.4")
            absent_vars=("VIEW_GRID_DELTA")
            ;;
        negative_outside_no_delta_pass)
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report neg -1 -1)\", time=0.4")
            absent_vars=("VIEW_GRID_DELTA")
            ;;
        full_grid_report_pass)
            grid_lines=("report_deltas = false" "grid_label = psg" "grid_var_name = VIEW_GRID")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report full 5 5)\", time=0.4")
            required_var_tokens=("VIEW_GRID:cell=" "VIEW_GRID:cell=0:x:1")
            ;;
        custom_var_label_pass)
            grid_lines=("report_deltas = true" "grid_label = custom_psg" "grid_var_name = SEARCH_GRID")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report custom 5 5)\", time=0.4")
            required_var_tokens=("SEARCH_GRID:label=psg" "SEARCH_GRID_DELTA:custom_psg@" "SEARCH_GRID_DELTA:,x,1")
            absent_vars=("VIEW_GRID_DELTA")
            ;;
        lowercase_var_name_pass)
            grid_lines=("report_deltas = true" "grid_label = lower_psg" "grid_var_name = search_grid")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report lower 5 5)\", time=0.4")
            required_var_tokens=("SEARCH_GRID:label=psg" "SEARCH_GRID_DELTA:lower_psg@" "SEARCH_GRID_DELTA:,x,1")
            absent_vars=("VIEW_GRID_DELTA")
            ;;
        custom_full_grid_var_pass)
            grid_lines=("report_deltas = false" "grid_label = custom_full" "grid_var_name = search_grid")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report customfull 5 5)\", time=0.4")
            required_var_tokens=("SEARCH_GRID:cell=0:x:1")
            absent_vars=("VIEW_GRID")
            ;;
        invalid_report_deltas_default_delta_pass)
            grid_lines=("report_deltas = maybe" "grid_label = psg" "grid_var_name = VIEW_GRID")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report defaultdelta 5 5)\", time=0.4")
            required_var_tokens=("VIEW_GRID_DELTA:psg@" "VIEW_GRID_DELTA:,x,1")
            ;;
        reset_grid_clears_pass)
            grid_lines=("report_deltas = false" "grid_label = psg" "grid_var_name = VIEW_GRID")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report reset 5 5)\", time=0.4" "event = var=PSG_RESET_GRID, val=true, time=0.9")
            required_var_tokens=("VIEW_GRID:cell=0:x:1")
            absent_after_marker="PSG_RESET_GRID"
            required_after_var_tokens=("VIEW_GRID:cell_vars=x:0,label=psg")
            absent_after_var_tokens=("VIEW_GRID:cell=0:x:1")
            EVAL_TIME="1.6"
            ;;
        reset_false_payload_clears_pass)
            grid_lines=("report_deltas = false" "grid_label = psg" "grid_var_name = VIEW_GRID")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report resetfalse 5 5)\", time=0.4" "event = var=PSG_RESET_GRID, val=false, time=0.9")
            required_var_tokens=("VIEW_GRID:cell=0:x:1")
            absent_after_marker="PSG_RESET_GRID"
            required_after_var_tokens=("VIEW_GRID:cell_vars=x:0,label=psg")
            absent_after_var_tokens=("VIEW_GRID:cell=0:x:1")
            EVAL_TIME="1.6"
            ;;
        two_cell_delta_pass)
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report one 5 5)\", time=0.4" "event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report two 15 5)\", time=0.4")
            required_var_tokens=("VIEW_GRID_DELTA:psg@0,x,1:2,x,1")
            ;;
        repeated_cell_delta_pass)
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report one 5 5)\", time=0.4" "event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report two 5 5)\", time=0.4")
            required_var_tokens=("VIEW_GRID_DELTA:psg@" "VIEW_GRID_DELTA:,x,2")
            GRID_APP_TICK="1"
            ;;
        sequential_delta_cleared_pass)
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report one 5 5)\", time=0.4" "event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report two 5 5)\", time=1.0")
            required_var_count_tokens=("VIEW_GRID_DELTA:,x,1:2")
            absent_var_tokens=("VIEW_GRID_DELTA:,x,2")
            EVAL_TIME="1.8"
            ;;
        match_community_allows_pass)
            grid_lines=("report_deltas = true" "grid_label = psg" "grid_var_name = VIEW_GRID" "match_name = shoreside")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report allowed 5 5)\", time=0.4")
            required_var_tokens=("VIEW_GRID_DELTA:psg@" "VIEW_GRID_DELTA:,x,1")
            ;;
        match_list_allows_pass)
            grid_lines=("report_deltas = true" "grid_label = psg" "grid_var_name = VIEW_GRID" "match_name = {vehicle,shoreside}")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report listallowed 5 5)\", time=0.4")
            required_var_tokens=("VIEW_GRID_DELTA:psg@" "VIEW_GRID_DELTA:,x,1")
            ;;
        match_community_blocks_pass)
            grid_lines=("report_deltas = true" "grid_label = psg" "grid_var_name = VIEW_GRID" "match_name = vehicle")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report blocked 5 5)\", time=0.4")
            absent_vars=("VIEW_GRID_DELTA")
            ;;
        ignore_other_allows_pass)
            grid_lines=("report_deltas = true" "grid_label = psg" "grid_var_name = VIEW_GRID" "ignore_name = vehicle")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report notignored 5 5)\", time=0.4")
            required_var_tokens=("VIEW_GRID_DELTA:psg@" "VIEW_GRID_DELTA:,x,1")
            ;;
        ignore_community_blocks_pass)
            grid_lines=("report_deltas = true" "grid_label = psg" "grid_var_name = VIEW_GRID" "ignore_name = shoreside")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report ignored 5 5)\", time=0.4")
            absent_vars=("VIEW_GRID_DELTA")
            ;;
        ignore_list_blocks_pass)
            grid_lines=("report_deltas = true" "grid_label = psg" "grid_var_name = VIEW_GRID" "ignore_name = {vehicle,shoreside}")
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"$(base_node_report listignored 5 5)\", time=0.4")
            absent_vars=("VIEW_GRID_DELTA")
            ;;
        malformed_report_absent_pass)
            timer_events=("event = var=NODE_REPORT_LOCAL, val=\"NAME=bad,X=5\", time=0.4")
            absent_vars=("VIEW_GRID_DELTA")
            ;;
    esac
}


write_case_files() {
    local case_dir="$1"
    local item
    local var
    local seen_required=" "
    local -a required_vars=()

    {
        echo "ProcessConfig = pSearchGrid"
        echo "{"
        echo "  AppTick   = $GRID_APP_TICK"
        echo "  CommsTick = 10"
        echo ""
        for item in "${grid_lines[@]}"; do
            echo "  $item"
        done
        for item in "${grid_config_lines[@]}"; do
            echo "  $item"
        done
        echo "}"
    } > "$case_dir/case_searchgrid.moos"

    {
        echo "ProcessConfig = uTimerScript"
        echo "{"
        echo "  AppTick   = 10"
        echo "  CommsTick = 10"
        echo ""
        for item in "${timer_events[@]}"; do
            echo "  $item"
        done
        echo "  event = var=TEST_EVAL_READY, val=true, time=$EVAL_TIME"
        echo "}"
    } > "$case_dir/case_timer.moos"

    for item in "${required_var_tokens[@]}" "${required_var_count_tokens[@]}"; do
        [ -n "$item" ] || continue
        var="${item%%:*}"
        case "$seen_required" in
            *" $var "*) ;;
            *)
                required_vars+=("$var")
                seen_required="$seen_required$var "
                ;;
        esac
    done

    {
        echo "ProcessConfig = pMissionEval"
        echo "{"
        echo "  AppTick   = 4"
        echo "  CommsTick = 4"
        echo ""
        echo "  lead_condition = TEST_EVAL_READY = true"
        if [ "${#required_vars[@]}" -gt 0 ]; then
            for var in "${required_vars[@]}"; do
                echo "  pass_condition = $var != __missing_$var"
            done
        else
            echo "  pass_condition = TEST_EVAL_READY = true"
        fi
        for var in "${absent_vars[@]}"; do
            echo "  fail_condition = $var != __missing_$var"
        done
        echo ""
        echo "  result_flag  = MISSION_EVALUATED = true"
        echo "  mission_form = psearchgrid_unit"
        echo ""
        echo "  report_column    = grade=\$[GRADE]"
        echo "  report_column    = form=\$[MISSION_FORM]"
        echo "  report_column    = eval=\$[TEST_EVAL_READY]"
        echo "  report_column    = mhash=\$[MHASH_SHORT]"
        echo "  report_file      = results.txt"
        echo "}"
    } > "$case_dir/case_eval.moos"
}

find_alog() {
    local case_dir="$1"
    find "$case_dir" -name '*.alog' -print | sort | tail -n 1
}

evaluation_cutoff() {
    local alog="$1"
    awk '$2 == "MISSION_EVALUATED" && $4 == "true" {print $1; exit}' "$alog"
}

alog_lines_for_var() {
    local case_dir="$1"
    local var="$2"
    local alog
    local cutoff

    alog=$(find_alog "$case_dir")
    [ -n "$alog" ] || return 1
    cutoff=$(evaluation_cutoff "$alog")
    [ -n "$cutoff" ] || return 1
    awk -v var="$var" -v cutoff="$cutoff" \
        '$2 == var && ($1 + 0) <= (cutoff + 0) {print}' "$alog"
}

marker_time_before_eval() {
    local case_dir="$1"
    local marker="$2"
    local alog
    local cutoff

    alog=$(find_alog "$case_dir")
    [ -n "$alog" ] || return 1
    cutoff=$(evaluation_cutoff "$alog")
    [ -n "$cutoff" ] || return 1
    awk -v marker="$marker" -v cutoff="$cutoff" \
        '$2 == marker && ($1 + 0) <= (cutoff + 0) {print $1; exit}' "$alog"
}

check_payloads() {
    local case_dir="$1"
    local status="success"
    local item
    local var
    local token
    local count
    local needed
    local lines
    local base_time
    local threshold
    local after_lines
    local alog
    local cutoff

    alog=$(find_alog "$case_dir")
    [ -n "$alog" ] || { echo "missing_evaluation_window"; return 0; }
    cutoff=$(evaluation_cutoff "$alog")
    [ -n "$cutoff" ] || { echo "missing_evaluation_window"; return 0; }

    for item in "${required_var_tokens[@]}"; do
        var="${item%%:*}"
        token="${item#*:}"
        lines=$(alog_lines_for_var "$case_dir" "$var")
        if ! grep -Fq -- "$token" <<< "$lines"; then
            status="mismatch"
        fi
    done
    for item in "${required_var_count_tokens[@]}"; do
        var="${item%%:*}"
        token="${item#*:}"
        token="${token%:*}"
        needed="${item##*:}"
        lines=$(alog_lines_for_var "$case_dir" "$var")
        count=$(grep -Fc -- "$token" <<< "$lines" || true)
        if [ "$count" -lt "$needed" ]; then
            status="mismatch"
        fi
    done
    for item in "${absent_var_tokens[@]}"; do
        var="${item%%:*}"
        token="${item#*:}"
        lines=$(alog_lines_for_var "$case_dir" "$var")
        if grep -Fq -- "$token" <<< "$lines"; then
            status="mismatch"
        fi
    done
    for var in "${absent_vars[@]}"; do
        lines=$(alog_lines_for_var "$case_dir" "$var")
        if [ -n "$lines" ]; then
            status="mismatch"
        fi
    done
    if [ -n "$absent_after_marker" ]; then
        base_time=$(marker_time_before_eval "$case_dir" "$absent_after_marker")
        if [ -z "$base_time" ]; then
            status="mismatch"
        else
            threshold=$(awk -v base="$base_time" -v offset="$absent_after_time" \
                'BEGIN { print base + offset }')
            for item in "${required_after_var_tokens[@]}"; do
                var="${item%%:*}"
                token="${item#*:}"
                after_lines=$(alog_lines_for_var "$case_dir" "$var" |
                    awk -v min_time="$threshold" '$1+0 > min_time {print}')
                if ! grep -Fq -- "$token" <<< "$after_lines"; then
                    status="mismatch"
                fi
            done
            for item in "${absent_after_var_tokens[@]}"; do
                var="${item%%:*}"
                token="${item#*:}"
                after_lines=$(alog_lines_for_var "$case_dir" "$var" |
                    awk -v min_time="$threshold" '$1+0 > min_time {print}')
                if grep -Fq -- "$token" <<< "$after_lines"; then
                    status="mismatch"
                fi
            done
        fi
    fi
    echo "$status"
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
    local evidence="$5"
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
    if [ "$mission_grade" = pass ] && [ "$evidence" != success ]; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=artifact_check_failed payload=%s%s\n' \
            "$case_name" "$evidence" "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi
    line=$(without_case_field "$line")
    printf 'case=%s %s payload=success\n' "$case_name" "$line" > "$result_file"
}

run_case() {
    local case_name="$1"
    local workdir="$2"
    local result_file="$3"
    local case_base="$4"
    local launch_rc=0
    local -a launch_args=()
    local evidence=not_checked
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

    if [ "$JUST_MAKE" = no ]; then
        evidence=$(check_payloads "$workdir")
    fi
    write_result "$case_name" "$result_file" "$launch_rc" "$workdir" "$evidence"
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
if [ -d "$RUN_ROOT" ]; then kept_root="$RUN_ROOT"; else kept_root=none; fi
if [ "$CLEANUP_FAILED" = yes ]; then FINAL_FAILURES=$((FINAL_FAILURES + 1)); fi
trap - EXIT INT TERM PIPE

printf 'results=%s failures=%s total=%s jobs=%s log_mode=%s elapsed_seconds=%s bash=%s workdirs=%s\n' \
    "$RESULTS_FILE" "$FINAL_FAILURES" "$total" "$JOBS" "$LOG_MODE" "$elapsed_seconds" "$BASH_VERSION" "$kept_root"

[ "$FINAL_FAILURES" -eq 0 ]
