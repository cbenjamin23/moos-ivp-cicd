# H02 nspatch contract

Each case copies `missions/opregion_missions/opregion_motion` into a unique
work directory. The harness applies one `*-vehicle.xbhv` patch to the
harness-owned `v26-stem.bhv`, writing `meta_vehicle.bhvx`, and applies one
`*-shoreside.xmoos` patch to the copied `meta_shoreside.moos`, writing
`meta_shoreside.moosx`. Cases that need deterministic local runtime updates may
also provide an optional `*-vehicle.xmoos` patch, which is combined with the
selected logging overlay and written to `meta_vehicle.moosx`. The copied
launchers already invoke `nsplug -x`, so generated targets consume those
sidecars without modifying the shared stem.

The V26 stem is necessary because `nspatch` keys behavior blocks by behavior
type plus name; a `BHV_OpRegionV26@opreg` block cannot delete or replace the
shared stem's `BHV_OpRegionV24@opreg` block. The behavior patches fully replace
the V26 stem's `transit` and `opreg` blocks. The
shoreside patches fully replace `pMissionEval`; local timer patches fully
replace the vehicle `uTimerScript`. Repeated behavior flags, report columns,
and timer events are therefore explicit and cannot leak between cases.

The explicit `get_case_config()` mapping in `zlaunch.sh` is authoritative:

| Case token | Patch prefix | Optional vehicle MOOS patch |
| --- | --- | --- |
| `convex_contained_keepin_pass` | `convex-contained-keepin-pass` | No |
| `nonconvex_contained_keepin_pass` | `nonconvex-contained-keepin-pass` | No |
| `lapsed_recovery_pass` | `lapsed-recovery-pass` | Yes |
| `entry_gate_start_outside_pass` | `entry-gate-start-outside-pass` | No |
| `dynamic_region_update_pass` | `dynamic-region-update-pass` | Yes |
| `stay_in_disabled_breach_pass` | `stay-in-disabled-breach-pass` | No |
| `metric_distance_macro_pass` | `metric-distance-macro-pass` | No |
| `delayed_breach_flag_pass` | `delayed-breach-flag-pass` | No |

Each prefix provides `-vehicle.xbhv` and `-shoreside.xmoos`. Mission names
come from `mission_mod` in the case patch, not a launcher-derived `--mmod`.
The launcher verifies patches before starting a case and cleans the copied
mission before patching it. Preserved workdirs live under
`.harness_runs/<run-id>/` for generated-target, log, and sidecar audits.
