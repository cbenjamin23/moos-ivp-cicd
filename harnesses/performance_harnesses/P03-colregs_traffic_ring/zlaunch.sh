#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: P03-colregs_traffic_ring
#   Author: Charles Benjamin
#   LastEd: Jul 2026
#------------------------------------------------------------

set -u

ME=$(basename "$0")
HARNESS_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$HARNESS_DIR/../../.." && pwd)
MISSION_DIR="$REPO_DIR/missions/performance_missions/P03-colregs_traffic_ring"
TEARDOWN_HELPER="$REPO_DIR/scripts/moos_scoped_teardown.sh"
RESULTS_FILE="$HARNESS_DIR/results.txt"
WORK_ROOT="$HARNESS_DIR/workdirs"
PTRAFFIC_BIN="$REPO_DIR/bin/pTrafficManager"

ALL_CASES=(
    baseline_circle_pass
    mixed_speed_circle_pass
    endurance_circle_pass
    noncoop_circle_pass
)

CASE=""
PORT_BASE=9000
PORT_STRIDE=30
PSHARE_OFFSET=15
KEEP_WORKDIRS=no
VERBOSE=no
JUST_MAKE=no
LOG_MODE=minimal
DISPLAY_ARGS=(--nogui)
PERF_PROFILE="${PERF_PROFILE:-local}"
TIME_WARP=""
MAX_TIME_OVERRIDE=""
RUN_ROOT=""
RESULT_COUNT=0
FAILURES=0

usage() {
    cat <<EOF
$ME [OPTIONS] [time_warp]

Options:
  --help, -h         Show this help message
  --verbose, -v      Show case launch details
  --just_make, -j    Prepare each case without launching it
  --log=<mode>       Logging mode: minimal (default) or full
  --max_time=<secs>  Override each case's launcher ceiling
  --case=<name>      Run one named case
  --port_base=<n>    Base of the first isolated case port block
  --keep_workdirs    Preserve isolated mission copies
  --gui              Launch with pMarineViewer
  --nogui, -ng       Run headlessly (default)
  --profile=<name>   Timing profile: local or ci

Performance cases run serially. Concurrent jobs would invalidate their
wall-clock measurements.
EOF
}

die() {
    echo "$ME: $*" >&2
    exit 2
}

is_uint() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

for arg in "$@"; do
    case "$arg" in
        --help|-h) usage; exit 0 ;;
        --verbose|-v) VERBOSE=yes ;;
        --just_make|-j) JUST_MAKE=yes ;;
        --max_time=*) MAX_TIME_OVERRIDE="${arg#--max_time=}" ;;
        --log=*) LOG_MODE="${arg#--log=}" ;;
        --case=*) CASE="${arg#--case=}" ;;
        --port_base=*) PORT_BASE="${arg#--port_base=}" ;;
        --keep_workdirs) KEEP_WORKDIRS=yes ;;
        --gui) DISPLAY_ARGS=(--gui) ;;
        --nogui|-ng) DISPLAY_ARGS=(--nogui) ;;
        --profile=*) PERF_PROFILE="${arg#--profile=}" ;;
        *)
            is_uint "$arg" || die "bad argument: $arg"
            [ -z "$TIME_WARP" ] || die "time warp supplied more than once"
            TIME_WARP="$arg"
            ;;
    esac
done

case "$LOG_MODE" in
    minimal|full) ;;
    *) die "--log must be minimal or full" ;;
esac

is_uint "$PORT_BASE" || die "--port_base must be an integer"
if [ -n "$MAX_TIME_OVERRIDE" ]; then
    is_uint "$MAX_TIME_OVERRIDE" || die "--max_time must be an integer"
fi
case "$PERF_PROFILE" in
    local) [ -n "$TIME_WARP" ] || TIME_WARP=10 ;;
    ci) [ -n "$TIME_WARP" ] || TIME_WARP=5 ;;
    *) die "unknown performance profile: $PERF_PROFILE" ;;
esac
is_uint "$TIME_WARP" || die "time warp must be an integer"

[ -f "$TEARDOWN_HELPER" ] || die "missing scoped teardown helper: $TEARDOWN_HELPER"
[ -x "$PTRAFFIC_BIN" ] || die "missing pTrafficManager binary: $PTRAFFIC_BIN"
# shellcheck source=/dev/null
. "$TEARDOWN_HELPER"

stop_root() {
    moos_scoped_teardown_stop_root "$1"
}

