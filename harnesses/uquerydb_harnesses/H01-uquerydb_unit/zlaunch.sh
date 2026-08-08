#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H01-uquerydb_unit
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
MISSION_DIR="$REPO_DIR/missions/uquerydb_missions/uquerydb_unit"
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
    cli_numeric_pass
    cli_string_pass
    cli_boolean_pass
    cli_negative_numeric_pass
    multiple_pass_conditions_pass
    multiple_second_false_fail
    fail_condition_false_pass
    fail_condition_true_fail
    missing_var_timeout_fail
    late_var_wait_pass
    mission_file_config_pass
    checkvar_esv_pass
    checkvar_csv_pass
    checkvar_wsv_pass
    checkvar_value_only_pass
    unique_name_pass
    compound_or_pass
    pass_condition_alias_pass
    compound_and_pass
    compound_and_second_false_fail
    compound_or_fail
    config_halt_max_time_timeout_fail
    config_fail_condition_false_pass
    config_fail_condition_true_fail
    checkvar_multi_csv_pass
    checkvar_timeout_esv_pass
    case_config_checkvar_csv_pass
    fail_only_false_pass
    fail_only_true_fail
    numeric_greater_than_pass
    numeric_less_than_fail
    config_condition_alias_pass
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
    cat <<EOF

Examples:
  ./$ME
  ./$ME --log=full
  ./$ME --case=cli_numeric_pass
  ./$ME --jobs=2 --port_base=22000
  ./$ME --just_make --case=mission_file_config_pass
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

is_uint "$TIME_WARP" && [ "${#TIME_WARP}" -le 9 ] || die "time warp must be a bounded positive integer"
is_uint "$JOBS" && [ "${#JOBS}" -le 9 ] || die "--jobs must be a bounded positive integer"
is_uint "$PORT_BASE" && [ "${#PORT_BASE}" -le 5 ] || die "--port_base must be an integer from 1 through 65535"
is_uint "$MAX_TIME" && [ "${#MAX_TIME}" -le 9 ] || die "--max_time must be a bounded positive integer"
case "$LOG_MODE" in
    minimal|full) ;;
    *) die "--log must be minimal or full" ;;
esac

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

