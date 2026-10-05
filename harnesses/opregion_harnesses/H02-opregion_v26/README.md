# H02 OpRegion V26

This harness exercises the generalized-polygon and active keep-in behavior
introduced by `BHV_OpRegionV26`. It reuses the proven
`missions/opregion_missions/opregion_motion` launch path, but every case runs
from an isolated copy with V26-specific `.bhvx` and `.moosx` sidecars. The
existing H01 V24 suite is unchanged.

## Upstream integration gate

The focused workflow pins upstream main commit
`3f0928a9712f802d020414e190ed21a1a028d34b` (reviewed October 5, 2026).
The factory admission, metric distance, segment origin, ETA interpolation,
delayed breach flag, and zero-CPA intersection fixes are present. All eight
cases now assert desired behavior; no case passes by observing an old bug.

Remaining CPA edge/configuration defects are separate desired-state CTests
under `opregion-known-issues`, not part of this mission matrix. A green H02
run does not resolve those defects or constitute a safety release approval.
See [the CI plan](../../../docs/opregion_v26_cicd_plan.md).

The default port base is `22000`, the stride is `30`, and each case uses four
listeners: shoreside and vehicle MOOSDB at offsets 0 and 1, then shoreside and
vehicle pShare at offsets 15 and 16. Do not run another harness invocation on
an overlapping block.

## Cases

- `convex_contained_keepin_pass` runs a contained transit in a single-cover
  convex region and requires an active V26 execution signal with no lapse or
  breach.
- `nonconvex_contained_keepin_pass` runs the same contained transit through an
  L-shaped generalized border represented by two convex cover polygons.
- `lapsed_recovery_pass` temporarily shrinks the active border around a moving
  vehicle without reaching the breach distance, then restores the region and
  requires recovery evidence plus route completion.
- `entry_gate_start_outside_pass` starts outside the region with entry gating
  enabled and requires the waypoint behavior to carry the vehicle inside
  before containment becomes active.
- `dynamic_region_update_pass` replaces the generalized polygon at runtime and
  requires the resulting lapsed/recovery transition without a terminal breach.
- `stay_in_disabled_breach_pass` disables the new contained-state keep-in
  objective and passes when the expected terminal breach and helm error are
  observed.
- `metric_distance_macro_pass` requires a real distance between 4 and 14
  meters in the controlled short transit, rejecting the former boolean `1`.
- `delayed_breach_flag_pass` requires both the configured breach flag and
  helm error after the delay expires.

## Run

Use an isolated upstream build after confirming the factory-registration
contract passes:

```bash
export PATH="/path/to/isolated/moos-ivp/bin:/path/to/isolated/moos-ivp/scripts:$PATH"
cd harnesses/opregion_harnesses/H02-opregion_v26
./zlaunch.sh --jobs=2 --port_base=22000 --keep_workdirs 10
```

For target-only validation:

```bash
./zlaunch.sh --just_make --jobs=2 --port_base=22000 10
```

Top-level `results.txt` is published only after all selected cases finish.
Concurrent invocations from this same harness directory are unsupported because
they share that aggregate file; callers must also choose non-overlapping port
ranges.

See [NSPATCH.md](NSPATCH.md) for the sidecar contract and case mapping.