cleanup() {
    local exit_rc=$?
    local teardown_ok=yes
    trap - EXIT
    trap '' INT TERM PIPE
    if [ -n "$RUN_ROOT" ] && [ -d "$RUN_ROOT" ]; then
        if ! stop_root "$RUN_ROOT"; then
            echo "$ME: scoped teardown failed; preserving $RUN_ROOT" >&2
            teardown_ok=no
            [ "$exit_rc" -ne 0 ] || exit_rc=1
        fi
        if [ "$KEEP_WORKDIRS" = no ] && [ "$teardown_ok" = yes ]; then
            rm -rf "$RUN_ROOT"
        fi
    fi
    exit "$exit_rc"
}

on_signal() {
    exit 130
}

trap cleanup EXIT
trap on_signal INT TERM PIPE

get_field() {
    local line="$1"
    local key="$2"
    local field
    for field in $line; do
        case "$field" in
            "$key"=*) printf '%s\n' "${field#*=}"; return 0 ;;
        esac
    done
    return 1
}

value_in_range() {
    local value="$1"
    local minimum="$2"
    local maximum="$3"
    awk -v value="$value" -v minimum="$minimum" -v maximum="$maximum" \
        'BEGIN { exit !((value + 0) >= (minimum + 0) && (value + 0) <= (maximum + 0)) }'
}

get_case_config() {
    local case_name="$1"

    CASE_SCENARIO=""
    SHORE_PATCH=""
    CASE_MAX_TIME=700
    WARNING_MAX=0

    case "$case_name" in
        baseline_circle_pass)
            CASE_SCENARIO=baseline_circle
            SHORE_PATCH="$HARNESS_DIR/baseline-circle-pass-shoreside.xmoos"
            if [ "$PERF_PROFILE" = ci ]; then
                WALL_MIN=58.0; WALL_MAX=70.0
            else
                WALL_MIN=30.0; WALL_MAX=32.0
            fi
            ;;
        mixed_speed_circle_pass)
            CASE_SCENARIO=mixed_speed_circle
            SHORE_PATCH="$HARNESS_DIR/mixed-speed-circle-pass-shoreside.xmoos"
            if [ "$PERF_PROFILE" = ci ]; then
                WALL_MIN=58.0; WALL_MAX=70.0
            else
                WALL_MIN=30.0; WALL_MAX=32.0
            fi
            ;;
        endurance_circle_pass)
            CASE_SCENARIO=endurance_circle
            SHORE_PATCH="$HARNESS_DIR/endurance-circle-pass-shoreside.xmoos"
            CASE_MAX_TIME=1400
            if [ "$PERF_PROFILE" = ci ]; then
                WALL_MIN=175.0; WALL_MAX=190.0
            else
                WALL_MIN=89.5; WALL_MAX=92.5
            fi
            ;;
        noncoop_circle_pass)
            CASE_SCENARIO=noncoop_circle
            SHORE_PATCH="$HARNESS_DIR/noncoop-circle-pass-shoreside.xmoos"
            if [ "$PERF_PROFILE" = ci ]; then
                WALL_MIN=58.0; WALL_MAX=70.0
            else
                WALL_MIN=30.0; WALL_MAX=32.0
            fi
            ;;
        *) return 1 ;;
    esac

    [ -f "$SHORE_PATCH" ] || return 1
    if [ -n "$MAX_TIME_OVERRIDE" ]; then
        CASE_MAX_TIME="$MAX_TIME_OVERRIDE"
    fi
}

prepare_case() {
    local case_dir="$1"
    local shore_stem
    mkdir "$case_dir" || return 1
    cp -R "$MISSION_DIR"/. "$case_dir"/ || return 1
    (
        cd "$case_dir" || exit 1
        ./clean.sh >/dev/null 2>&1 || true
        rm -f meta_shoreside.moosx meta_shoreside.full.moos \
            meta_vehicle.moosx meta_vehicle.bhvx
        shore_stem=meta_shoreside.moos
        if [ "$LOG_MODE" = full ]; then
            nspatch meta_shoreside.moos full-logging-shoreside.xmoos \
                meta_shoreside.full.moos || exit 1
            nspatch meta_vehicle.moos full-logging-vehicle.xmoos \
                meta_vehicle.moosx || exit 1
            shore_stem=meta_shoreside.full.moos
        fi
        nspatch "$shore_stem" "$SHORE_PATCH" \
            meta_shoreside.moosx
    )
}