case_known() {
    local wanted="$1"
    local case_name
    for case_name in "${CASES[@]}"; do
        [ "$case_name" = "$wanted" ] && return 0
    done
    return 1
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
    local compound_condition
    EXPECTED_RC="0"
    QUERY_FILE_MODE="connect"
    QUERY_ARGS=()
    CONFIG_LINES=()
    EXPECTED_CHECKVARS=()
    CHECKVARS_REGEXES=()
    MIN_ELAPSED_MS=0
    # Zero disables a case-specific wall-clock maximum. run_querydb's hard
    # deadline remains the infrastructure upper bound for every case.
    MAX_ELAPSED_MS=0

    if ! case_known "$CASE_NAME"; then
        echo "$ME: Unknown case: $CASE_NAME"
        return 1
    fi

    case "$CASE_NAME" in
        cli_numeric_pass)
            QUERY_ARGS=("--condition=QUERY_NUM = 42" "--wait=3")
            ;;
        cli_string_pass)
            QUERY_ARGS=("--condition=QUERY_STR = ready" "--wait=3")
            ;;
        cli_boolean_pass)
            QUERY_ARGS=("--condition=QUERY_BOOL = true" "--wait=3")
            ;;
        cli_negative_numeric_pass)
            QUERY_ARGS=("--condition=QUERY_NEG = -7.5" "--wait=3")
            ;;
        multiple_pass_conditions_pass)
            QUERY_ARGS=("--condition=QUERY_NUM = 42" "--condition=QUERY_STR = ready" "--wait=3")
            ;;
        multiple_second_false_fail)
            EXPECTED_RC="1"
            QUERY_ARGS=("--condition=QUERY_NUM = 42" "--condition=QUERY_STR = not_ready" "--wait=1")
            ;;
        fail_condition_false_pass)
            QUERY_ARGS=("--condition=QUERY_NUM = 42" "--fail_condition=QUERY_FAIL = true" "--wait=3")
            ;;
        fail_condition_true_fail)
            EXPECTED_RC="1"
            QUERY_ARGS=("--condition=QUERY_NUM = 42" "--fail_condition=QUERY_FAIL = false" "--wait=3")
            ;;
        missing_var_timeout_fail)
            EXPECTED_RC="1"
            QUERY_ARGS=("--condition=QUERY_MISSING = ready" "--wait=1")
            MIN_ELAPSED_MS=1500
            ;;
        late_var_wait_pass)
            QUERY_ARGS=("--condition=QUERY_LATE = arrived" "--wait=3")
            MIN_ELAPSED_MS=1500
            ;;
        mission_file_config_pass)
            QUERY_FILE_MODE="mission_config"
            QUERY_ARGS=()
            EXPECTED_CHECKVARS=(" QUERY_NUM=42")
            ;;
        checkvar_esv_pass)
            QUERY_ARGS=("--condition=QUERY_NUM = 42" "--check_var=QUERY_NUM" "--esv" "--wait=3")
            EXPECTED_CHECKVARS=(" QUERY_NUM=42")
            ;;
        checkvar_csv_pass)
            QUERY_ARGS=("--condition=QUERY_STR = ready" "--check_var=QUERY_STR" "--csv" "--wait=3")
            EXPECTED_CHECKVARS=("QUERY_STR,ready")
            ;;
        checkvar_wsv_pass)
            QUERY_ARGS=("--condition=QUERY_OTHER = bravo" "--check_var=QUERY_OTHER" "--wsv" "--wait=3")
            EXPECTED_CHECKVARS=("QUERY_OTHER bravo")
            ;;
        checkvar_value_only_pass)
            QUERY_FILE_MODE="case_config"
            CONFIG_LINES=("pass_condition = QUERY_BOOL = true" "check_var = QUERY_BOOL" "check_var_format = vo" "wait = 3")
            EXPECTED_CHECKVARS=("true")
            ;;
        unique_name_pass)
            QUERY_ARGS=("--unique" "--condition=QUERY_LATE = arrived" "--check_var=DB_CLIENTS" "--esv" "--wait=3")
            CHECKVARS_REGEXES=('unique_name::^ DB_CLIENTS=.*uQueryDB_[0-9]+,')
            ;;
        compound_or_pass)
            compound_condition="--condition=(QUERY_STR = not_ready) or (QUERY_OTHER = bravo)"
            QUERY_ARGS=("$compound_condition" "--wait=3")
            ;;
        pass_condition_alias_pass)
            QUERY_ARGS=("--pass_condition=QUERY_STR = ready" "--wait=3")
            ;;
        compound_and_pass)
            compound_condition="--condition=(QUERY_NUM = 42) and (QUERY_STR = ready)"
            QUERY_ARGS=("$compound_condition" "--wait=3")
            ;;
        compound_and_second_false_fail)
            EXPECTED_RC="1"
            compound_condition="--condition=(QUERY_NUM = 42) and (QUERY_STR = not_ready)"
            QUERY_ARGS=("$compound_condition" "--wait=1")
            ;;
        compound_or_fail)
            EXPECTED_RC="1"
            compound_condition="--condition=(QUERY_STR = not_ready) or (QUERY_OTHER = not_bravo)"
            QUERY_ARGS=("$compound_condition" "--wait=1")
            ;;
        config_halt_max_time_timeout_fail)
            EXPECTED_RC="1"
            QUERY_FILE_MODE="case_config"
            CONFIG_LINES=("halt_max_time = 1" "pass_condition = QUERY_MISSING = ready")
            MIN_ELAPSED_MS=1500
            ;;
        config_fail_condition_false_pass)
            QUERY_FILE_MODE="case_config"
            CONFIG_LINES=("wait = 3" "pass_condition = QUERY_NUM = 42" "fail_condition = QUERY_FAIL = true")
            ;;
        config_fail_condition_true_fail)
            EXPECTED_RC="1"
            QUERY_FILE_MODE="case_config"
            CONFIG_LINES=("wait = 3" "pass_condition = QUERY_NUM = 42" "fail_condition = QUERY_FAIL = false")
            ;;
        checkvar_multi_csv_pass)
            QUERY_ARGS=("--condition=QUERY_NUM = 42" "--check_var=QUERY_NUM" "--check_var=QUERY_STR" "--csv" "--wait=3")
            EXPECTED_CHECKVARS=("QUERY_NUM,42" "QUERY_STR,ready")
            ;;
        checkvar_timeout_esv_pass)
            EXPECTED_RC="1"
            QUERY_ARGS=("--condition=QUERY_MISSING = ready" "--check_var=QUERY_NUM" "--esv" "--wait=1")
            EXPECTED_CHECKVARS=(" QUERY_NUM=42")
            ;;
        case_config_checkvar_csv_pass)
            QUERY_FILE_MODE="case_config"
            CONFIG_LINES=("wait = 3" "pass_condition = QUERY_OTHER = bravo" "check_var = QUERY_OTHER" "check_var_format = csv")
            EXPECTED_CHECKVARS=("QUERY_OTHER,bravo")
            ;;
        fail_only_false_pass)
            QUERY_ARGS=("--fail_condition=QUERY_FAIL = true" "--wait=3")
            ;;
        fail_only_true_fail)
            EXPECTED_RC="1"
            QUERY_ARGS=("--fail_condition=QUERY_FAIL = false" "--wait=3")
            ;;
        numeric_greater_than_pass)
            QUERY_ARGS=("--condition=QUERY_NUM > 41" "--wait=3")
            ;;
        numeric_less_than_fail)
            EXPECTED_RC="1"
            QUERY_ARGS=("--condition=QUERY_NUM < 41" "--wait=1")
            ;;
        config_condition_alias_pass)
            QUERY_FILE_MODE="case_config"
            CONFIG_LINES=("wait = 3" "condition = QUERY_BOOL = true")
            ;;
    esac
}

