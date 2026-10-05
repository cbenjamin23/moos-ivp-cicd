# OpRegion CI gate and remaining upstream work

## Current baseline

Reviewed October 5, 2026 against upstream main
`3f0928a9712f802d020414e190ed21a1a028d34b`.
The former development branch `aug1926opreg-cpa` was merged in PR #139.
The original factory admission, metric distance, segment-origin, ETA
interpolation, and delayed breach flag defects are fixed. Crossing and touching
segments now correctly have zero CPA.

The implementation is on `codex/opregion-regression-gate`. GitHub-hosted
execution remains unverified. The installed MOOS-IvP checkout and binaries were not changed;
native validation uses an isolated upstream source/build and disposable mission
copies. Existing MOOS dependency binaries are reused because that source is
unchanged between the installed revision and this upstream snapshot.

## Implemented regression gate

[OpRegion workflow](../.github/workflows/opregion.yml) builds headless upstream
MOOS-IvP on Ubuntu 24.04, then runs these required layers:

1. The exact `opregion` CTest label: geometry, static factory admission,
   ETA-only/CPA-only/combined scoring, and V26 lifecycle/flags.
2. The full `bhvutil` family, migrated to `CPXEngineOG` and `AOF_ContactX`.
3. All eight H02 V26 mission cases.
4. All 27 H01 V24 compatibility cases.

The two former bug-observing H02 sentinels now assert a metric distance and
the delayed breach flag. No required case succeeds by detecting an old defect.

The workflow pins the reviewed upstream SHA. Manual dispatch accepts a branch
or SHA, records its resolved commit, and assesses it without changing the pin.
Upstream changes do not automatically trigger this separate repository's
workflow; use manual dispatch for candidate fixes and update the pin after
review. There is no scheduled monitor, deployment, or installed-binary update.

C++ JUnit reports, mission verdicts, and retained case workdirs are uploaded
even when a test fails. H02 and H01 run sequentially on port bases 22000 and
24000 with two workers each. Compilation failures are blocking, including
failures to compile the known-issue target.

## Known issues remain separate and visible

Configure with `-DMOOS_ENABLE_KNOWN_ISSUE_TESTS=ON` to build four
desired-state contracts under the exact label `opregion-known-issues`.
Their workflow step is explicitly non-blocking. They retain genuine failed
assertions rather than using inverted expectations or CTest `WILL_FAIL`.
They are excluded by default from an ordinary repository build.

| Verified defect | Consequence | Suggested upstream solution |
| --- | --- | --- |
| CPA-only scoring at one meter from the boundary gives both safe and crossing courses utility 100 | CPA no longer distinguishes a boundary exit at this edge; ETA can still penalize it in combined mode | Keep the adaptive CPA thresholds meaningful at or below one meter; require a crossing course to score below a safe course |
| Reversed CPA thresholds initialize successfully | A malformed utility interval is accepted | Validate CPA threshold ordering before adapting the thresholds to the current border distance |
| Both scoring factors can be disabled without an initialization error | The safety objective is built without an active scoring factor | Reject configurations with both ETA and CPA disabled, or explicitly define a no-objective mode |
| A zero CPA window is accepted by the behavior but rejected by its AOF; initialization then masks the failure | A valid objective is produced using a default instead of the requested window | Reject zero at parsing, or propagate every AOF setter failure through initialization rather than overwriting its result |

All four contracts fail against the reviewed revision. Once a fix turns its
contract green, promote that contract into the required suite. A green
regression gate is useful engineering evidence, not a claim that V26 is safe
for every configuration or ready for a safety-critical release.

Additional source-review follow-ups remain outside the four executable
contracts: repetitive CPA diagnostics, a declared but unimplemented
`XYSeglr::getDistSegList` member (a separate free function exists), unused
`lapse_dist` semantics, and restrictive
beta headers in generalized-polygon sources. These require API/intent or
licensing clarification and should not be represented as runtime failures
proven by this matrix.

## Local commands

Build upstream separately, then configure the test workspace with explicit
paths to its source, MOOS package, and MOOSGeodesy package:

```bash
cmake -S . -B build/opregion \
  -DMOOSIVP_SOURCE_TREE_BASE=/path/to/isolated/moos-ivp \
  -DMOOS_DIR=/path/to/isolated/moos-ivp/build/MOOS/MOOSCore \
  -DMOOSGeodesy_DIR=/path/to/isolated/moos-ivp/build/MOOS/MOOSGeodesy \
  -DMOOS_ENABLE_KNOWN_ISSUE_TESTS=ON
cmake --build build/opregion --parallel 4 --target \
  ctest-family-opregion ctest-family-bhvutil ctest-family-opregion-known-issues
python3 scripts/ci_cpp_test_targets.py run --build-dir build/opregion \
  --targets opregion,bhvutil --reports-dir build/opregion/reports
python3 scripts/ci_cpp_test_targets.py run --build-dir build/opregion \
  --targets opregion-known-issues --reports-dir build/opregion/reports
```

The last command currently exits nonzero by design; do not hide that result.
An existing build cache configured before the API migration must be reconfigured
against a compatible upstream checkout. Use separate binary/library output
directories if other local tests rely on the ordinary workspace outputs.

Put the candidate's `bin/` and `scripts/` first in PATH before mission runs.
Use disposable copies if existing `results.txt` or logs must be preserved.
Do not run two scripts using overlapping MOOSDB/pShare port blocks.

```bash
(cd harnesses/opregion_harnesses/H02-opregion_v26 &&
 ./zlaunch.sh --jobs=2 --port_base=22000 --keep_workdirs 10)
(cd harnesses/opregion_harnesses/H01-opregion_safety &&
 ./zlaunch.sh --jobs=2 --port_base=24000 --keep_workdirs 10)
```

## Validation and rollout boundary

Native focused CTests passed 16/16, and the full migrated `bhvutil` family
passed 103/103. Five AOF tests belong to both selections, so these counts are
not additive unique-test totals. H02 V26 passed 8/8, H01 V24 passed 27/27,
and the metric-distance H02 case also passed serially. All 93 Python helper
tests and repository invariants for 68 harness targets passed. The four
known-issue contracts remain red and are not included in these pass counts.

The workflow passes local Actionlint checks. This does not confirm its fresh
Ubuntu build, artifact upload, or GitHub-hosted execution; those require an
actual workflow run after publication. Docker's local daemon is unavailable,
so no Linux portability result is claimed for this implementation. Retain the
existing headless build matrix for broader
compiler/platform checks.

Regenerate documentation and the dependency map after changes to test-family
metadata or harness wiring:

```bash
python3 docs/tools/build_pages.py
python3 scripts/generate_context_graph.py
python3 scripts/list_harness_targets.py validate
python3 scripts/generate_context_graph.py --check
python3 scripts/check_repo_invariants.py
```

Next: run the hosted workflow through a pull request, review its evidence,
and promote individual known-issue contracts as upstream fixes
land. No production deployment or active installation consolidation is part of
this CI change.