read_mission_result() {
    local results_path="$1"
    local row_count
    local field

    MISSION_LINE=""
    MISSION_GRADE=""
    MISSION_EVIDENCE=""
    MISSION_GRADE_COUNT=0
    row_count=$(awk 'NF {count++} END {print count+0}' "$results_path" 2>/dev/null)
    [ "$row_count" -eq 1 ] || return 1
    MISSION_LINE=$(awk 'NF {print; exit}' "$results_path" 2>/dev/null)
    for field in $MISSION_LINE; do
        case "$field" in
            grade=*)
                MISSION_GRADE="${field#grade=}"
                MISSION_GRADE_COUNT=$((MISSION_GRADE_COUNT + 1))
                ;;
            *) MISSION_EVIDENCE="$MISSION_EVIDENCE $field" ;;
        esac
    done
    [ "$MISSION_GRADE_COUNT" -eq 1 ] || return 1
    [ "$MISSION_GRADE" = pass ] || [ "$MISSION_GRADE" = fail ]
}

scan_case_warnings() {
    local case_dir="$1"
    local alog_file
    local file_count=0
    local warning_count=0
    local count

    while IFS= read -r alog_file; do
        [ -n "$alog_file" ] || continue
        file_count=$((file_count + 1))
        count=$(aloggrep APP_LOG "$alog_file" 2>/dev/null | \
            grep -Eic 'BHV_ERROR|obstacle unavoidable|Obstacle Breached|Unable to init AOF_AvoidObstacleV24|Allstop' || true)
        warning_count=$((warning_count + count))
    done < <(find "$case_dir" -maxdepth 2 -type f -path '*/LOG_*/*.alog' \
        ! -path '*/LOG_SHORESIDE*/*' | sort)

    [ "$file_count" -gt 0 ] || { echo missing; return 0; }
    echo "$warning_count"
}

evaluate_performance() {
    local case_dir="$1"
    local wall_time
    local warning_count
    local notes=""

    wall_time=$(get_field "$MISSION_LINE" wall_time 2>/dev/null || true)
    warning_count=$(scan_case_warnings "$case_dir")
    PERF_WARNING_COUNT="$warning_count"
    if [ -z "$wall_time" ]; then
        PERF_STATUS=error
        PERF_NOTES=missing_metrics
        return
    fi
    value_in_range "$wall_time" "$WALL_MIN" "$WALL_MAX" || notes=wall_time
    if [ "$warning_count" = missing ]; then
        notes="${notes:+$notes,}missing_logs"
    elif ! value_in_range "$warning_count" 0 "$WARNING_MAX"; then
        notes="${notes:+$notes,}warnings"
    fi
    if [ -n "$notes" ]; then
        PERF_STATUS=mismatch
        PERF_NOTES="$notes"
    else
        PERF_STATUS=ok
        PERF_NOTES=none
    fi
}

write_runner_failure() {
    local case_name="$1"
    local reason="$2"
    shift 2
    printf 'case=%s grade=fail reason=%s' "$case_name" "$reason" >> "$RESULTS_FILE"
    [ "$#" -eq 0 ] || printf ' %s' "$*" >> "$RESULTS_FILE"
    printf '\n' >> "$RESULTS_FILE"
    RESULT_COUNT=$((RESULT_COUNT + 1))
    FAILURES=$((FAILURES + 1))
}

write_case_result() {
    local case_name="$1"
    local launch_rc="$2"
    local teardown_rc="$3"
    local final_grade="$MISSION_GRADE"

    if [ "$launch_rc" -ne 0 ]; then
        write_runner_failure "$case_name" launch_error \
            "launch_rc=$launch_rc mission_grade=$MISSION_GRADE$MISSION_EVIDENCE perf_status=$PERF_STATUS perf_notes=$PERF_NOTES warning_count=$PERF_WARNING_COUNT"
        return
    fi
    if [ "$teardown_rc" -ne 0 ]; then
        write_runner_failure "$case_name" teardown_error \
            "mission_grade=$MISSION_GRADE$MISSION_EVIDENCE perf_status=$PERF_STATUS perf_notes=$PERF_NOTES warning_count=$PERF_WARNING_COUNT"
        return
    fi
    [ "$PERF_STATUS" = ok ] || final_grade=fail
    printf 'case=%s grade=%s mission_grade=%s%s perf_status=%s perf_notes=%s warning_count=%s\n' \
        "$case_name" "$final_grade" "$MISSION_GRADE" "$MISSION_EVIDENCE" \
        "$PERF_STATUS" "$PERF_NOTES" "$PERF_WARNING_COUNT" >> "$RESULTS_FILE"
    RESULT_COUNT=$((RESULT_COUNT + 1))
    [ "$final_grade" = pass ] || FAILURES=$((FAILURES + 1))
}