run_querydb() {
    local case_dir="$1"
    local port="$2"
    local output="$case_dir/querydb.out"
    local connect_file="$case_dir/query_connect.moos"
    local config_file="$case_dir/query_config.moos"
    local query_pid
    local deadline
    local line
    local stop_attempt
    local cmd=()
    local query_rc
    local started_at="$EPOCHREALTIME"

    if [ "$QUERY_FILE_MODE" = "mission_config" ]; then
        cmd=("uQueryDB" "$case_dir/targ_shoreside.moos" "${QUERY_ARGS[@]}")
    elif [ "$QUERY_FILE_MODE" = "case_config" ]; then
        {
            echo "ServerHost = localhost"
            echo "ServerPort = $port"
            echo "Community  = query"
            echo ""
            echo "ProcessConfig = uQueryDB"
            echo "{"
            echo "  AppTick   = 4"
            echo "  CommsTick = 4"
            for line in "${CONFIG_LINES[@]}"; do
                echo "  $line"
            done
            echo "}"
        } > "$config_file"
        cmd=("uQueryDB" "$config_file" "${QUERY_ARGS[@]}")
    else
        {
            echo "ServerHost = localhost"
            echo "ServerPort = $port"
            echo "Community  = query"
        } > "$connect_file"
        cmd=("uQueryDB" "$connect_file" "${QUERY_ARGS[@]}")
    fi

    (
        cd "$case_dir" || exit 1
        "${cmd[@]}" > "$output" 2>&1 &
        query_pid=$!
        deadline=$((SECONDS + 8))
        while kill -0 "$query_pid" 2>/dev/null; do
            if [ "$SECONDS" -ge "$deadline" ]; then
                kill -TERM "$query_pid" 2>/dev/null || true
                for ((stop_attempt = 0; stop_attempt < 20; stop_attempt++)); do
                    kill -0 "$query_pid" 2>/dev/null || break
                    sleep 0.1
                done
                if kill -0 "$query_pid" 2>/dev/null; then
                    kill -KILL "$query_pid" 2>/dev/null || true
                fi
                wait "$query_pid" 2>/dev/null || true
                exit 124
            fi
            sleep 0.1
        done
        wait "$query_pid"
    )
    query_rc=$?
    QUERY_ELAPSED_MS=$(awk -v started="$started_at" -v finished="$EPOCHREALTIME" \
        'BEGIN {printf "%d", (finished - started) * 1000}')
    return "$query_rc"
}

