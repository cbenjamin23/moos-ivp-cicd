#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H01-pspoofnode_unit
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
MISSION_DIR="$REPO_DIR/missions/pspoofnode_missions/pspoofnode_unit"
TEARDOWN_HELPER="$REPO_DIR/scripts/moos_scoped_teardown.sh"
RESULTS_FILE="$HARNESS_DIR/results.txt"
RUNS_DIR="$HARNESS_DIR/.harness_runs"
RUN_ROOT=""

TIME_WARP=10
MAX_TIME=30
JOBS=1
PORT_BASE=9000
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
FINISH_FATAL_REASON=""

CASES=(
    config_static_report_pass
    mail_spoof_report_pass
    mail_group_vsource_pass
    default_fields_pass
    generated_name_pass
    moving_contact_advances_pass
    duration_expires_pass
    explicit_zero_duration_persists_pass
    duplicate_name_update_pass
    cancel_vname_pass
    cancel_group_pass
    cancel_contact_alias_pass
    runtime_defaults_pass
    default_after_spoof_order_pass
    runtime_length_ignored_pass
    default_group_vsource_not_inherited_pass
    default_duration_expires_pass
    invalid_default_vtype_fallback_pass
    invalid_default_color_fallback_pass
    mixed_case_request_normalized_pass
    runtime_color_unvalidated_pass
    unknown_alnum_type_preserved_pass
    negative_speed_accepted_pass
    invalid_request_absent_pass
    invalid_x_absent_pass
    invalid_name_absent_pass
    invalid_group_absent_pass
    invalid_type_absent_pass
    invalid_vsource_absent_pass
    invalid_heading_absent_pass
    invalid_speed_absent_pass
    invalid_length_absent_pass
    invalid_duration_absent_pass
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

get_case_config() {
    CASE_NAME="$1"
    SPOOF_LINES=()
    TIMER_EVENTS=()
    REQUIRED_TOKENS=()
    REQUIRED_REPORT_ROWS=()
    FIRST_REPORT_NAME=""
    FIRST_REPORT_TOKENS=()
    FIRST_REPORT_RANGES=()
    GENERATED_NAME_COUNT=0
    ABSENT_TOKENS=()
    ABSENT_AFTER_TIME=""
    ABSENT_AFTER_MARKER=""
    ABSENT_AFTER_TOKENS=()
    REQUIRED_AFTER_TIME=""
    REQUIRED_AFTER_MARKER=""
    REQUIRED_AFTER_TOKENS=()
    ABSENT_FOR_REQUIRED_NAME=""
    ABSENT_FOR_REQUIRED_TOKENS=()
    MOVEMENT_NAME=""
    EVAL_TIME="1.8"

    case "$CASE_NAME" in
        config_static_report_pass)
            SPOOF_LINES=("spoof = x=10,y=20,name=alpha,type=heron,group=red,color=green,vsource=ais,hdg=90,spd=0")
            REQUIRED_REPORT_ROWS=("NAME=alpha|X=10|Y=20|SPD=0|HDG=90|TYPE=heron|GROUP=red|COLOR=green|VSOURCE=ais")
            ;;
        mail_spoof_report_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=5,y=-3,name=bravo,type=kayak,color=yellow,hdg=180,spd=0\", time=0.3")
            REQUIRED_REPORT_ROWS=("NAME=bravo|X=5|Y=-3|SPD=0|HDG=180|TYPE=kayak|COLOR=yellow")
            ;;
        mail_group_vsource_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=4,y=6,name=papa,group=team,type=ship,color=yellow,vsource=radar,hdg=270,spd=0\", time=0.3")
            REQUIRED_REPORT_ROWS=("NAME=papa|X=4|Y=6|SPD=0|HDG=270|TYPE=ship|GROUP=team|COLOR=yellow|VSOURCE=radar")
            ;;
        default_fields_pass)
            SPOOF_LINES=("default_vtype = ship" "default_color = orange" "default_hdg = 135" "default_spd = 0.4" "default_length = 8" "spoof = x=0,y=0,name=charlie")
            REQUIRED_REPORT_ROWS=("NAME=charlie|TYPE=ship|COLOR=orange|HDG=135|SPD=0.4|LENGTH=8")
            ;;
        generated_name_pass)
            SPOOF_LINES=("spoof = x=1,y=2,type=auv,color=blue" "spoof = x=3,y=4,type=auv,color=blue")
            REQUIRED_REPORT_ROWS=("X=1|Y=2|TYPE=auv|COLOR=blue" "X=3|Y=4|TYPE=auv|COLOR=blue")
            GENERATED_NAME_COUNT=2
            ;;
        moving_contact_advances_pass)
            SPOOF_LINES=("spoof = x=0,y=0,name=delta,hdg=90,spd=2")
            REQUIRED_TOKENS=("NAME=delta" "SPD=2" "HDG=90")
            MOVEMENT_NAME="delta"
            EVAL_TIME="2.2"
            ;;
        duration_expires_pass)
            SPOOF_LINES=("spoof = x=2,y=2,name=echo,dur=0.7")
            REQUIRED_TOKENS=("NAME=echo")
            ABSENT_AFTER_TIME="1.4"
            ABSENT_AFTER_TOKENS=("NAME=echo")
            EVAL_TIME="2.0"
            ;;
        explicit_zero_duration_persists_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=3,y=3,name=quebec,dur=0\", time=0.2")
            REQUIRED_TOKENS=("NAME=quebec")
            REQUIRED_AFTER_TIME="1.3"
            REQUIRED_AFTER_TOKENS=("NAME=quebec")
            EVAL_TIME="2.0"
            ;;
        duplicate_name_update_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=1,y=1,name=romeo\", time=0.2" "event = var=SPOOF, val=\"x=8,y=8,name=romeo\", time=0.9")
            REQUIRED_TOKENS=("NAME=romeo")
            REQUIRED_AFTER_TIME="1.3"
            REQUIRED_AFTER_TOKENS=("NAME=romeo" "X=8" "Y=8")
            ABSENT_AFTER_TIME="1.3"
            ABSENT_AFTER_TOKENS=("X=1" "Y=1")
            EVAL_TIME="2.0"
            ;;
        cancel_vname_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=2,y=2,name=foxtrot,group=red\", time=0.2" "event = var=SPOOF, val=\"x=4,y=4,name=golf,group=red\", time=0.2" "event = var=SPOOF_CANCEL, val=\"vname=foxtrot\", time=0.9")
            REQUIRED_TOKENS=("NAME=foxtrot" "NAME=golf")
            ABSENT_AFTER_TIME="0.4"
            ABSENT_AFTER_MARKER="SPOOF_CANCEL"
            ABSENT_AFTER_TOKENS=("NAME=foxtrot")
            REQUIRED_AFTER_TIME="0.4"
            REQUIRED_AFTER_MARKER="SPOOF_CANCEL"
            REQUIRED_AFTER_TOKENS=("NAME=golf")
            ;;
        cancel_group_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=2,y=2,name=hotel,group=red\", time=0.2" "event = var=SPOOF, val=\"x=4,y=4,name=india,group=blue\", time=0.2" "event = var=SPOOF_CANCEL, val=\"group=red\", time=0.9")
            REQUIRED_TOKENS=("NAME=hotel" "NAME=india")
            ABSENT_AFTER_TIME="0.4"
            ABSENT_AFTER_MARKER="SPOOF_CANCEL"
            ABSENT_AFTER_TOKENS=("NAME=hotel")
            REQUIRED_AFTER_TIME="0.4"
            REQUIRED_AFTER_MARKER="SPOOF_CANCEL"
            REQUIRED_AFTER_TOKENS=("NAME=india")
            ;;
        cancel_contact_alias_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=2,y=2,name=kilo,group=red\", time=0.2" "event = var=SPOOF, val=\"x=4,y=4,name=lima,group=red\", time=0.2" "event = var=SPOOF_CANCEL, val=\"contact=kilo\", time=0.9")
            REQUIRED_TOKENS=("NAME=kilo" "NAME=lima")
            ABSENT_AFTER_TIME="0.4"
            ABSENT_AFTER_MARKER="SPOOF_CANCEL"
            ABSENT_AFTER_TOKENS=("NAME=kilo")
            REQUIRED_AFTER_TIME="0.4"
            REQUIRED_AFTER_MARKER="SPOOF_CANCEL"
            REQUIRED_AFTER_TOKENS=("NAME=lima")
            ;;
        runtime_defaults_pass)
            SPOOF_LINES=("default_vtype = ship" "default_color = orange" "default_hdg = 135" "default_spd = 0.4" "default_length = 8")
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=6,y=7,name=mike\", time=0.3")
            REQUIRED_REPORT_ROWS=("NAME=mike|TYPE=ship|COLOR=orange|HDG=135|SPD=0.4|LENGTH=8")
            ;;
        default_after_spoof_order_pass)
            SPOOF_LINES=("spoof = x=4,y=5,name=orderly" "default_vtype = ship" "default_color = orange" "default_hdg = 222" "default_length = 9")
            REQUIRED_TOKENS=("NAME=orderly" "TYPE=ship" "COLOR=orange" "HDG=222" "LENGTH=9")
            ;;
        runtime_length_ignored_pass)
            SPOOF_LINES=("default_length = 8")
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=6,y=7,name=victor,len=12\", time=0.3")
            REQUIRED_TOKENS=("NAME=victor" "LENGTH=8")
            ABSENT_FOR_REQUIRED_NAME="victor"
            ABSENT_FOR_REQUIRED_TOKENS=("LENGTH=12")
            ;;
        default_group_vsource_not_inherited_pass)
            SPOOF_LINES=("default_group = fleet" "default_vsource = radar" "spoof = x=2,y=2,name=whiskey")
            REQUIRED_TOKENS=("NAME=whiskey")
            ABSENT_FOR_REQUIRED_NAME="whiskey"
            ABSENT_FOR_REQUIRED_TOKENS=("GROUP=fleet" "VSOURCE=radar")
            ;;
        default_duration_expires_pass)
            SPOOF_LINES=("default_duration = 0.7" "spoof = x=2,y=2,name=november")
            REQUIRED_TOKENS=("NAME=november")
            ABSENT_AFTER_TIME="1.4"
            ABSENT_AFTER_TOKENS=("NAME=november")
            EVAL_TIME="2.0"
            ;;
        invalid_default_vtype_fallback_pass)
            SPOOF_LINES=("default_vtype = dragon" "spoof = x=2,y=2,name=xray")
            REQUIRED_TOKENS=("NAME=xray" "TYPE=kayak")
            ABSENT_FOR_REQUIRED_NAME="xray"
            ABSENT_FOR_REQUIRED_TOKENS=("TYPE=dragon")
            ;;
        invalid_default_color_fallback_pass)
            SPOOF_LINES=("default_color = notacolor" "spoof = x=2,y=2,name=colorbad")
            REQUIRED_TOKENS=("NAME=colorbad" "COLOR=purple")
            ABSENT_FOR_REQUIRED_NAME="colorbad"
            ABSENT_FOR_REQUIRED_TOKENS=("COLOR=notacolor")
            ;;
        mixed_case_request_normalized_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=3,y=3,name=MiXeD,type=Heron,group=TeamA,color=Yellow,vsource=Radar\", time=0.2")
            REQUIRED_TOKENS=("NAME=mixed" "TYPE=heron" "GROUP=teama" "COLOR=yellow" "VSOURCE=radar")
            ;;
        runtime_color_unvalidated_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=3,y=3,name=colorfree,color=notacolor\", time=0.2")
            REQUIRED_TOKENS=("NAME=colorfree" "COLOR=notacolor")
            ;;
        unknown_alnum_type_preserved_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=3,y=3,name=yankee,type=dragon\", time=0.2")
            REQUIRED_TOKENS=("NAME=yankee" "TYPE=dragon")
            ;;
        negative_speed_accepted_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=3,y=3,name=backward,spd=-1,hdg=90\", time=0.2")
            FIRST_REPORT_NAME="backward"
            FIRST_REPORT_TOKENS=("NAME=backward" "Y=3" "SPD=-1" "HDG=90")
            FIRST_REPORT_RANGES=("X:2.4:3.0")
            ;;
        invalid_request_absent_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=9,name=juliet\", time=0.2")
            ABSENT_TOKENS=("NAME=juliet")
            ;;
        invalid_x_absent_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=west,y=9,name=zulu\", time=0.2")
            ABSENT_TOKENS=("NAME=zulu")
            ;;
        invalid_name_absent_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=9,y=9,name=bad-name\", time=0.2")
            ABSENT_TOKENS=("NAME=bad-name" "NAME=bad")
            ;;
        invalid_group_absent_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=9,y=9,name=sierra,group=bad-team\", time=0.2")
            ABSENT_TOKENS=("NAME=sierra")
            ;;
        invalid_type_absent_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=9,y=9,name=alpha2,type=bad-type\", time=0.2")
            ABSENT_TOKENS=("NAME=alpha2")
            ;;
        invalid_vsource_absent_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=9,y=9,name=bravo2,vsource=bad-source\", time=0.2")
            ABSENT_TOKENS=("NAME=bravo2")
            ;;
        invalid_heading_absent_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=9,y=9,name=charlie2,hdg=east\", time=0.2")
            ABSENT_TOKENS=("NAME=charlie2")
            ;;
        invalid_speed_absent_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=9,y=9,name=tango,spd=fast\", time=0.2")
            ABSENT_TOKENS=("NAME=tango")
            ;;
        invalid_length_absent_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=9,y=9,name=uniform,len=long\", time=0.2")
            ABSENT_TOKENS=("NAME=uniform")
            ;;
        invalid_duration_absent_pass)
            TIMER_EVENTS=("event = var=SPOOF, val=\"x=9,y=9,name=oscar,dur=soon\", time=0.2")
            ABSENT_TOKENS=("NAME=oscar")
            ;;
    esac
}

