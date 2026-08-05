# H01-opregion_safety

Logging is minimal by default in both communities. Use `--log=full` for the
whole matrix or with `--case=NAME` for one diagnostic case.

Patch-driven moving correctness harness for
[`missions/opregion_missions/opregion_motion`](../../../missions/opregion_missions/opregion_motion).

This harness focuses on `BHV_OpRegionV24` as the behavior under test. The stem
mission keeps the vehicle motion simple and grades on behavior-owned safety
signals:

- whether the nominal transit stays inside the configured region
- whether a save-region exit posts recovery flags without causing a halt breach
- whether positive `save_dist` generated buffers allow or reject the expected
  route shapes
- whether a halt-region exit causes the expected mission failure
- whether `trigger_on_poly_entry` handles a mission that starts outside the
  halt envelope
- whether `trigger_entry_time` delays formal halt-envelope entry
- whether `trigger_exit_time` debounces a short halt-region excursion
- whether `reset=true` clears entry state before a later halt-envelope exit
- whether `max_time` causes the expected failure
- whether `max_depth` and `min_altitude` runtime breaches halt through
  behavior-owned errors
- whether invalid scalar and boolean configuration values put the helm into
  `MALCONFIG`
- whether runtime `OPREGION_CORE_POLY` shrink and expansion updates are accepted
  and enforced
- whether explicit `save_poly` and `halt_poly` configuration is honored

## Current Matrix

- `inside_region_pass` Sends the vehicle from `(-18,-121)` through `(42,-121)` and back to `(12,-121)` inside the core box `[-23,47]×[-152,-90]`, testing nominal containment; passes on arrival with no save-, halt-, or time-breach flag and no `BHV_ERROR` mail.
- `save_recover_pass` Narrows the core's east edge to `x=27`, keeps the halt edge at `x=49`, and routes through `x=34` before returning to `x=10`, testing that a save-region exit posts both the one-time `save_flag` and repeated `savex_flag` without reaching the halt region; passes on arrival with `SAVE_REGION_BREACHED=true`, `SAVE_REGION_RECOVERING=true`, and no halt/time breach or behavior error.
- `save_dist_buffer_pass` Uses core east edge `x=32`, `save_dist=16`, and `halt_dist=24` on the stock route to `x=42`, testing that the generated save buffer contains a point outside the core; passes on arrival with all breach flags false and no behavior error.
- `save_dist_buffer_fail` Uses core east edge `x=32`, `save_dist=16`, and `halt_dist=36`, then routes through `x=58`, testing that the vehicle can leave the generated save buffer while remaining inside the larger halt buffer; passes after `SECS_OUT_SAVE_POLY>=1` with both save flags true and no halt/time breach or behavior error.
- `halt_breach_fail` Uses a core ending at `x=10` with `halt_dist=4`, placing the eastbound route outside the halt envelope; the harness passes when `HALT_REGION_BREACHED=true`, `TIME_LIMIT_BREACHED=false`, and any `BHV_ERROR` mail has appeared.
- `entry_gate_start_outside_pass` Places the core's west edge at `x=-10` with `halt_dist=5`, so the vehicle starts three meters outside the halt envelope, and sets `trigger_on_poly_entry=true`; passes after the vehicle enters and completes the route with no save-, halt-, or time-breach flag and no behavior error.
- `entry_gate_disabled_fail` Uses the same start-outside geometry with `trigger_on_poly_entry=false`, testing immediate enforcement before polygon entry; the harness passes when `HALT_REGION_BREACHED=true`, time breach remains false, and any behavior error has appeared.
- `trigger_exit_debounce_pass` Routes to `x=58` and back across the halt edge at `x=50` with `trigger_exit_time=80`, testing that a real halt-region exit shorter than the configured delay is debounced; passes after the behavior reports at least four seconds outside with no halt/time breach or behavior error.
- `trigger_exit_strict_fail` Uses the same out-and-back route and halt geometry with `trigger_exit_time=0.5`, testing strict exit enforcement; the harness passes when the excursion produces `HALT_REGION_BREACHED=true` and a behavior error without a time breach.
- `trigger_entry_delay_pass` Uses the same route with `trigger_entry_time=80` and `trigger_exit_time=0.5`, testing that the initial stay inside never becomes an official entry and therefore the later exit is not enforced; an ordered evaluator first observes at least four seconds inside, then at least two seconds outside, and requires no halt/time breach or behavior error.
- `reset_before_exit_pass` Uses the same route with `trigger_exit_time=5` and posts `OPREGION_UPDATES="reset=true"` about three seconds after crossing the halt edge, testing that reset clears the prior official entry before the five-second exit threshold; passes only when `IVPHELM_UPDATE_RESULT` reports success for `opreg` and `OPREGION_UPDATES`, the behavior remains outside for at least four post-reset seconds, and no halt/time breach or behavior error occurs.
- `max_time_fail` Sets `max_time=8` while keeping the region large enough for the route, testing the behavior's mission timer; the harness passes when `TIME_LIMIT_BREACHED=true` and a behavior error appear while save and halt breach remain false.
- `max_depth_breach_fail` Sets `max_depth=1` and posts `NAV_DEPTH=5` once per second from times two through six, testing the numeric maximum-depth comparison; passes only with `DEPTH_LIMIT_BREACHED=true`, the paired input value `5`, and a behavior error before the missing-breach deadline.
- `min_altitude_breach_fail` Seeds `NAV_ALTITUDE=20`, then lowers it to `2` with `min_altitude=10`, testing the numeric minimum-altitude comparison; an inactive helper registers the input that `BHV_OpRegionV24` currently omits from its subscriptions, and the case passes only with `ALTITUDE_LIMIT_BREACHED=true`, the paired input value `2`, and a behavior error before the deadline.
- `bad_save_dist_fail` Sets `save_dist=-1`, testing rejection of a negative save buffer; passes only when `IVPHELM_STATE` becomes exactly `MALCONFIG` before the missing-state deadline.
- `bad_halt_dist_fail` Sets `halt_dist=-1`, testing rejection of a negative halt buffer; passes only on the same exact pre-deadline `MALCONFIG` state.
- `bad_max_depth_fail` Sets `max_depth=-1`, testing rejection of a negative depth limit; passes only on the same exact pre-deadline `MALCONFIG` state.
- `bad_min_altitude_fail` Sets `min_altitude=-1`, testing rejection of a negative altitude limit; passes only on the same exact pre-deadline `MALCONFIG` state.
- `bad_recover_spd_fail` Sets `recover_spd=0`, testing rejection of a nonpositive recovery speed; passes only on the same exact pre-deadline `MALCONFIG` state.
- `bad_trigger_on_poly_entry_fail` Sets `trigger_on_poly_entry=maybe`, testing rejection outside the accepted Boolean forms; passes only on the same exact pre-deadline `MALCONFIG` state.
- `bad_trigger_entry_time_fail` Sets `trigger_entry_time=-1`, testing rejection of a negative entry delay; passes only on the same exact pre-deadline `MALCONFIG` state.
- `bad_trigger_exit_time_fail` Sets `trigger_exit_time=-1`, testing rejection of a negative exit delay; passes only on the same exact pre-deadline `MALCONFIG` state.
- `dynamic_region_expand_pass` Starts with a dynamic core ending at `x=21`, then posts an expanded core ending at `x=60` after three seconds, testing expansion before the vehicle reaches the narrow save boundary; passes on arrival with all breach flags false and no behavior error.
- `dynamic_region_update_pass` Starts with a core ending at `x=47`, posts a shrink to `x=21` after six seconds, and routes through `x=34` before returning to `x=4`, testing runtime enforcement of the recomputed save boundary; passes on arrival with both `SAVE_REGION_BREACHED=true` and `SAVE_REGION_RECOVERING=true`, plus no halt/time breach or behavior error.
- `dynamic_region_halt_fail` Posts a shrink from east edge `x=47` to `x=5` after six seconds while retaining the stock eight-meter halt distance, testing immediate enforcement of a recomputed halt boundary; the harness passes when `HALT_REGION_BREACHED=true` and a behavior error appear without a time breach.
- `explicit_polygons_pass` Uses explicit `save_poly` and `halt_poly` values instead of generated distance buffers, routes outside the explicit save polygon while remaining inside the explicit halt polygon, and requires save recovery without a halt breach.
- `explicit_halt_poly_fail` Uses an explicit halt polygon ending at `x=25`, routes through `x=34`, and requires the explicit halt boundary to produce the expected halt breach.

