# Upstream regression gate and remaining defects

## Reviewed baseline

The workflow pins official MOOS-IvP main at
`41cd21eecdfc5a7b40c034044d5e96e045b0d05f`. It includes merged OpRegion fixes
and subsequent CPX geometry, velocity regulation, helm all-stop, log
suppression, nspatch, and runtime shore-route changes. Unmerged mission
reorganization and IvPico proposals are outside this baseline.

Manual dispatch can assess another SHA or branch and records the resolved
commit. Upstream pushes do not automatically trigger this separate repository.

## Required CI coverage

The [regression workflow](../.github/workflows/opregion.yml) builds headless
upstream on Ubuntu 24.04 and requires:

- All Python contracts, including real nspatch output and dependency preflight.
- Exact CTest families `opregion`, `bhvutil`, `merged-upstream`,
  `behaviors-colregs`, `helmivp`, `geometry`, `mbutil`, and `logutils`.
- Eight V26 and 27 V24 mission cases.
- All 26 runtime-route cases and all 35 communication cases.
- The 11 core broker cases, including keyword rejection.

The five mission steps run sequentially, with two workers each and explicit
20000-range port bases: 107 required core cases. Test-family counts overlap
and must not be summed as unique coverage. Required compilation failures are
blocking, including compilation of known-defect binaries. Older tracked
verdicts are removed before running; summaries, JUnit, mission verdicts, and
case workdirs are retained after failure.

## Compatibility and test corrections

Launchers use positional nspatch stem/patch/target arguments because the pinned
parser can shadow generic behavior-file flags. Real CLI tests verify sidecar
contents, vehicle-key filtering, and failure status. Pre-October tools are not
covered; put the selected upstream tools first in PATH.

AOF tests supply the external CPX engine required by the current API. Contracts
cover stationary contacts, velocity and obstacle-speed regulation, duplicate-log
suppression, and helm state. GNU linking requires `gen_poly` before geometry;
the map-image test also compiles upstream `TiffUtils.cpp`.

Geometry/string expectations follow actual helper contracts: inclusive side
boundaries, the half-turn convention, meaningful winding on non-degenerate
shapes, compact decimal formatting, current platform summary fields, and
whitespace trimming. Full-precision numeric assertions remain. The loiter
fixture tests distinct approaches on either side of a symmetric tie rather
than depending on math-library rounding to choose a direction.

## Broker contracts and dependencies

The legacy `keyword_mismatch_status_pass` token now grades rejection. The
mission must observe an incoming broker ping, then require zero enrolled nodes,
no broker acknowledgement, and no delivered traffic. No attempted connection
means failure. `pMissionEval` owns the grade.

Runtime-route/discovery fixtures explicitly enable `accept_try_shore_host`
where needed. The default-rejection fixture omits it and verifies no route is
created. No global opt-in is added to the mission stem.

The full H02 broker matrix has 12 cases. Its mediation case needs the separate
`pMediator` app from `moos-ivp-swarm`. Live runs check this dependency before
creating workdirs or launching apps. `--just_make` can generate targets without
it. `--core_only` explicitly selects the other 11 cases; combining that option
with an explicit mediation case is rejected. CI runs the core selection;
extension integration is validated separately with that dependency available.

## Six non-blocking upstream defects

Enable `MOOS_ENABLE_KNOWN_ISSUE_TESTS`. Labels `opregion-known-issues` and
`logstart-known-issues`, and `colorpack-known-issues` are disjoint from required families. Their workflow
step uses `continue-on-error` while preserving real failed assertions; no
expectation is inverted and no test uses `WILL_FAIL`.

| Defect | Upstream correction |
| --- | --- |
| CPA-only scoring gives safe and crossing courses full utility one meter from the boundary | Preserve a meaningful scoring interval when adapting thresholds |
| Reversed CPA thresholds initialize successfully | Validate ordering before adaptation |
| Both ETA and CPA factors can be disabled while initialization succeeds | Reject this configuration or define an explicit no-scoring mode |
| A zero CPA window is rejected internally, then silently replaced by defaults | Validate consistently and preserve failed setter results |
| End-of-line log timestamps leave the parser buffer unterminated | Bound writes and terminate the token before parsing |
| Invalid color construction leaves status flags uninitialized | Initialize flags on every constructor path before rejecting invalid input |

The ordinary file/time-bounds test uses a whitespace-terminated header. The
separate defect contract retains the bare end-of-line case and a shorter
parse after a longer timestamp; its precision expectations are not relaxed.
The invalid-color constructor is exercised separately from ordinary circle
parsing. The rotated lawnmower containment test uses the shared geometry
tolerance at the boundary and rejects non-finite coordinates.
Promote each defect after verifying its upstream fix. A green required job
does not mean these defects are fixed or approve a safety release.

## Validation and publication

Validate the exact proposed tree in a clean checkout. An earlier numeric-sharing
false alarm came from an old snapshot expecting ten reports while the current
fixture already expected four. The four-report correction belongs in this
publication.

Native validation can run the full C++ suite with GUI dependencies; macOS GUI
tests need desktop-service access. A fresh Debian container checks headless
builds and the required C++/Python/mission layers. That does not replace the
hosted Ubuntu/Ninja/dependency-install/artifact run. The optional broader Docker
compiler/platform matrix is compile-only.

After metadata or harness changes, regenerate docs and the dependency map and
run repository/C++ invariants. Stage reviewed CI/test/docs changes while
preserving unrelated working edits. Push the CI branch and use a pull request
and hosted gate before merging. CI does not deploy or rebuild an active user
installation.