write_case_files() {
    local case_dir="$1"
    local item
    {
        echo "ProcessConfig = pSpoofNode"
        echo "{"
        echo "  AppTick   = 10"
        echo "  CommsTick = 10"
        echo ""
        echo "  refresh_interval = 0.2"
        for item in "${SPOOF_LINES[@]}"; do
            echo "  $item"
        done
        echo "}"
    } > "$case_dir/case_spoof.moos"

    {
        echo "ProcessConfig = uTimerScript"
        echo "{"
        echo "  AppTick   = 10"
        echo "  CommsTick = 10"
        echo ""
        for item in "${TIMER_EVENTS[@]}"; do
            echo "  $item"
        done
        echo "  event = var=TEST_EVAL_READY, val=true, time=$EVAL_TIME"
        echo "}"
    } > "$case_dir/case_timer.moos"

    {
        echo "ProcessConfig = pMissionEval"
        echo "{"
        echo "  AppTick   = 4"
        echo "  CommsTick = 4"
        echo ""
        echo "  lead_condition = TEST_EVAL_READY = true"
        if [ "${#ABSENT_TOKENS[@]}" -gt 0 ]; then
            echo "  pass_condition = TEST_EVAL_READY = true"
            echo "  fail_condition = NODE_REPORT != __no_node_report__"
        else
            echo "  pass_condition = NODE_REPORT != __no_node_report__"
        fi
        echo ""
        echo "  result_flag  = MISSION_EVALUATED = true"
        echo "  mission_form = pspoofnode_unit"
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

node_reports_for_case() {
    local case_dir="$1"
    local alog
    local cutoff
    alog=$(find_alog "$case_dir")
    [ -n "$alog" ] || return 1
    cutoff=$(evaluation_cutoff "$alog")
    [ -n "$cutoff" ] || return 1
    awk -v cutoff="$cutoff" \
        '$2 == "NODE_REPORT" && ($1 + 0) <= (cutoff + 0) {print}' "$alog"
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

field_from_report() {
    local report="$1"
    local key="$2"
    echo "$report" | sed -n "s/.*$key=\\([^, ]*\\).*/\\1/p"
}

report_set_contains_row() {
    local reports="$1"
    local spec="$2"
    local report
    local token
    local matches
    local -a row_tokens=()

    IFS='|' read -r -a row_tokens <<< "$spec"
    while IFS= read -r report; do
        [ -n "$report" ] || continue
        matches=yes
        for token in "${row_tokens[@]}"; do
            if [[ "$report" != *"$token"* ]]; then
                matches=no
                break
            fi
        done
        [ "$matches" = yes ] && return 0
    done <<< "$reports"
    return 1
}

generated_names_are_distinct() {
    local reports="$1"
    local expected_count="$2"
    local report
    local name
    local -A names=()

    while IFS= read -r report; do
        [[ "$report" == *"TYPE=auv"* && "$report" == *"COLOR=blue"* ]] || continue
        name=$(field_from_report "$report" NAME)
        [[ "$name" =~ ^C[0-9]{4}$ ]] || return 1
        names["$name"]=1
    done <<< "$reports"

    [ "${#names[@]}" -eq "$expected_count" ]
}

check_payloads() {
    local case_dir="$1"
    local reports="$2"
    local status="success"
    local token
    local row_spec
    local range_spec
    local field
    local min_value
    local max_value
    local observed
    local base_time
    local threshold
    local after_reports
    local first_report
    local last_report
    local first_x
    local last_x

    for token in "${REQUIRED_TOKENS[@]}"; do
        if ! echo "$reports" | grep -Fq -- "$token"; then
            status="mismatch"
        fi
    done
    for row_spec in "${REQUIRED_REPORT_ROWS[@]}"; do
        if ! report_set_contains_row "$reports" "$row_spec"; then
            status="mismatch"
        fi
    done
    if [ "$FIRST_REPORT_NAME" != "" ]; then
        first_report=$(echo "$reports" | grep -F "NAME=$FIRST_REPORT_NAME" | head -n 1)
        if [ -z "$first_report" ]; then
            status="mismatch"
        else
            for token in "${FIRST_REPORT_TOKENS[@]}"; do
                [[ "$first_report" == *"$token"* ]] || status="mismatch"
            done
            for range_spec in "${FIRST_REPORT_RANGES[@]}"; do
                IFS=: read -r field min_value max_value <<< "$range_spec"
                observed=$(field_from_report "$first_report" "$field")
                if [ -z "$observed" ] || ! awk -v value="$observed" -v min="$min_value" -v max="$max_value" \
                    'BEGIN {exit !(value >= min && value <= max)}'; then
                    status="mismatch"
                fi
            done
        fi
    fi
    if [ "$GENERATED_NAME_COUNT" -gt 0 ] && \
       ! generated_names_are_distinct "$reports" "$GENERATED_NAME_COUNT"; then
        status="mismatch"
    fi
    for token in "${ABSENT_TOKENS[@]}"; do
        if echo "$reports" | grep -Fq -- "$token"; then
            status="mismatch"
        fi
    done
    if [ "$ABSENT_FOR_REQUIRED_NAME" != "" ]; then
        local named_reports
        named_reports=$(echo "$reports" | grep -F "NAME=$ABSENT_FOR_REQUIRED_NAME" || true)
        for token in "${ABSENT_FOR_REQUIRED_TOKENS[@]}"; do
            if echo "$named_reports" | grep -Fq -- "$token"; then
                status="mismatch"
            fi
        done
    fi
    if [ "$ABSENT_AFTER_TIME" != "" ]; then
        if [ "$ABSENT_AFTER_MARKER" != "" ]; then
            base_time=$(marker_time_before_eval "$case_dir" "$ABSENT_AFTER_MARKER")
        else
            base_time=$(echo "$reports" | head -n 1 | awk '{print $1}')
        fi
        if [ -z "$base_time" ]; then
            status="mismatch"
        else
            threshold=$(awk -v base="$base_time" -v offset="$ABSENT_AFTER_TIME" 'BEGIN { print base + offset }')
            after_reports=$(echo "$reports" | awk -v min_time="$threshold" '$1+0 > min_time {print}')
            for token in "${ABSENT_AFTER_TOKENS[@]}"; do
                if echo "$after_reports" | grep -Fq -- "$token"; then
                    status="mismatch"
                fi
            done
        fi
    fi
    if [ "$REQUIRED_AFTER_TIME" != "" ]; then
        if [ "$REQUIRED_AFTER_MARKER" != "" ]; then
            base_time=$(marker_time_before_eval "$case_dir" "$REQUIRED_AFTER_MARKER")
        else
            base_time=$(echo "$reports" | head -n 1 | awk '{print $1}')
        fi
        if [ -z "$base_time" ]; then
            status="mismatch"
        else
            threshold=$(awk -v base="$base_time" -v offset="$REQUIRED_AFTER_TIME" 'BEGIN { print base + offset }')
            after_reports=$(echo "$reports" | awk -v min_time="$threshold" '$1+0 > min_time {print}')
            for token in "${REQUIRED_AFTER_TOKENS[@]}"; do
                if ! echo "$after_reports" | grep -Fq -- "$token"; then
                    status="mismatch"
                fi
            done
        fi
    fi
    if [ "$MOVEMENT_NAME" != "" ]; then
        first_report=$(echo "$reports" | grep -F "NAME=$MOVEMENT_NAME" | head -n 1)
        last_report=$(echo "$reports" | grep -F "NAME=$MOVEMENT_NAME" | tail -n 1)
        first_x=$(field_from_report "$first_report" "X")
        last_x=$(field_from_report "$last_report" "X")
        if ! awk -v first="$first_x" -v last="$last_x" 'BEGIN { exit !(last > first + 0.1) }'; then
            status="mismatch"
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
    local report_count="$6"
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
        printf 'case=%s grade=fail reason=artifact_check_failed evidence=%s reports=%s%s\n' \
            "$case_name" "$evidence" "$report_count" "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi

    line=$(without_case_field "$line")
    printf 'case=%s %s evidence=node_reports_ok reports=%s\n' \
        "$case_name" "$line" "$report_count" > "$result_file"
}

run_case() {
    local case_name="$1"
    local workdir="$2"
    local result_file="$3"
    local case_base="$4"
    local launch_rc=0
    local -a launch_args=()
    local reports=""
    local evidence=missing_evaluation_window
    local report_count=0
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
        if reports=$(node_reports_for_case "$workdir"); then
            evidence=$(check_payloads "$workdir" "$reports")
            report_count=$(awk 'NF {count++} END {print count+0}' <<< "$reports")
        fi
    fi

    write_result "$case_name" "$result_file" "$launch_rc" "$workdir" "$evidence" "$report_count"
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
