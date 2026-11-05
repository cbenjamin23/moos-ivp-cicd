#!/usr/bin/env bash
#------------------------------------------------------------
#   Script: zlaunch.sh
#  Harness: H01-legrun_behavior_motion
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
MISSION_DIR="$REPO_DIR/missions/legrun_behavior_missions/legrun_behavior_motion"
TEARDOWN_HELPER="$REPO_DIR/scripts/moos_scoped_teardown.sh"
RESULTS_FILE="$HARNESS_DIR/results.txt"
RUNS_DIR="$HARNESS_DIR/.harness_runs"
RUN_ROOT=""

TIME_WARP=10
MAX_TIME=200
JOBS=1
PORT_BASE=15400
PORT_STRIDE=30
PSHARE_OFFSET=10
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
    baseline_cycle_pass
    finite_complete_pass
    colon_leg_format_pass
    vertex_points_pass
    init_close_turn_pass
    init_far_turn_pass
    turn_rad_alias_pass
    turn_bias_ext_gap_pass
    individual_turn_params_pass
    turn_rad_min_clip_pass
    capture_radius_alias_pass
    capture_line_absolute_pass
    no_capture_line_pass
    leg_speed_schedule_pass
    leg_speed_onturn_pass
    leg_speed_count_repeat_pass
    runtime_length_angle_update_pass
    runtime_turn_radius_update_pass
    runtime_speed_replace_reset_pass
    runtime_shift_point_pass
    runtime_turn_bias_ext_update_pass
    flag_aliases_pass
    mid_pct_late_pass
    patience_clip_pass
    bad_leg_config_fail
    bad_speed_schedule_fail
    bad_init_mode_fail
    bad_mid_pct_fail
    bad_turn_radius_fail
    bad_turn_ext_fail
    bad_turn_dir_fail
    bad_speed_high_fail
    bad_speed_count_fail
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
  --port_stride=<n>  Port spacing between case blocks (minimum 12)
  --keep_workdirs    Keep this invocation's isolated case directories
  --gui              Launch with pMarineViewer
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
  ./$ME --case=baseline_cycle_pass
  ./$ME --jobs=4 --port_base=15000 --port_stride=12
  ./$ME --just_make --case=bad_leg_config_fail
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
        --port_stride=*) PORT_STRIDE="${arg#--port_stride=}" ;;
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
is_uint "$PORT_STRIDE" && [ "${#PORT_STRIDE}" -le 5 ] || die "--port_stride must be a bounded integer of at least 12"
is_uint "$MAX_TIME" && [ "${#MAX_TIME}" -le 9 ] || die "--max_time must be a bounded positive integer"