wait_for_nonempty_file() {
    local path="$1"
    local attempt

    for ((attempt=0; attempt<30; attempt++)); do
        [ -s "$path" ] && return 0
        sleep 0.1
    done
    return 1
}

check_checkvars() {
    local workdir="$1"
    local check_file="$workdir/.checkvars"
    local regex_spec
    local regex_name
    local regex
    local index
    local -a actual_lines=()
    CHECKVARS_DETAIL=""

    if [ "${#EXPECTED_CHECKVARS[@]}" -eq 0 ] &&
       [ "${#CHECKVARS_REGEXES[@]}" -eq 0 ]; then
        return 0
    fi
    if [ ! -f "$check_file" ]; then
        CHECKVARS_DETAIL=missing_file
        return 1
    fi

    mapfile -t actual_lines < "$check_file"
    if [ "${#EXPECTED_CHECKVARS[@]}" -gt 0 ]; then
        if [ "${#actual_lines[@]}" -ne "${#EXPECTED_CHECKVARS[@]}" ]; then
            CHECKVARS_DETAIL="line_count_${#actual_lines[@]}_expected_${#EXPECTED_CHECKVARS[@]}"
            return 1
        fi
        for ((index=0; index<${#EXPECTED_CHECKVARS[@]}; index++)); do
            if [ "${actual_lines[$index]}" != "${EXPECTED_CHECKVARS[$index]}" ]; then
                CHECKVARS_DETAIL="line_$((index + 1))_mismatch"
                return 1
            fi
        done
    fi

    for regex_spec in "${CHECKVARS_REGEXES[@]}"; do
        regex_name=${regex_spec%%::*}
        regex=${regex_spec#*::}
        if ! grep -Eq -- "$regex" "$check_file"; then
            CHECKVARS_DETAIL="regex_$regex_name"
            return 1
        fi
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
    get_case_config "$case_name"
}

write_result() {
    local case_name="$1"
    local result_file="$2"
    local launch_rc="$3"
    local query_rc="$4"
    local completion_rc="$5"
    local workdir="$6"
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
        printf 'case=%s grade=fail reason=missing_result_file launch_rc=%s actual_rc=%s completion_rc=%s\n' \
            "$case_name" "$launch_rc" "$query_rc" "$completion_rc" > "$result_file"
        return 0
    fi
    mission_rows=$(awk 'NF {count++} END {print count+0}' "$workdir/results.txt")
    if [ "$mission_rows" -eq 0 ]; then
        printf 'case=%s grade=fail reason=missing_result launch_rc=%s actual_rc=%s completion_rc=%s\n' \
            "$case_name" "$launch_rc" "$query_rc" "$completion_rc" > "$result_file"
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

    if [ "$completion_rc" -ne 0 ]; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=completion_error completion_rc=%s%s\n' \
            "$case_name" "$completion_rc" "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi
    if [ "$launch_rc" -ne 0 ]; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=launch_error launch_rc=%s%s\n' \
            "$case_name" "$launch_rc" "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi

    if [ "$mission_grade" = pass ] && [ "$query_rc" -ne "$EXPECTED_RC" ]; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=subject_result_mismatch expected_rc=%s actual_rc=%s%s\n' \
            "$case_name" "$EXPECTED_RC" "$query_rc" "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi
    if [ "$mission_grade" = pass ] && [ "$MIN_ELAPSED_MS" -gt 0 ] &&
       { [ "$QUERY_ELAPSED_MS" -lt "$MIN_ELAPSED_MS" ] ||
         { [ "$MAX_ELAPSED_MS" -gt 0 ] &&
           [ "$QUERY_ELAPSED_MS" -gt "$MAX_ELAPSED_MS" ]; }; }; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=subject_timing_mismatch elapsed_ms=%s min_elapsed_ms=%s max_elapsed_ms=%s%s\n' \
            "$case_name" "$QUERY_ELAPSED_MS" "$MIN_ELAPSED_MS" "$MAX_ELAPSED_MS" \
            "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi
    if [ "$mission_grade" = pass ] && ! check_checkvars "$workdir"; then
        provenance=$(runner_provenance "$line")
        printf 'case=%s grade=fail reason=checkvars_mismatch detail=%s expected_rc=%s actual_rc=%s%s\n' \
            "$case_name" "${CHECKVARS_DETAIL:-unknown}" \
            "$EXPECTED_RC" "$query_rc" "${provenance:+ $provenance}" > "$result_file"
        return 0
    fi

    line=$(without_case_field "$line")
    printf 'case=%s %s expected_rc=%s actual_rc=%s elapsed_ms=%s readiness=%s checkvars=%s checkvars_regexes=%s\n' \
        "$case_name" "$line" "$EXPECTED_RC" "$query_rc" "$QUERY_ELAPSED_MS" \
        "$mission_grade" "${#EXPECTED_CHECKVARS[@]}" \
        "${#CHECKVARS_REGEXES[@]}" > "$result_file"
}

run_case() {
    local case_name="$1"
    local workdir="$2"
    local result_file="$3"
    local case_base="$4"
    local launch_rc=0
    local query_rc=0
    local completion_rc=0
    local stem_pid=0
    local launch_args
    local result_line
    local grade
    QUERY_ELAPSED_MS=0

    prepare_case "$case_name" "$workdir" || {
        printf 'case=%s grade=fail reason=prepare_error\n' "$case_name" > "$result_file"
        return 1
    }

    if [ "$JUST_MAKE" = yes ]; then
        (
            cd "$workdir" || exit 1
            launch_args=(
                --just_make
                --mmod="$case_name"
                --max_time="$MAX_TIME"
                "${DISPLAY_ARGS[@]}"
                --shore_mport="$((case_base + 0))"
                --shore_pshare="$((case_base + PSHARE_OFFSET))"
                "$TIME_WARP"
            )
            ./zlaunch.sh --log="$LOG_MODE" "${launch_args[@]}"
        ) || launch_rc=$?
    else
        (
            cd "$workdir" || exit 1
            : > results.txt
            launch_args=(
                --external_client
                --mmod="$case_name"
                --max_time="$MAX_TIME"
                "${DISPLAY_ARGS[@]}"
                --shore_mport="$((case_base + 0))"
                --shore_pshare="$((case_base + PSHARE_OFFSET))"
                "$TIME_WARP"
            )
            ./zlaunch.sh --log="$LOG_MODE" "${launch_args[@]}"
        ) &
        stem_pid=$!
        sleep 0.75
        if [ "$QUERY_FILE_MODE" = "mission_config" ] &&
           ! wait_for_nonempty_file "$workdir/targ_shoreside.moos"; then
            query_rc=125
        else
            run_querydb "$workdir" "$((case_base + 0))" || query_rc=$?
        fi
        if [ "$query_rc" -eq 124 ]; then
            completion_rc=124
        else
            uPokeDB --quiet --host=localhost --port="$((case_base + 0))" \
                TEST_EVAL_READY=true > "$workdir/readiness.out" 2>&1 || completion_rc=$?
        fi
        wait "$stem_pid" || launch_rc=$?
    fi

    write_result "$case_name" "$result_file" "$launch_rc" "$query_rc" \
        "$completion_rc" "$workdir"
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
    kept_root=none
fi
if [ "$CLEANUP_FAILED" = yes ]; then
    FINAL_FAILURES=$((FINAL_FAILURES + 1))
fi
trap - EXIT INT TERM PIPE

printf 'results=%s failures=%s total=%s jobs=%s log_mode=%s elapsed_seconds=%s bash=%s workdirs=%s\n' \
    "$RESULTS_FILE" "$FINAL_FAILURES" "$total" "$JOBS" "$LOG_MODE" "$elapsed_seconds" "$BASH_VERSION" "$kept_root"

[ "$FINAL_FAILURES" -eq 0 ]