## Running

```bash
./zlaunch.sh
./zlaunch.sh --case=save_recover_pass 10
./zlaunch.sh --case=trigger_exit_debounce_pass --gui 1
./zlaunch.sh --just_make 10
./zlaunch.sh --jobs=4 --port_base=31000 10
./zlaunch.sh --jobs=4 --port_base=35600 --port_stride=20 10
```

Results are appended to `results.txt` with `case=<case_name>` followed by the
mission-owned `grade` and the OpRegion safety flags used for grading. Expected
negative cases grade `pass` when their expected breach, behavior-error, or exact
`MALCONFIG` evidence is observed. Boundary-delay and reset cases lead on
behavior-owned seconds-inside/outside state; `TEST_EVAL_READY` is only a
missing-evidence deadline.

Wave mode runs the full matrix in isolated temporary mission copies. Each case
gets its own MOOSDB and pShare port block using
`case_base = port_base + case_idx*PORT_STRIDE`, with pShare ports starting at
`case_base + 10`. The default is serial `--jobs=1` and `PORT_STRIDE=30`; use
`--port_stride=20` with the 25-case matrix to keep validation inside a 500-port
band. Use `--keep_workdirs` when preserving the temporary case folders is useful
for debugging.

Latest validation:

- July 20, 2026
- syntax: `bash -n harnesses/opregion_harnesses/H01-opregion_safety/zlaunch.sh`
- just_make matrix: `25/25` target generations completed with
  `--just_make --jobs=4 --port_base=35600 --port_stride=20 10`
- wave matrix: `25/25` mission-owned grades passed with
  `--jobs=4 --port_base=45000 --port_stride=20 --max_time=80 10`
- mutations: removing the reset or save-recovery flag, shortening either delay,
  keeping depth/altitude on the safe side, and repairing a malformed parameter
  all produced mission-owned `grade=fail`
- warp: `10`