TIME_WARP=$((10#$TIME_WARP))
JOBS=$((10#$JOBS))
PORT_BASE=$((10#$PORT_BASE))
PORT_STRIDE=$((10#$PORT_STRIDE))
MAX_TIME=$((10#$MAX_TIME))

[ "$TIME_WARP" -gt 0 ] || die "time warp must be a positive integer"
[ "$JOBS" -gt 0 ] || die "--jobs must be a positive integer"
[ "$PORT_BASE" -gt 0 ] && [ "$PORT_BASE" -le 65535 ] || die "--port_base must be an integer from 1 through 65535"
[ "$PORT_STRIDE" -ge 12 ] || die "--port_stride must be at least 12"
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
    CASE_SHORE_PATCH=""
    CASE_VEH_MOOS_PATCH=""
    CASE_VEH_MOOS_FULL_PATCH=""
    CASE_VEH_BHV_PATCH=""

    if [ "$CASE_NAME" = "baseline_cycle_pass" ]; then
        :
    elif [ "$CASE_NAME" = "finite_complete_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/finite-complete-pass-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/finite-complete-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "colon_leg_format_pass" ]; then
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/colon-leg-format-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "vertex_points_pass" ]; then
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/vertex-points-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "init_close_turn_pass" ]; then
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/init-close-turn-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "init_far_turn_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/init-far-turn-pass-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/init-far-turn-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "turn_rad_alias_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/turn-rad-alias-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/turn-preview-sample-vehicle.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/turn-rad-alias-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "turn_bias_ext_gap_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/turn-bias-ext-gap-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/turn-preview-sample-vehicle.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/turn-bias-ext-gap-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "individual_turn_params_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/individual-turn-params-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/turn-preview-sample-vehicle.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/individual-turn-params-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "turn_rad_min_clip_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/turn-rad-min-clip-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/turn-preview-sample-vehicle.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/turn-rad-min-clip-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "capture_radius_alias_pass" ]; then
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/capture-radius-alias-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "capture_line_absolute_pass" ]; then
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/capture-line-absolute-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "no_capture_line_pass" ]; then
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/no-capture-line-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "leg_speed_schedule_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/leg-speed-schedule-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/leg-speed-sequence-pass-vehicle.xmoos"
        CASE_VEH_MOOS_FULL_PATCH="$HARNESS_DIR/leg-speed-sequence-pass-full-logging-vehicle.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/leg-speed-schedule-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "leg_speed_onturn_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/leg-speed-onturn-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/leg-speed-sequence-pass-vehicle.xmoos"
        CASE_VEH_MOOS_FULL_PATCH="$HARNESS_DIR/leg-speed-sequence-pass-full-logging-vehicle.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/leg-speed-onturn-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "leg_speed_count_repeat_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/leg-speed-count-repeat-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/leg-speed-sequence-pass-vehicle.xmoos"
        CASE_VEH_MOOS_FULL_PATCH="$HARNESS_DIR/leg-speed-sequence-pass-full-logging-vehicle.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/leg-speed-count-repeat-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "runtime_length_angle_update_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/runtime-length-angle-update-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/runtime-length-angle-update-pass-vehicle.xmoos"
    elif [ "$CASE_NAME" = "runtime_turn_radius_update_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/runtime-turn-radius-update-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/runtime-turn-radius-update-pass-vehicle.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/runtime-compact-leg-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "runtime_speed_replace_reset_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/runtime-speed-replace-reset-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/runtime-speed-replace-reset-pass-vehicle.xmoos"
        CASE_VEH_MOOS_FULL_PATCH="$HARNESS_DIR/runtime-speed-replace-reset-pass-full-logging-vehicle.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/runtime-speed-replace-reset-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "runtime_shift_point_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/runtime-shift-point-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/runtime-shift-point-pass-vehicle.xmoos"
    elif [ "$CASE_NAME" = "runtime_turn_bias_ext_update_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/runtime-turn-bias-ext-update-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/runtime-turn-bias-ext-update-pass-vehicle.xmoos"
    elif [ "$CASE_NAME" = "flag_aliases_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/flag-aliases-pass-shoreside.xmoos"
        CASE_VEH_MOOS_PATCH="$HARNESS_DIR/flag-aliases-pass-vehicle.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/flag-aliases-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "mid_pct_late_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/mid-pct-late-pass-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/mid-pct-late-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "patience_clip_pass" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/patience-clip-pass-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/patience-clip-pass-vehicle.xbhv"
    elif [ "$CASE_NAME" = "bad_leg_config_fail" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/eval-malconfig-fail-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-leg-config-fail-vehicle.xbhv"
    elif [ "$CASE_NAME" = "bad_speed_schedule_fail" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/eval-malconfig-fail-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-speed-schedule-fail-vehicle.xbhv"
    elif [ "$CASE_NAME" = "bad_init_mode_fail" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/eval-malconfig-fail-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-init-mode-fail-vehicle.xbhv"
    elif [ "$CASE_NAME" = "bad_mid_pct_fail" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/eval-malconfig-fail-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-mid-pct-fail-vehicle.xbhv"
    elif [ "$CASE_NAME" = "bad_turn_radius_fail" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/eval-malconfig-fail-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-turn-radius-fail-vehicle.xbhv"
    elif [ "$CASE_NAME" = "bad_turn_ext_fail" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/eval-malconfig-fail-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-turn-ext-fail-vehicle.xbhv"
    elif [ "$CASE_NAME" = "bad_turn_dir_fail" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/eval-malconfig-fail-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-turn-dir-fail-vehicle.xbhv"
    elif [ "$CASE_NAME" = "bad_speed_high_fail" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/eval-malconfig-fail-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-speed-high-fail-vehicle.xbhv"
    elif [ "$CASE_NAME" = "bad_speed_count_fail" ]; then
        CASE_SHORE_PATCH="$HARNESS_DIR/eval-malconfig-fail-shoreside.xmoos"
        CASE_VEH_BHV_PATCH="$HARNESS_DIR/bad-speed-count-fail-vehicle.xbhv"
    else
        echo "$ME: Unknown case: [$CASE_NAME]"
        return 1
    fi
    return 0
}

apply_case_patches() {
    clear_xfiles

    if [ "$CASE_SHORE_PATCH" != "" ]; then
        nspatch "$SHORE_STEM" "$CASE_SHORE_PATCH" "$SHORE_XFILE"
    fi

    if [ "$LOG_MODE" = full ] && [ "$CASE_VEH_MOOS_FULL_PATCH" != "" ]; then
        nspatch "$VEHICLE_MOOS_STEM" "$CASE_VEH_MOOS_FULL_PATCH" "$VEHICLE_MOOS_XFILE"
    elif [ "$CASE_VEH_MOOS_PATCH" != "" ]; then
        nspatch "$VEHICLE_MOOS_STEM" "$CASE_VEH_MOOS_PATCH" "$VEHICLE_MOOS_XFILE"
    fi

    if [ "$CASE_VEH_BHV_PATCH" != "" ]; then
        nspatch "$VEHICLE_BHV_STEM" "$CASE_VEH_BHV_PATCH" "$VEHICLE_BHV_XFILE"
    fi
}

apply_case_overlays() {
    local case_name="$1"
    local workdir="$2"
    local patch
    local -a shore_patches=()
    local -a vehicle_patches=()

    get_case_config "$case_name" || return 1

    if [ "$LOG_MODE" = full ]; then
        shore_patches+=("$workdir/full-logging-shoreside.xmoos")
        if [ -n "$CASE_VEH_MOOS_FULL_PATCH" ]; then
            vehicle_patches+=("$CASE_VEH_MOOS_FULL_PATCH")
        else
            vehicle_patches+=("$workdir/full-logging-vehicle.xmoos")
        fi
    fi
    if [ -n "$CASE_SHORE_PATCH" ]; then
        shore_patches+=("$CASE_SHORE_PATCH")
    fi
    if [ "${#shore_patches[@]}" -gt 0 ]; then
        for patch in "${shore_patches[@]}"; do
            [ -f "$patch" ] || return 1
        done
        nspatch "$workdir/meta_shoreside.moos" \
            "${shore_patches[@]}" "$workdir/meta_shoreside.moosx" || return 1
    fi
    if [ -n "$CASE_VEH_MOOS_PATCH" ] &&
       { [ "$LOG_MODE" != full ] || [ -z "$CASE_VEH_MOOS_FULL_PATCH" ]; }; then
        vehicle_patches+=("$CASE_VEH_MOOS_PATCH")
    fi
    if [ "${#vehicle_patches[@]}" -gt 0 ]; then
        for patch in "${vehicle_patches[@]}"; do
            [ -f "$patch" ] || return 1
        done
        nspatch "$workdir/meta_vehicle.moos" \
            "${vehicle_patches[@]}" "$workdir/meta_vehicle.moosx" || return 1
    fi
    if [ -n "$CASE_VEH_BHV_PATCH" ]; then
        [ -f "$CASE_VEH_BHV_PATCH" ] || return 1
        nspatch "$workdir/meta_vehicle.bhv" \
            "$CASE_VEH_BHV_PATCH" "$workdir/meta_vehicle.bhvx" || return 1
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
            --veh_mport="$((case_base + 1))"
            --shore_pshare="$((case_base + PSHARE_OFFSET))"
            --veh_pshare="$((case_base + PSHARE_OFFSET + 1))"
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
last_port=$((PORT_BASE + (total - 1) * PORT_STRIDE + PSHARE_OFFSET + 1))
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