run_case() {
    local case_idx="$1"
    local case_name="$2"
    local case_tag
    local case_dir
    local case_base
    local launch_rc=0
    local teardown_rc=0
    local launch_args

    get_case_config "$case_name" || {
        write_runner_failure "$case_name" prepare_error "detail=unknown_case_or_missing_patch"
        return
    }
    case_tag=$(printf '%03d_%s' "$case_idx" "$case_name")
    case_dir="$RUN_ROOT/$case_tag"
    prepare_case "$case_dir" || {
        write_runner_failure "$case_name" prepare_error
        return
    }

    case_base=$((PORT_BASE + case_idx * PORT_STRIDE))
    launch_args=(
        --scenario="$CASE_SCENARIO"
        --max_time="$CASE_MAX_TIME"
        --shore_mport="$case_base"
        --veh_mport="$((case_base + 1))"
        --shore_pshare="$((case_base + PSHARE_OFFSET))"
        --veh_pshare="$((case_base + PSHARE_OFFSET + 1))"
        "$TIME_WARP"
    )
    if [ "${#DISPLAY_ARGS[@]}" -gt 0 ]; then
        launch_args+=("${DISPLAY_ARGS[@]}")
    fi
    [ "$JUST_MAKE" = yes ] && launch_args+=(--just_make)

    [ "$VERBOSE" = yes ] && \
        echo "$ME: case=$case_name scenario=$CASE_SCENARIO ports=$case_base-$((case_base + PORT_STRIDE - 1))"
    (
        cd "$case_dir" || exit 1
        LOG_MODE_PREPARED=yes LOG_MODE_PREPARED_VALUE="$LOG_MODE" \
            PTRAFFIC_BIN="$PTRAFFIC_BIN" \
            ./zlaunch.sh --log="$LOG_MODE" "${launch_args[@]}"
    ) || launch_rc=$?

    if [ "$JUST_MAKE" = yes ]; then
        if [ "$launch_rc" -eq 0 ]; then
            printf 'case=%s grade=pass mode=just_make\n' "$case_name" >> "$RESULTS_FILE"
            RESULT_COUNT=$((RESULT_COUNT + 1))
        else
            write_runner_failure "$case_name" launch_error "launch_rc=$launch_rc mode=just_make"
        fi
        return
    fi

    if ! read_mission_result "$case_dir/results.txt"; then
        stop_root "$case_dir" || teardown_rc=$?
        if [ "$teardown_rc" -ne 0 ]; then
            write_runner_failure "$case_name" teardown_error
        else
            write_runner_failure "$case_name" missing_result "launch_rc=$launch_rc"
        fi
        return
    fi

    evaluate_performance "$case_dir"
    stop_root "$case_dir" || teardown_rc=$?
    write_case_result "$case_name" "$launch_rc" "$teardown_rc"
}

RUN_CASES=("${ALL_CASES[@]}")
if [ -n "$CASE" ]; then
    get_case_config "$CASE" || die "unknown case or missing case patch: $CASE"
    RUN_CASES=("$CASE")
fi
if [ "${DISPLAY_ARGS[0]}" = --gui ] && [ "${#RUN_CASES[@]}" -ne 1 ]; then
    die "--gui requires one explicit --case"
fi

highest_port=$((PORT_BASE + (${#RUN_CASES[@]} - 1) * PORT_STRIDE + PSHARE_OFFSET + 5))
[ "$PORT_BASE" -ge 1 ] && [ "$highest_port" -le 65535 ] || \
    die "selected port blocks exceed the valid TCP/UDP range"

mkdir -p "$WORK_ROOT"
RUN_ROOT=$(mktemp -d "$WORK_ROOT/run_XXXXXX") || die "unable to create run root"
: > "$RESULTS_FILE"

case_idx=0
for case_name in "${RUN_CASES[@]}"; do
    run_case "$case_idx" "$case_name"
    case_idx=$((case_idx + 1))
done

if [ "${#RUN_CASES[@]}" -gt 0 ] && [ "$RESULT_COUNT" -eq 0 ]; then
    echo "$ME: selected cases produced zero result rows" >&2
    FAILURES=$((FAILURES + 1))
fi
if [ "$RESULT_COUNT" -ne "${#RUN_CASES[@]}" ]; then
    echo "$ME: expected ${#RUN_CASES[@]} result rows but wrote $RESULT_COUNT" >&2
    FAILURES=$((FAILURES + 1))
fi

cat "$RESULTS_FILE"
[ "$FAILURES" -eq 0 ]
