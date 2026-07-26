#!/usr/bin/env python3
"""Generate the static GitHub Pages site for the CI/CD harness catalog."""

from __future__ import annotations

import re
import shlex
import sys
from dataclasses import dataclass
from html import escape
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[2]
HARNESS_DIR = REPO_ROOT / "harnesses"
CPP_TEST_DIR = REPO_ROOT / "tests" / "cpp"
SCRIPTS_DIR = REPO_ROOT / "scripts"
REPO_BLOB = "https://github.com/cbenjamin23/moos-ivp-cicd/blob/main"
UPSTREAM_REVISION = "29ea136b6d489fd8dda093b6218a51e4022badeb"
UPSTREAM_BLOB = f"https://github.com/moos-ivp/moos-ivp/blob/{UPSTREAM_REVISION}"
ASSET_VERSION = "20260719-1"
PENDING_GIF = "GIF_PENDING"
CASE_ARRAY_RE = re.compile(
    r"^\s*([A-Z0-9_]*CASES)\s*=\s*\(\s*(.*?)\)\s*(?:#.*)?$",
    re.MULTILINE | re.DOTALL,
)
ARRAY_REF_RE = re.compile(r"^\$\{([A-Z][A-Z0-9_]*)\[@\]\}$")
CASE_NAME_RE = re.compile(r"\b[A-Za-z0-9_]+_(?:pass|fail|absent)\b")
VISUAL_NOTES = {
    "cmgr-unit": "This unit harness uses map-style explanatory GIFs instead of pMarineViewer captures because the ownship geometry is intentionally simple and the verdict comes from MOOS publications such as contact alerts, reports, and filter messages.",
    "obmgr-unit": "This unit harness uses map-style explanatory GIFs instead of pMarineViewer captures because the ownship is stationary and the verdict comes from MOOS publications such as obstacle acceptance, distance reports, hull generation, and filter messages.",
    "pid-unit": "This unit harness uses variable-level PID evidence instead of pMarineViewer captures because it intentionally checks pMarinePIDV22 input/output behavior before adding vehicle dynamics.",
    "pid-motion": "This motion harness uses PID-focused generated visuals instead of raw pMarineViewer captures because the verdict depends on bridged navigation, actuator output, and closed-loop vehicle response.",
    "constant-depth-motion": "These depth GIFs are generated from real run alogs, not raw pMarineViewer screen captures, because the top-down track alone does not show held-depth behavior clearly.",
    "goto-depth-motion": "These depth GIFs are generated from real run alogs, not raw pMarineViewer screen captures, because the top-down track alone does not show commanded depth sequence progress clearly.",
    "periodic-surface-motion": "These depth GIFs are generated from real run alogs, not raw pMarineViewer screen captures, because the top-down track alone does not show surfacing cycles and wait windows clearly.",
    "max-depth-motion": "These depth GIFs are generated from real run alogs, not raw pMarineViewer screen captures, because the top-down track alone does not show max-depth guard pressure clearly.",
    "min-altitude-motion": "These depth GIFs are generated from real run alogs, not raw pMarineViewer screen captures, because the top-down track alone does not show bottom-clearance evidence clearly.",
    "periodic-speed-behavior-motion": "These PeriodicSpeed GIFs are generated explanatory views instead of raw pMarineViewer captures because the meaningful evidence is the lazy/busy timer state, reset behavior, and posted speed variables.",
    "timer-behavior-motion": "These Timer GIFs are generated explanatory views instead of raw pMarineViewer captures because BHV_Timer returns no IvP function and the meaningful evidence is the changing MOOS counter variables.",
    "memoryturnlimit-behavior-motion": "These MemoryTurnLimit GIFs are generated explanatory views instead of raw pMarineViewer captures because the important evidence is the relationship between recent heading memory, turn range, runtime updates, and graded motion metrics.",
    "usim-marine-motion": "These uSimMarineV22 GIFs are generated explanatory views instead of raw pMarineViewer captures because the harness is validating actuator inputs, drift/current effects, runtime controls, and NAV output evidence directly.",
    "pnodereporter-unit": "These pNodeReporter GIFs are generated report-flow views instead of raw pMarineViewer captures because the harness verdict depends on MOOS mail and NODE_REPORT payload fields rather than visible vehicle motion.",
    "hostinfo-unit": "These pHostInfo GIFs are generated explanatory views instead of raw pMarineViewer captures because the meaningful evidence is host-info MOOS mail, not map geometry.",
    "loadwatch-unit": "These uLoadWatch GIFs are generated explanatory views instead of raw pMarineViewer captures because the meaningful evidence is threshold mail and breach counters.",
    "processwatch-unit": "These uProcessWatch GIFs are generated explanatory views instead of raw pMarineViewer captures because the meaningful evidence is process-presence summaries and mapped output variables.",
    "pmissioneval-unit": "These pMissionEval GIFs are generated mail-flow views instead of raw pMarineViewer captures because the meaningful evidence is mission grading mail, report rows, flags, and completion publication.",
    "pmissionhash-unit": "These pMissionHash GIFs are generated mail-flow views instead of raw pMarineViewer captures because the meaningful evidence is hash publication names, disabled outputs, and reset-driven hash changes.",
    "umayfinish-unit": "These uMayFinish GIFs are generated process-flow views instead of raw pMarineViewer captures because the meaningful evidence is finish-variable matching, timeout behavior, and process exit code.",
    "colregs-classification": "This classification harness uses alog-backed explanatory GIFs instead of raw pMarineViewer captures because the vehicles do move, but the verdict comes from COLREGS publications such as mode, index, summary, and range reports.",
    "colregs-thresholds": "This threshold harness uses alog-backed overlay GIFs instead of raw pMarineViewer captures because the cases differ by small geometry changes and the verdict comes from boundary-specific COLREGS publications.",
}


def published_media_name(filename: str) -> str:
    """Return the static-site media asset generated from a source GIF name."""
    if filename.endswith(".gif"):
        return f"{filename[:-4]}.mp4"
    return filename


@dataclass(frozen=True)
class Harness:
    slug: str
    title: str
    family: str
    path: str
    mission: str
    summary: str
    proof: str
    gifs: tuple[tuple[str, str, str], tuple[str, str, str]]
    run: str
    notes: tuple[str, ...]


@dataclass(frozen=True)
class Family:
    name: str
    label: str
    summary: str
    slugs: tuple[str, ...]


@dataclass(frozen=True)
class CTestArea:
    key: str
    label: str
    target_count: int
    source_count: int
    case_count: int
    description: str
    labels: tuple[str, ...]
    path: str


@dataclass(frozen=True)
class Example:
    slug: str
    title: str
    category: str
    summary: str
    source_path: str
    test_path: str
    mutation: str
    diff: str
    command: str
    baseline: str
    failure: str
    why_it_looks_good: str
    what_changed: str
    what_caught_it: str
    corrected_approach: str
    feature_commits: tuple[tuple[str, str], ...] = ()
    diff_label: str = ""
    source_revision: str = ""


@dataclass(frozen=True)
class RealExample:
    slug: str
    title: str
    category: str
    summary: str
    pr_number: int
    pr_author: str
    pr_status: str
    source_path: str
    test_path: str
    failing_revision: str
    fixed_revision: str
    problem: str
    incomplete_solution: str
    diff: str
    diff_label: str
    command: str
    failure: str
    what_caught_it: str
    corrected_approach: str
    corrected_result: str


EXAMPLE_CATALOG: tuple[Example, ...] = (
    Example(
        slug="global-obstacle-alert-deduplication",
        title="The deduplication that ignores the second obstacle",
        category="Mission harness · debugging",
        summary="Suppressing repeated publications on one alert variable reduces traffic, but two different obstacle IDs legitimately share that channel.",
        source_path="ivp/src/pObstacleMgr/ObstacleManager.cpp",
        test_path="harnesses/obstacle_behavior_harnesses/H01-obstacle_behavior_motion/README.md",
        mutation="Post only the first obstacle alert",
        diff="""void ObstacleManager::postConvexHullUpdate(...)
{
+  if(m_alerts_posted > 0)
+    return;
+
   XYPolygon poly = m_map_obstacles[key].getPoly();""",
        command="""cd harnesses/obstacle_behavior_harnesses/H01-obstacle_behavior_motion
./zlaunch.sh --case=two_obstacles_clean_pass \\
  --port_base=42000 --log=minimal 10""",
        baseline="failures=0 total=1 elapsed_seconds=12",
        failure="""grade=fail
obstacle_alert_count=1
obstacle_spawned=ob_one
arrived=true collisions=1 encounters=2

failures=1 total=1 elapsed_seconds=12""",
        why_it_looks_good="OBSTACLE_ALERT is one MOOS variable, so treating later posts as duplicates looks like a simple way to reduce repeated work and message traffic.",
        what_changed="The variable is a stream, not a singleton. Each publication carries an obstacle ID. Global deduplication allows ob_one through, suppresses ob_two, and prevents the second spawned avoidance behavior from being created.",
        what_caught_it="The mission requires two alert deliveries and the final spawned ID ob_two. It also grades the vehicle outcome, exposing the operational consequence: the vehicle arrives but records a collision.",
        corrected_approach="Deduplicate by obstacle identity and payload version, not by output variable or lifetime alert count. Retain the two-obstacle mission as the integration guard.",
    ),
    Example(
        slug="dynamic-operating-region",
        title="The geofence update that never takes effect",
        category="Mission harness · new feature",
        summary="Changing an operating boundary during deployment is a real MOOS-IvP feature. A plausible first implementation subscribes to the update but never rebuilds the active safety polygons.",
        source_path="ivp/src/lib_behaviors-marine/BHV_OpRegionV24.cpp",
        test_path="harnesses/opregion_harnesses/H01-opregion_safety/README.md",
        mutation="Add runtime geofence updates without rebuilding the active regions",
        diff="""+  else if(param == \"dynamic_region_var\") {
    m_dynamic_region_var = val;
    addInfoVars(m_dynamic_region_var);
    return(true);
  }
  ...
  if(getBufferVarUpdated(m_dynamic_region_var)) {
    bool ok;
    getBufferStringVal(m_dynamic_region_var, ok);
  }""",
        command="""cd harnesses/opregion_harnesses/H01-opregion_safety
./zlaunch.sh --case=dynamic_region_update_pass \\
  --port_base=45500 --log=minimal 10""",
        baseline="""grade=pass arrived=true
save_breached=true save_recovering=true
halt_breached=false bhv_error=false

failures=0 total=1 elapsed_seconds=11""",
        failure="""grade=fail arrived=true
save_breached=false save_recovering=false
halt_breached=false bhv_error=false

failures=1 total=1""",
        why_it_looks_good="Operators may need to shrink a permitted area without restarting the helm. Registering an information variable and consuming its latest value looks like the normal plumbing for that feature, and the mission still runs to completion.",
        what_changed="Nothing operational changed. The update payload was read and discarded, leaving the original core, save, and halt polygons in force even though the new boundary was displayed by the mission.",
        what_caught_it="The harness shrinks the core polygon after six seconds and requires SAVE_REGION_BREACHED=true when the vehicle crosses the new save boundary. Arrival alone is deliberately insufficient.",
        corrected_approach="The completed upstream implementation parses the new core polygon and calls onSetParamComplete(), which rebuilds the derived save and halt polygons before the next safety decision.",
        feature_commits=(("5d7b2bb11", "dynamic region support"),),
        diff_label="Reconstructed incomplete implementation",
    ),
    Example(
        slug="coordinate-output-order",
        title="The coordinate cleanup that swaps X and Y",
        category="C++ unit test · debugging",
        summary="A conventional output-argument order looks more natural, compiles cleanly, and returns plausible coordinates—but puts each value in the wrong field.",
        source_path="ivp/src/pNodeReporter/NodeReporter.cpp",
        test_path="tests/cpp/pnodereporter/Core/NodeReporterTest.cpp",
        mutation="Treat the geodesy outputs as X then Y",
        diff="""-  m_geodesy.LatLong2LocalGrid(nav_lat, nav_lon, nav_y, nav_x);
+  m_geodesy.LatLong2LocalGrid(nav_lat, nav_lon, nav_x, nav_y);""",
        command="""cd tests/cpp
./ctests.sh --pnodereporter --jobs=4""",
        baseline="100% tests passed, 0 tests failed out of 17",
        failure="""CrossFillSynthesizesLocalAndGlobalCoordinates
Expected X: -4.717421778   Actual X:  6.668403106
Expected Y:  6.741529793   Actual Y: -4.810944792

94% tests passed, 1 tests failed out of 17""",
        why_it_looks_good="Most APIs return Cartesian coordinates in X/Y order. Reordering the two output arguments makes the call read the way a maintainer would expect, and the types provide no warning because both arguments are doubles.",
        what_changed="This MOOSGeodesy call uses the less obvious Y/X output order. Swapping the arguments still produces finite, believable numbers, but pNodeReporter serializes the wrong local position.",
        what_caught_it="The pNodeReporter CTest checks the numeric result in both conversion directions. Merely checking that X and Y exist would let this edit pass.",
        corrected_approach="Keep the established Y/X argument order. If the call is wrapped for readability, give the wrapper named X and Y outputs and preserve a numeric round-trip test.",
    ),
    Example(
        slug="stale-contact-timestamps",
        title="The stale-contact cleanup that deletes a live vehicle",
        category="C++ unit test · new feature",
        summary="Automatically expiring vehicles that stop reporting is useful. Reusing the sender's timestamp looks natural, but clock skew can make a freshly received contact appear old.",
        source_path="ivp/src/lib_geodaid/ContactLedger.cpp",
        test_path="tests/cpp/geodaid/ContactLedger/ContactLedgerTest.cpp",
        mutation="Measure contact freshness from the sender's report timestamp",
        diff=""" bool ContactLedger::isStale(string vname, double thresh) const
 {
-  map<string,double>::const_iterator p;
-  p = m_map_records_utc.find(vname);
-  if(p == m_map_records_utc.end())
+  double report_utc = getUTC(vname);
+  if(report_utc == 0)
     return(false);

-  double rcvd_utc = p->second;
-  double elapsed  = m_curr_utc - rcvd_utc;
+  double elapsed = m_curr_utc - report_utc;
 }""",
        command="""cd tests/cpp
./ctests.sh --geodaid --jobs=4""",
        baseline="100% tests passed, 0 tests failed out of 21",
        failure="""DistinguishesReportTimestampAgeFromReceiveTimestampAge
Value of: ledger.isStale(\"abe\", 20)
  Actual: true
Expected: false
Expected stale contacts: 0
  Actual: 1

95% tests passed, 1 test failed out of 21""",
        why_it_looks_good="Every node report already carries a UTC timestamp, so reusing getUTC() avoids a second lookup and appears to measure the report's age directly. It works whenever vehicle clocks are perfectly synchronized.",
        what_changed="The report timestamp says when the sender created the message, not when this vehicle received it. With latency or clock skew, a report received five seconds ago can appear thirty-five seconds old and be removed as stale.",
        what_caught_it="The CTest receives a report stamped 70 at local time 100, advances to 105, and applies a 20-second stale threshold. The contact is fresh by its five-second receive age even though its embedded timestamp is thirty-five seconds old.",
        corrected_approach="Keep local receipt times in m_map_records_utc for stale-contact decisions. Use the embedded report timestamp for extrapolation and clock-skew telemetry, where sender time is the value that actually matters.",
        feature_commits=(("5472d94c2", "contact staleness tracking"),),
        diff_label="Reconstructed incomplete implementation",
        source_revision=UPSTREAM_REVISION,
    ),
)

REAL_EXAMPLE_CATALOG: tuple[RealExample, ...] = (
    RealExample(
        slug="proj-geodesy-value-semantics",
        title="Restoring PROJ broke safe geodesy copies",
        category="Unit tests · merged PR #106",
        summary="The restored PROJ backend converted coordinates correctly in the simple case, but copied geodesy objects crashed and successful conversions left their stored coordinates at zero.",
        pr_number=106,
        pr_author="HeroCC",
        pr_status="Merged July 23, 2026",
        source_path="MOOS_Jul2724/MOOSGeodesy/libMOOSGeodesy/MOOSGeodesyProj.cpp",
        test_path="tests/cpp/moosgeodesy/Core/MOOSGeodesyTest.cpp",
        failing_revision="00b2cf84",
        fixed_revision="68523edd",
        problem="PR #106 restored the PROJ implementation and made it selectable at build time. The first complete-looking version passed ordinary coordinate conversions, but it treated owned PROJ handles like ordinary copyable fields and returned projected values without updating MOOSGeodesy's stored state.",
        incomplete_solution="The implementation owned raw PROJ handles, freed them in the destructor, and relied on compiler-generated copy operations. A copy therefore shared the same handles, while repeated conversions returned good output arguments but left the object's getters stale.",
        diff="""-  projPJ pj_utm_;
-  projPJ pj_latlong_;
+  typedef std::shared_ptr<void> ProjectionPtr;
+  ProjectionPtr m_utm_projection;
+  ProjectionPtr m_latlong_projection;

-  MetersNorth = tmpNorth - GetOriginNorthing();
-  MetersEast = tmpEast - GetOriginEasting();
+  SetMetersNorth(tmpNorth - GetOriginNorthing());
+  SetMetersEast(tmpEast - GetOriginEasting());
+  MetersNorth = GetMetersNorth();
+  MetersEast = GetMetersEast();""",
        diff_label="Corrections prompted by the failing tests",
        command="""cd tests/cpp
./ctests.sh --moosgeodesy --jobs=4""",
        failure="""18/22 enabled geodesy tests passed

CopyConstructionPreservesProjection: SEGFAULT
CopyAssignmentOutlivesSource: SEGFAULT
ContainerCopiesRemainUsable: SEGFAULT

RepeatedProjectionIsIndependentOfCallHistory
  expected stored east/north ≈ -4.7174 / 6.7415
  actual 0 / 0""",
        what_caught_it="The geodesy family deliberately copies initialized objects, lets source objects die, stores copies in containers, and compares returned coordinates with the object's stored east/north state. Those checks exercised ownership and state consistency that one successful conversion could not reveal.",
        corrected_approach="The PR replaced raw handles with shared ownership using the proper PROJ deleter, persisted successful conversion results through the normal setters, and added further transactional initialization and invalid-input safeguards.",
        corrected_result="All 22 enabled geodesy tests passed, and the corrected implementation merged in PR #106.",
    ),
    RealExample(
        slug="testfailure-burn-timing",
        title="A two-second failure lasted four seconds",
        category="Mission harness · open PR #109",
        summary="The behavior accepted a two-second burn duration and appeared to honor it, but the helm remained blocked for roughly four seconds because the completion callback could trigger the burn twice.",
        pr_number=109,
        pr_author="cbenjamin23",
        pr_status="Corrected upstream; PR remains open",
        source_path="ivp/src/lib_behaviors-marine/BHV_TestFailure.cpp",
        test_path="harnesses/testfailure_behavior_harnesses/H01-testfailure_behavior_unit/README.md",
        failing_revision="2fa08bd7",
        fixed_revision="7e6e6129",
        problem="BHV_TestFailure intentionally stalls the helm to exercise failure handling. Its configurable burn time looked complete, but onCompleteState() could be invoked more than once and each invocation started a fresh busy wait.",
        incomplete_solution="The initial implementation measured elapsed wall time inside onCompleteState() and returned after the requested duration. It had no one-shot guard, so a two-second configuration could burn twice and produce a four-second operational gap.",
        diff="""void BHV_TestFailure::onCompleteState()
{
+  if(m_failure_triggered)
+    return;
+  m_failure_triggered = true;
+
   if(m_failure_crash)
     assert(0);
   else if(m_failure_burn) {
-    MBTimer timer;
-    timer.start();
-    bool done = false;
-    while(!done) {
-      double elapsed_time = timer.get_float_wall_time();
-      if(elapsed_time > m_failure_burn_time)
-        done = true;
-    }
-    timer.stop();
+    const auto start_time = std::chrono::steady_clock::now();
+    while(std::chrono::duration<double>(
+      std::chrono::steady_clock::now() - start_time).count()
+      <= m_failure_burn_time) {}
   }
}""",
        diff_label="One-shot guard and monotonic timer in the corrected PR",
        command="""cd harnesses/testfailure_behavior_harnesses/H01-testfailure_behavior_unit
./zlaunch.sh --case=burn_gap_detected_pass \\
  --port_base=45500 --log=minimal 10""",
        failure="""Configured burn: 2 seconds
Observed normalized helm gap: approximately 4 seconds

Expected gap band: 1.6–2.4 seconds
Result: FAIL — burn lasted about twice as long as requested""",
        what_caught_it="The strengthened mission harness measures the gap between helm iterations and checks duration-specific bands. That distinguishes a two-second burn from a three-second burn instead of merely proving that some delay occurred.",
        corrected_approach="The proposed correction makes failure triggering one-shot and measures the burn with std::chrono::steady_clock. The duration cases then track their configured values across time warps 5, 10, and 20.",
        corrected_result="All nine harness cases pass on corrected commit 7e6e6129. PR #109 is still open, so this result is corrected and reproducible but not yet merged.",
    ),
    RealExample(
        slug="pmarineviewer-refresh-mode",
        title="A valid viewer setting was silently ignored",
        category="Unit test · merged PR #110",
        summary="The viewer advertised refresh_mode and already knew how to apply it internally, but startup configuration never connected the setting to the existing GUI setter.",
        pr_number=110,
        pr_author="cbenjamin23",
        pr_status="Merged July 25, 2026",
        source_path="ivp/src/pMarineViewer/PMV_MOOSApp.cpp",
        test_path="tests/test_pmarineviewer_refresh_mode_contract.py",
        failing_revision="174bd734",
        fixed_revision="4896b545",
        problem="pMarineViewer's example configuration documented refresh_mode=events, and the GUI, repository, and request loops all supported the mode. The startup parser simply omitted the route from the configuration parameter to that existing implementation.",
        incomplete_solution="Most of the feature was already present, so manual inspection at either end looked reassuring: the option was advertised and the runtime consumers were implemented. With no startup branch calling setRadioCastAttrib(), however, a valid configuration line was rejected and had no effect.",
        diff="""bool PMV_MOOSApp::handleStartUp(...)
 {
   ...
+  else if(param == "refresh_mode")
+    handled = m_gui->setRadioCastAttrib(param, value);
   ...
 }""",
        diff_label="Missing startup route added by the corrected commit",
        command="""MOOS_IVP_SOURCE=/path/to/moos-ivp \
  python3 -m unittest -v \
  tests.test_pmarineviewer_refresh_mode_contract""",
        failure="""test_advertised_refresh_mode_reaches_existing_gui_setter ... FAIL
test_existing_gui_setter_updates_both_refresh_state_consumers ... ok
test_request_loops_consume_the_states_updated_by_the_setter ... ok

Ran 3 tests
FAILED (failures=1)""",
        what_caught_it="The restored source-contract test traces the entire advertised path: documentation to startup parsing, startup parsing to the GUI setter, the setter to both refresh-state consumers, and the request loops that read those states.",
        corrected_approach="PR #110 added the missing startup branch and delegated validation to the existing GUI setter. That kept one source of truth for accepted values while finally connecting configuration to behavior.",
        corrected_result="The same three checks pass at corrected commit 4896b545, which merged in PR #110.",
    ),
)

EXAMPLES: tuple[RealExample, ...] = REAL_EXAMPLE_CATALOG

STALE_EXAMPLE_SLUGS = (
    "strict-eflipper-filters",
    "colregs-boundary-tolerance",
    "json-node-reports",
    "dynamic-operating-region",
    "stale-contact-timestamps",
    "global-obstacle-alert-deduplication",
    "coordinate-output-order",
)


HARNESSES: tuple[Harness, ...] = (
    Harness(
        slug="cmgr-unit",
        title="H01 Contact Manager Unit",
        family="Contact Manager",
        path="harnesses/cmgr_harnesses/H01-cmgr_unit",
        mission="missions/cmgr_missions/cmgr_unit",
        summary="Contact-manager mode checks for detection, absence, alerts, reports, filters, and multi-contact outputs.",
        proof="Directly checks detection, absence, report, alert filter, runtime request, closest-contact, and multi-contact publication paths.",
        gifs=(
            ("Runtime Alert Path", "runtime_alert_add_pass", "cmgr-unit-runtime-alert.gif"),
            ("CPA-only Detection", "detect_cpa_only_pass", "cmgr-unit-cpa-detection.gif"),
        ),
        run="./zlaunch.sh --case=detect_baseline_pass 10",
        notes=(
            "This harness reads like a mission-level unit test suite: one stem mission, many focused contact-manager assertions.",
            "The important evidence is mostly variable-level: detection, absence, runtime requests, filters, and report fields.",
        ),
    ),
    Harness(
        slug="cmgr-motion",
        title="H02 Contact Manager Motion",
        family="Contact Manager",
        path="harnesses/cmgr_harnesses/H02-cmgr_motion",
        mission="missions/cmgr_missions/cmgr_motion",
        summary="Moving integration companion proving contact-manager alerts can drive safe collision-avoidance transit.",
        proof="Grades arrival, detection, contact range, encounters, near misses, and collisions over short moving encounters.",
        gifs=(
            ("Baseline Crossing Pass", "baseline_crossing_pass", "cmgr-motion-baseline-crossing.gif"),
            ("Head-on Pass", "head_on_pass", "cmgr-motion-head-on-pass.gif"),
            ("Two Contact Pass", "two_contact_pass", "cmgr-motion-two-contact-pmarineviewer.gif"),
        ),
        run="./zlaunch.sh --case=baseline_crossing_pass --gui 10",
        notes=(
            "This harness connects contact-manager output to a moving collision-avoidance outcome.",
            "Expected-fail cases are included to prove the gate catches missing or late avoidance evidence.",
        ),
    ),
    Harness(
        slug="obmgr-unit",
        title="H01 Obstacle Manager Unit",
        family="Obstacle Manager",
        path="harnesses/obmgr_harnesses/H01-obmgr_unit",
        mission="missions/obmgr_missions/obmgr_unit",
        summary="Obstacle-manager mode checks for alerts, given obstacles, point clusters, hulls, and lifecycle branches.",
        proof="Checks accepted/rejected obstacles, general alerts, distance reports, point-cluster hull generation, lasso, placeholder, disable, enable, and expunge paths.",
        gifs=(
            ("Given Obstacle Alert", "given_baseline_pass", "obmgr-unit-given-baseline.gif"),
            ("Point Cluster Hull", "points_cluster_dist_pass", "obmgr-unit-point-cluster.gif"),
        ),
        run="./zlaunch.sh --case=given_baseline_pass 10",
        notes=(
            "This harness covers obstacle-manager message paths before testing full moving obstacle avoidance.",
            "Point-cluster cases are useful for understanding how raw obstacle observations become usable obstacle geometry.",
        ),
    ),
    Harness(
        slug="obmgr-motion",
        title="H02 Obstacle Manager Motion",
        family="Obstacle Manager",
        path="harnesses/obmgr_harnesses/H02-obmgr_motion",
        mission="missions/obmgr_missions/obmgr_motion",
        summary="Moving integration suite for pObstacleMgr alert output feeding BHV_AvoidObstacleV24.",
        proof="Grades clean arrival, obstacle encounters, near misses, collisions, and expected fail modes in a short corridor.",
        gifs=(
            ("Baseline Center Pass", "baseline_center_pass", "obmgr-motion-baseline-center.gif"),
            ("Offset Clear Pass", "offset_clear_pass", "obmgr-motion-offset-clear.gif"),
            ("Two Sequential Fail", "two_sequential_fail", "obmgr-motion-two-sequential.gif"),
        ),
        run="./zlaunch.sh --case=baseline_center_pass --gui 10",
        notes=(
            "This harness checks whether obstacle-manager alerts lead to clean short-corridor transit.",
            "Expected-fail cases capture conditions where alerts are missing, too difficult, or not actionable.",
        ),
    ),
    Harness(
        slug="pid-unit",
        title="H01 Marine PID Unit",
        family="Marine PID",
        path="harnesses/pid_harnesses/H01-pid_unit",
        mission="missions/pid_missions/pid_unit",
        summary="Headless pMarinePIDV22 unit matrix covering heading, speed, depth, override, stale-input, yaw, and debug-output branches.",
        proof="Checks suffixed rudder, thrust, elevator, control-state, stale-input, yaw-source, and debug publications from scripted MOOS mail.",
        gifs=(
            ("Heading Wrap", "heading_wrap_pass", "pid-unit-heading-wrap.gif"),
            ("Manual Override", "manual_override_zero_pass", "pid-unit-manual-override.gif"),
        ),
        run="./zlaunch.sh --case=rudder_starboard_pass 10",
        notes=(
            "This harness keeps the PID app isolated from simulation and helm behavior so actuator output can be checked directly.",
            "The speed cases intentionally distinguish `speed_factor` mapping, runtime speed-factor updates, PID speed control, and thrust clipping.",
        ),
    ),
    Harness(
        slug="pid-motion",
        title="H02 Marine PID Motion",
        family="Marine PID",
        path="harnesses/pid_harnesses/H02-pid_motion",
        mission="missions/pid_missions/pid_motion",
        summary="Closed-loop pMarinePIDV22 motion matrix covering transit, turn recovery, speed-PID mode, depth response, and authority failures.",
        proof="Checks bridged arrival, corridor position, speed, heading, depth, and actuator evidence from pMarinePIDV22 driving uSimMarineV22.",
        gifs=(
            ("Hard Turn Recovery", "hard_turn_recover_pass", "pid-motion-hard-turn-recover.gif"),
            ("Depth Step Response", "depth_step_pass", "pid-motion-depth-step.gif"),
        ),
        run="./zlaunch.sh --case=baseline_transit_pass --gui 10",
        notes=(
            "This harness adds pHelmIvP and uSimMarineV22 so PID output is judged as vehicle motion instead of only as actuator publications.",
            "Expected-fail cases intentionally hold manual override or cap thrust too low to prove the motion gate catches lost authority.",
        ),
    ),
    Harness(
        slug="usim-marine-motion",
        title="H01 uSimMarineV22 Motion",
        family="uSimMarineV22",
        path="harnesses/usim_marine_harnesses/H01-usim_marine_motion",
        mission="missions/usim_marine_missions/usim_marine_motion",
        summary="App-level simulator harness for uSimMarineV22 actuator response, embedded PID coupling, limits, drift/current inputs, water-depth altitude, pause, reset, disabled-state nav seeding, and stop controls.",
        proof="Checks NAV_X, NAV_Y, NAV_SPEED, NAV_HEADING, NAV_DEPTH, USM_RESET_COUNT, drift summary, and nav-position summary under scripted actuator and runtime mail.",
        gifs=(
            ("Forward Thrust", "thrust_forward_pass", "usim-marine-forward-thrust.gif"),
            ("Runtime Drift", "drift_x_pass", "usim-marine-runtime-drift.gif"),
        ),
        run="./zlaunch.sh --case=thrust_forward_pass --port_base=30000 10",
        notes=(
            "This harness validates uSimMarineV22 directly instead of only using it as a hidden dependency under behavior tests.",
            "The cases intentionally separate actuator command paths, simulator limits, environmental drift, and runtime state controls.",
        ),
    ),
    Harness(
        slug="pnodereporter-unit",
        title="H01 pNodeReporter Unit",
        family="pNodeReporter",
        path="harnesses/pnodereporter_harnesses/H01-pnodereporter_unit",
        mission="missions/pnodereporter_missions/pnodereporter_unit",
        summary="Headless pNodeReporter matrix for node-report construction, platform metadata, helm mode, JSON output, alternate nav streams, coordinate cross-fill, runtime updates, pause/resume, and odometry metrics.",
        proof="Checks NODE_REPORT_LOCAL, NODE_REPORT_FIRST, PLATFORM_REPORT_LOCAL, JSON report output, runtime color/group updates, PNR_MHASH odometry, extrapolation gap metrics, and one expected-fail blackout-interval detector.",
        gifs=(
            ("Baseline Node Report", "nav_report_baseline_pass", "pnodereporter-baseline-report.gif"),
            ("Alternate Nav Report", "alt_nav_report_pass", "pnodereporter-alt-nav-report.gif"),
        ),
        run="./zlaunch.sh --case=nav_report_baseline_pass --port_base=12400 10",
        notes=(
            "This harness makes pNodeReporter explicit instead of treating node reports as incidental support evidence in motion tests.",
            "The cases intentionally combine mission-owned pMissionEval grades with narrow payload-token checks because node reports include dynamic timing fields.",
        ),
    ),
    Harness(
        slug="upokedb-unit",
        title="H01 uPokeDB Unit",
        family="uPokeDB",
        path="harnesses/upokedb_harnesses/H01-upokedb_unit",
        mission="missions/upokedb_missions/upokedb_unit",
        summary="Headless uPokeDB matrix covering explicit host/port pokes, mission-file connection, quiet/cache aliases, numeric and string value forms, overwrites, repeated commands, and time macros.",
        proof="Checks mission-owned pMissionEval grades on the exact MOOS variables posted by uPokeDB, with harness-side token checks for final values, overwritten-value absence, and positive macro-expanded times.",
        gifs=(
            ("Direct Numeric Poke", "numeric_direct_pass", "upokedb-direct-numeric.gif"),
            ("Cached Pokes", "cache_string_numeric_pass", "upokedb-cached-pokes.gif"),
        ),
        run="./zlaunch.sh --case=numeric_direct_pass --port_base=15000 10",
        notes=(
            "This harness tests uPokeDB as the app-under-test rather than using it only as a helper for other harnesses.",
            "Most verdicts are mission-owned because the important behavior is whether the live MOOSDB receives the intended variable/value pair.",
        ),
    ),
    Harness(
        slug="uxms-unit",
        title="H01 uXMS Unit",
        family="uXMS",
        path="harnesses/uxms_harnesses/H01-uxms_unit",
        mission="missions/uxms_missions/uxms_unit",
        summary="Captured-output uXMS matrix covering named scopes, all/alll display, source/time/community columns, history view, truncation, clean CLI override, mission-file config, filters, source selection, aliases, refresh modes, shortcuts, and color mapping.",
        proof="Checks mission readiness with pMissionEval, then grades bounded uXMS terminal captures for required and forbidden display tokens.",
        gifs=(
            ("Scoped Variable", "scoped_var_pass", "uxms-scoped-variable.gif"),
            ("History View", "history_var_pass", "uxms-history-view.gif"),
        ),
        run="./zlaunch.sh --case=scoped_var_pass --port_base=15200 10",
        notes=(
            "This harness grades uXMS at the terminal-output boundary because uXMS is primarily an observer rather than a MOOS variable publisher.",
            "Each case combines a mission readiness grade with explicit required/absent token checks in the captured output.",
        ),
    ),
    Harness(
        slug="uquerydb-unit",
        title="H01 uQueryDB Unit",
        family="uQueryDB",
        path="harnesses/uquerydb_harnesses/H01-uquerydb_unit",
        mission="missions/uquerydb_missions/uquerydb_unit",
        summary="Headless uQueryDB matrix covering CLI/config pass/fail conditions, fail-only queries, missing-variable timeout failure, halt_max_time, numeric comparisons, compound logic, unique names, and check-variable output formats.",
        proof="Checks uQueryDB process return codes, mission readiness with pMissionEval, and .checkvars tokens for ESV, CSV, WSV, config-driven value-only, multi-variable, and timeout-path output.",
        gifs=(
            ("Numeric Condition", "cli_numeric_pass", "uquerydb-numeric-condition.gif"),
            ("Checkvar Formats", "checkvar_csv_pass", "uquerydb-checkvar-formats.gif"),
        ),
        run="./zlaunch.sh --case=cli_numeric_pass --port_base=15600 10",
        notes=(
            "Most cases use a minimal connection .moos file so CLI conditions are isolated from mission-file ProcessConfig defaults.",
            "Expected-fail cases are first-class pass cases when uQueryDB returns non-zero for a satisfied fail condition or missing-variable timeout.",
        ),
    ),
    Harness(
        slug="pechovar-unit",
        title="H01 pEchoVar Unit",
        family="pEchoVar",
        path="harnesses/pechovar_harnesses/H01-pechovar_unit",
        mission="missions/pechovar_missions/pechovar_unit",
        summary="Headless pEchoVar matrix covering live numeric and string echoing, boolean inversion, fan-out, duplicate mapping de-duplication, latest-value handling, EFlipper component maps, filters, separators, cycle suppression, invalid flippers, and independent named flippers.",
        proof="Checks mission-owned pMissionEval grades for direct echo outputs, then validates EFlipper payloads, suppression, de-duplication, and absence cases with narrow alog evidence.",
        gifs=(
            ("Echo Mapping", "numeric_echo_pass", "pechovar-echo-mapping.gif"),
            ("Filtered Flip", "flip_filter_suppresses_pass", "pechovar-filtered-flip.gif"),
        ),
        run="./zlaunch.sh --case=numeric_echo_pass --port_base=17600 10",
        notes=(
            "The CTests already cover EchoVar and EFlipper parser/helper internals, so this harness focuses on live MOOS mail delivery and publication boundaries.",
            "Payloads containing separators or embedded equals signs are graded from the alog because pMissionEval reports are intentionally scalar-oriented.",
        ),
    ),
    Harness(
        slug="utimerscript-unit",
        title="H01 uTimerScript Unit",
        family="uTimerScript",
        path="harnesses/utimerscript_harnesses/H01-utimerscript_unit",
        mission="missions/utimerscript_missions/utimerscript_unit",
        summary="Headless uTimerScript runtime matrix covering exact posts and macro payloads, control-mail ordering, reset counts and delays, publication timing, status configuration, polygon random pairs, delayed-client block-on, awake policies, and process exit.",
        proof="Checks mission-owned pMissionEval grades on live uTimerScript publications, with external uPokeDB used only for runtime control mail and alog counts used for reposting and burst evidence.",
        gifs=(
            ("Timed Numeric/String", "timed_numeric_string_pass", "utimerscript-timed-numeric-string.gif"),
            ("Pause/Unpause", "pause_unpause_external_pass", "utimerscript-pause-unpause.gif"),
        ),
        run="./zlaunch.sh --case=timed_numeric_string_pass --port_base=7300 10",
        notes=(
            "The harness treats uTimerScript as the app-under-test and deliberately avoids using another uTimerScript instance as the driver.",
            "The CTests already cover parser/helper internals, so this page focuses on live MOOS timing, control mail, and reset/status behavior.",
        ),
    ),
    Harness(
        slug="pdeadmanpost-unit",
        title="H01 pDeadManPost Unit",
        family="pDeadManPost",
        path="harnesses/pdeadmanpost_harnesses/H01-pdeadmanpost_unit",
        mission="missions/pdeadmanpost_missions/pdeadmanpost_unit",
        summary="Headless pDeadManPost watchdog matrix covering active-at-start posting, inactive-until-first-heartbeat behavior, stale heartbeat posting, live heartbeat suppression, custom heartbeat variables, post policies, invalid policy fallback, and typed deadflags.",
        proof="Checks mission-owned pMissionEval grades on exact deadflag variables, absent-post fail conditions, and alog posting counts for once/repeat/reset policy cases.",
        gifs=(
            ("Deadman Trip", "active_start_once_posts_pass", "pdeadmanpost-deadman-trip.gif"),
            ("Heartbeat Suppression", "heartbeat_before_dead_suppresses_pass", "pdeadmanpost-heartbeat-suppression.gif"),
        ),
        run="./zlaunch.sh --case=active_start_once_posts_pass --port_base=15800 10",
        notes=(
            "The harness writes case-specific pDeadManPost, uTimerScript, and pMissionEval blocks before each isolated launch.",
            "Suppression cases use fail conditions for deadflags, so absence is part of the mission-owned grade rather than only a harness-side string check.",
        ),
    ),
    Harness(
        slug="pspoofnode-unit",
        title="H01 pSpoofNode Unit",
        family="pSpoofNode",
        path="harnesses/pspoofnode_harnesses/H01-pspoofnode_unit",
        mission="missions/pspoofnode_missions/pspoofnode_unit",
        summary="Headless pSpoofNode matrix covering config-time and runtime spoof requests, default fields and startup ordering, generated names, moving contacts, duration expiry, name/group/contact cancellation, runtime normalization, color/type edge behavior, and malformed request rejection.",
        proof="Checks mission readiness with pMissionEval, then validates structured NODE_REPORT payload tokens and post-cancel/post-expiration absence from the generated alog.",
        gifs=(
            ("Static Spoof", "config_static_report_pass", "pspoofnode-static-spoof.gif"),
            ("Cancel By Name", "cancel_vname_pass", "pspoofnode-cancel-by-name.gif"),
        ),
        run="./zlaunch.sh --case=config_static_report_pass --port_base=16000 10",
        notes=(
            "NODE_REPORT contains dynamic time and position fields, so the harness uses narrow alog payload checks as a supplement to the mission-owned readiness grade.",
            "Cancellation and expiration cases use event-relative timestamps rather than absolute alog times, which keeps them stable across launch latency.",
        ),
    ),
    Harness(
        slug="utermcommand-unit",
        title="H01 uTermCommand Unit",
        family="uTermCommand",
        path="harnesses/utermcommand_harnesses/H01-utermcommand_unit",
        mission="missions/utermcommand_missions/utermcommand_unit",
        summary="Headless uTermCommand matrix covering numeric and string commands, arrow syntax, unique and ambiguous partial selection, duplicate key precedence, exact prefix wins, editing, config parsing, and unknown-command absence.",
        proof="Runs uTermCommand externally with deterministic stdin, then checks mission-owned pMissionEval grades for the exact variables that should or should not be posted.",
        gifs=(
            ("Numeric Command", "numeric_command_pass", "utermcommand-numeric-command.gif"),
            ("Arrow Syntax", "arrow_syntax_command_pass", "utermcommand-arrow-syntax.gif"),
        ),
        run="./zlaunch.sh --case=numeric_command_pass --port_base=16200 10",
        notes=(
            "The app is interactive, so the harness drives keystrokes through stdin and gives MOOS delivery time before sending q.",
            "The multi-command case uses separate deterministic sessions against one config because back-to-back piped commands can collapse into one terminal buffer.",
        ),
    ),
    Harness(
        slug="psearchgrid-unit",
        title="H01 pSearchGrid Unit",
        family="pSearchGrid",
        path="harnesses/psearchgrid_harnesses/H01-psearchgrid_unit",
        mission="missions/psearchgrid_missions/psearchgrid_unit",
        summary="Headless pSearchGrid matrix covering initial grid publication, local/global node-report deltas, repeated and multi-cell deltas, reset clearing semantics, outside-grid absence, full-grid reporting, custom output variables, single and list community filters, and malformed report rejection.",
        proof="Checks mission readiness with pMissionEval, then validates VIEW_GRID / VIEW_GRID_DELTA payload tokens, event-relative reset absence, and absent output from the generated alog.",
        gifs=(
            ("Grid Delta", "node_local_delta_pass", "psearchgrid-grid-delta.gif"),
            ("Full Grid Report", "full_grid_report_pass", "psearchgrid-full-grid-report.gif"),
        ),
        run="./zlaunch.sh --case=node_local_delta_pass --port_base=16400 10",
        notes=(
            "The harness keeps grid-payload checks narrow: it validates channel, label, cell var, and increment behavior without reimplementing the full convex-grid parser.",
            "Filter cases reflect the current source behavior, where match/ignore filters are applied to the MOOS message community.",
        ),
    ),
    Harness(
        slug="ufield-comms-unit",
        title="H01 uField Comms Unit",
        family="uField Communications",
        path="harnesses/ufield_comms_harnesses/H01-ufield_comms_unit",
        mission="missions/ufield_comms_missions/ufield_comms_unit",
        summary="Headless uFldNodeComms matrix covering range gates, critical range, shared reports, pulses, message payload forms, group filters, runtime mail, stale reports, and drop controls.",
        proof="Checks mission-owned delivery booleans plus targeted alog evidence for delivered, blocked, grouped, shared, pulsed, and runtime-adjusted communications.",
        gifs=(
            ("Baseline Broker Comms", "baseline_broker_comms_pass", "ufield-comms-baseline-broker.gif"),
            ("Runtime Range Extend", "runtime_range_extend_pass", "ufield-comms-runtime-range.gif"),
        ),
        run="./zlaunch.sh --case=baseline_broker_comms_pass --port_base=4000 10",
        notes=(
            "This harness keeps the two-vehicle field static so uFldNodeComms owns the communications verdict rather than vehicle motion.",
            "The cases combine mission-owned pMissionEval results with focused alog checks for payload fields that are awkward to normalize inside MOOS.",
        ),
    ),
    Harness(
        slug="ufield-broker-bridge",
        title="H02 uField Broker Bridge",
        family="uField Communications",
        path="harnesses/ufield_comms_harnesses/H02-ufield_broker_bridge",
        mission="missions/ufield_comms_missions/ufield_comms_unit",
        summary="Broker-level uFldNodeBroker/uFldShoreBroker matrix covering handshake acks, qbridge expansion, bridge token expansion, mediated node-message selection, vnode discovery, keyword mismatch status, and auto-bridge suppression.",
        proof="Checks node broker pings and acks, `UFSB_NODE_COUNT`, `NODE_PSHARE_VARS`, and exact pShare command evidence for shoreside and vehicle-side bridge setup.",
        gifs=(
            ("Broker Handshake", "broker_handshake_pass", "ufield-broker-handshake.gif"),
            ("Bridge Tokens", "shore_bridge_tokens_pass", "ufield-broker-bridge-tokens.gif"),
        ),
        run="./zlaunch.sh --case=broker_handshake_pass --port_base=4000 10",
        notes=(
            "This harness reuses the ufield_comms_unit stem and changes broker configuration only through case overlays or small generated mission edits.",
            "The cases intentionally supplement the mission grade with pShare command checks because bridge correctness is expressed as structured broker output.",
        ),
    ),
    Harness(
        slug="ufield-route-resilience",
        title="H03 uField Route Resilience",
        family="uField Communications",
        path="harnesses/ufield_comms_harnesses/H03-ufield_route_resilience",
        mission="missions/ufield_comms_missions/ufield_comms_unit",
        summary="Route-lifecycle matrix covering startup/runtime route parsing, dead-first-route blocking, secondary dead-route tolerance, runtime timing, duplicates, malformed route rejection, per-node recovery, numeric loopback routes, and shore-driven vnode discovery.",
        proof="Requires the mission-owned delivery or expected-fail grade, then checks exact `TRY_SHORE_HOST`, `PSHARE_CMD`, and `NODE_BROKER_ACK` evidence for route recovery, blocked first routes, duplicate suppression, invalid-route suppression, startup parser resilience, and vnode discovery.",
        gifs=(
            ("Runtime Route Recovery", "runtime_tryhost_recover_pass", "ufield-route-runtime-recovery.gif"),
            ("Shore VNode Discovery", "shore_vnode_discovery_recover_pass", "ufield-route-vnode-discovery.gif"),
        ),
        run="./zlaunch.sh --case=runtime_tryhost_recover_pass --port_base=4000 10",
        notes=(
            "This harness keeps the same static communication stem as H01/H02 but removes or perturbs route setup so broker retry and discovery behavior owns the outcome.",
            "The cases are intentionally integration-level because route resilience depends on pShare, `uFldNodeBroker`, and `uFldShoreBroker` interacting across separate MOOS communities.",
        ),
    ),
    Harness(
        slug="ufld-obstacle-sim-unit",
        title="H01 uFldObstacleSim Unit",
        family="uField Obstacle Simulation",
        path="harnesses/ufld_obstacle_sim_harnesses/H01-ufld_obstacle_sim_unit",
        mission="missions/ufld_obstacle_sim_missions/ufld_obstacle_sim_unit",
        summary="Headless uFldObstacleSim source-side matrix covering obstacle files, truth publications, visual output, point-sensor mode, refreshes, resets, range boundaries, and style parameters.",
        proof="Requires mission-owned completion, then checks exact alog evidence for `KNOWN_OBSTACLE`, `GIVEN_OBSTACLE`, `TRACKED_FEATURE_ALPHA`, `VIEW_POLYGON`, `VIEW_POINT`, `UFOS_MIN_RNG`, and reset/point-size mail.",
        gifs=(
            ("Fixed Field Publish", "fixed_field_publish_pass", "ufld-obstacle-sim-fixed-field.gif"),
            ("Point Sensor Mode", "post_points_inside_pass", "ufld-obstacle-sim-point-sensor.gif"),
        ),
        run="./zlaunch.sh --case=fixed_field_publish_pass --port_base=7600 10",
        notes=(
            "This harness tests the obstacle source/simulator side before obstacle consumers such as pObstacleMgr or BHV_AvoidObstacleV24 see the data.",
            "The cases intentionally supplement pMissionEval with alog checks because simulator correctness often appears as structured payload history rather than one stable current value.",
        ),
    ),
    Harness(
        slug="ufld-pathcheck-unit",
        title="H01 uFldPathCheck Unit",
        family="uFldPathCheck",
        path="harnesses/ufld_pathcheck_harnesses/H01-ufld_pathcheck_unit",
        mission="missions/ufield_app_missions/ufield_app_unit",
        summary="Headless uFldPathCheck matrix covering odometry, speed reports, trip resets, local reports, invalid reports, stationary tracks, multi-node accounting, and history-length speed windows.",
        proof="Checks mission-owned completion plus targeted alog evidence for `UPC_ODOMETRY_REPORT` and `UPC_SPEED_REPORT` values, including expected absence when reports are insufficient or invalid.",
        gifs=(
            ("Baseline Odometry", "odometry_baseline_pass", "ufld-pathcheck-baseline-odometry.gif"),
            ("Trip Reset", "trip_reset_pass", "ufld-pathcheck-trip-reset.gif"),
        ),
        run="./zlaunch.sh --case=odometry_baseline_pass --port_base=4300 10",
        notes=(
            "This harness keeps vehicle motion synthetic so uFldPathCheck owns the verdict rather than a simulator or behavior.",
            "The cases intentionally supplement the pMissionEval grade with exact alog checks because distance and speed are structured report payload fields.",
        ),
    ),
    Harness(
        slug="ufld-message-handler-unit",
        title="H01 uFldMessageHandler Unit",
        family="uFldMessageHandler",
        path="harnesses/ufld_message_handler_harnesses/H01-ufld_message_handler_unit",
        mission="missions/ufield_app_missions/ufield_app_unit",
        summary="Headless uFldMessageHandler matrix covering destination routing, strict addressing, invalid messages, numeric and string payload forwarding, summary counters, and good/bad flag macro expansion.",
        proof="Checks forwarded MOOS variables, rejected/invalid-message absence, `UMH_SUMMARY_MSGS` counters, and configured `msg_flag` / `bad_msg_flag` outputs from the mission alog.",
        gifs=(
            ("Accepted Message", "dest_specific_self_pass", "ufld-message-handler-accepted.gif"),
            ("Strict Reject", "strict_all_reject_pass", "ufld-message-handler-strict-reject.gif"),
        ),
        run="./zlaunch.sh --case=dest_specific_self_pass --port_base=4400 10",
        notes=(
            "This harness tests uFldMessageHandler directly instead of reaching it through broker-mediated field traffic.",
            "The cases keep routing inputs narrow so accepted, rejected, and invalid messages have distinct observable counters and forwarded-mail evidence.",
        ),
    ),
    Harness(
        slug="ufld-contact-range-sensor-unit",
        title="H01 uFldContactRangeSensor Unit",
        family="uFldContactRangeSensor",
        path="harnesses/ufld_contact_range_sensor_harnesses/H01-ufld_contact_range_sensor_unit",
        mission="missions/ufield_app_missions/ufield_app_unit",
        summary="Headless uFldContactRangeSensor matrix covering short/long report forms, ground-truth reporting, echo-type filters, sensor arcs, ping wait, pulse suppression, local reports, unknown requesters, and unlimited range overrides.",
        proof="Checks `CRS_RANGE_REPORT`, `CRS_RANGE_REPORT_<VNAME>`, `CRS_RANGE_REPORT_GT`, and `VIEW_RANGE_PULSE` presence, absence, count, and payload range values in the mission alog.",
        gifs=(
            ("Baseline Range", "baseline_short_report_pass", "ufld-contact-range-sensor-baseline.gif"),
            ("Arc Block", "sensor_arc_aft_block_pass", "ufld-contact-range-sensor-arc-block.gif"),
        ),
        run="./zlaunch.sh --case=baseline_short_report_pass --port_base=4500 10",
        notes=(
            "This harness scripts static contact geometry so uFldContactRangeSensor owns the range-report verdict.",
            "The cases avoid probabilistic range-boundary assertions and use deterministic filters, arcs, ping waits, and unlimited-distance overrides.",
        ),
    ),
    Harness(
        slug="ufld-beacon-range-sensor-unit",
        title="H01 uFldBeaconRangeSensor Unit",
        family="uFldBeaconRangeSensor",
        path="harnesses/ufld_beacon_range_sensor_harnesses/H01-ufld_beacon_range_sensor_unit",
        mission="missions/ufield_app_missions/ufield_app_unit",
        summary="Headless uFldBeaconRangeSensor matrix covering short/long report modes, ground-truth output, NODE_REPORT_LOCAL input, request/reply range gates, malformed and unknown requests, node-level unlimited range, node-specific ping wait, ping-payment policy, marker styling, and unsolicited frequency reports.",
        proof="Checks `BRS_RANGE_REPORT`, `BRS_RANGE_REPORT_<VNAME>`, `BRS_RANGE_REPORT_GT`, `VIEW_RANGE_PULSE`, and `VIEW_MARKER` presence, absence, counts, and payload range values in the mission alog.",
        gifs=(
            ("Baseline Beacon Range", "request_short_report_pass", "ufld-beacon-range-sensor-baseline.gif"),
            ("Ground Truth Report", "brs_ground_truth_uniform_zero_pass", "ufld-beacon-range-sensor-ground-truth.gif"),
        ),
        run="./zlaunch.sh --case=request_short_report_pass --port_base=4000 10",
        notes=(
            "This harness scripts static node and beacon geometry so uFldBeaconRangeSensor owns the range-report verdict.",
            "The cases mirror the contact-range sensor style where useful while staying beacon-specific around marker output, beacon IDs, and node range overrides.",
        ),
    ),
    Harness(
        slug="ufld-collision-detect-unit",
        title="H01 uFldCollisionDetect Unit",
        family="uFldCollisionDetect",
        path="harnesses/ufld_collision_detect_harnesses/H01-ufld_collision_detect_unit",
        mission="missions/ufield_app_missions/ufield_app_unit",
        summary="Headless uFldCollisionDetect matrix covering collision, near-miss, clear encounter reporting and suppression, encounter-range blocking, closest-range publish suppression, reset, pulse and ring suppression, range normalization, group filters, conditions, and configured collision/near/encounter flags.",
        proof="Checks `UCD_REPORT`, `COLLISION_TOTAL`, `NEAR_MISS_TOTAL`, `ENCOUNTER_TOTAL`, closest-range outputs, pulse absence, and configured flag mail including contact-density macros from scripted node-report encounters.",
        gifs=(
            ("Collision Event", "collision_event_pass", "ufld-collision-detect-collision-event.gif"),
            ("Condition Gate", "condition_allows_pass", "ufld-collision-detect-condition-gate.gif"),
        ),
        run="./zlaunch.sh --case=collision_event_pass --port_base=4000 10",
        notes=(
            "This harness uses controlled report sequences instead of moving vehicles so uFldCollisionDetect owns the threshold and filter verdict.",
            "Blocked cases assert absence of `UCD_REPORT` because the app may still publish zero-valued status and closest-range state while suppressing encounter events.",
        ),
    ),
    Harness(
        slug="ufld-collob-detect-unit",
        title="H01 uFldCollObDetect Unit",
        family="uFldCollObDetect",
        path="harnesses/ufld_collob_detect_harnesses/H01-ufld_collob_detect_unit",
        mission="missions/ufield_app_missions/ufield_app_unit",
        summary="Headless uFldCollObDetect matrix covering obstacle collision flags, near-miss flags, encounter-only flags, strict threshold boundaries, normalized range ordering, numeric distance flags, global minimum distance, invalid obstacle suppression, aged/fresh/named obstacle clearing, and macro flag output.",
        proof="Checks `COD_ENCOUNTER`, `COD_NEAR`, `COD_COLLISION`, `COD_ENCOUNTER_DIST`, `OB_GLOBAL_MIN`, and configured macro flag mail from scripted known-obstacle and node-report geometry.",
        gifs=(
            ("Obstacle Collision", "collision_flag_pass", "ufld-collob-detect-obstacle-collision.gif"),
            ("Encounter Only", "encounter_only_flag_pass", "ufld-collob-detect-encounter-only.gif"),
        ),
        run="./zlaunch.sh --case=collision_flag_pass --port_base=4000 10",
        notes=(
            "This harness feeds `KNOWN_OBSTACLE` directly so obstacle-consumer behavior is isolated from obstacle-source apps.",
            "Distance cases use points just outside the polygon boundary so collision, near-miss, and encounter-only thresholds remain distinct and deterministic.",
        ),
    ),
    Harness(
        slug="ufld-scope-unit",
        title="H01 uFldScope Unit",
        family="uFldScope",
        path="harnesses/ufld_scope_harnesses/H01-ufld_scope_unit",
        mission="missions/ufield_app_missions/ufield_app_unit",
        summary="Headless uFldScope matrix covering appcast table construction, field aliases, same-key row replacement including blank overwrites, multiple vehicle rows, invalid-scope recovery, missing fields, and missing key values.",
        proof="Checks `proc=uFldScope` APPCAST payloads specifically, including table headers, rows, replacement values, blank cells, blank-key rows, and ignored invalid scope lines.",
        gifs=(
            ("Scope Table", "appcast_table_pass", "ufld-scope-table.gif"),
            ("Row Replacement", "update_replaces_same_key_pass", "ufld-scope-row-replacement.gif"),
        ),
        run="./zlaunch.sh --case=appcast_table_pass --port_base=4000 10",
        notes=(
            "This harness uses appcast payload evidence because uFldScope's primary observable behavior is the rendered scope table.",
            "Evidence is filtered to `proc=uFldScope` appcasts so pMissionEval's own appcasts cannot accidentally satisfy table checks.",
        ),
    ),
    Harness(
        slug="constant-depth-motion",
        title="H01 Constant Depth Motion",
        family="Depth Behavior",
        path="harnesses/depth_behavior_harnesses/H01-constant_depth_motion",
        mission="missions/depth_behavior_missions/depth_behavior_motion",
        summary="BHV_ConstantDepth motion matrix covering held depth, surfacing, negative-depth clipping, shape parameters, runtime updates, malformed update preservation, finite-duration completion, malformed config, missing depth mail/domain, and actuator authority failures.",
        proof="Checks bridged NAV_DEPTH, DEPTH_MISMATCH, behavior error evidence, and elevator/depth-control signals from pHelmIvP driving pMarinePIDV22 and uSimMarineV22.",
        gifs=(
            ("Held Depth", "constant_depth_hold_pass", "constant-depth-hold.gif"),
            ("Runtime Update", "constant_depth_update_pass", "constant-depth-update.gif"),
        ),
        run="./zlaunch.sh --case=constant_depth_hold_pass --gui 10",
        notes=(
            "This harness keeps the horizontal waypoint leg as background motion so BHV_ConstantDepth owns the vertical-control verdict.",
            "Expected-fail cases prove the evaluator catches invalid configuration, missing depth inputs, missing depth domain, and disabled vertical-control authority.",
        ),
    ),
    Harness(
        slug="goto-depth-motion",
        title="H02 GoToDepth Motion",
        family="Depth Behavior",
        path="harnesses/depth_behavior_harnesses/H02-goto_depth_motion",
        mission="missions/depth_behavior_missions/depth_behavior_motion",
        summary="BHV_GoToDepth motion matrix covering multi-level sequences, repeat behavior and exhaustion, vertical target crossings, zero-delta arrivals, single-level targets, malformed update preservation, unsupported perpetual config, invalid sequences, negative depths, malformed repeat values, missing depth mail, and missing depth domain.",
        proof="Checks bridged NAV_DEPTH, behavior-owned arrival counters, depth-band evidence, and configuration/error evidence from the simulated UUV stack.",
        gifs=(
            ("Depth Sequence", "goto_depth_sequence_pass", "goto-depth-sequence.gif"),
            ("Crossing Arrivals", "goto_depth_crossing_pass", "goto-depth-crossing.gif"),
        ),
        run="./zlaunch.sh --case=goto_depth_sequence_pass --gui 10",
        notes=(
            "Finite sequence cases grade arrival and depth evidence instead of treating post-completion behavior quieting as the primary signal.",
            "Expected-fail cases isolate invalid sequence inputs and missing vertical-state conditions.",
        ),
    ),
    Harness(
        slug="periodic-surface-motion",
        title="H03 Periodic Surface Motion",
        family="Depth Behavior",
        path="harnesses/depth_behavior_harnesses/H03-periodic_surface_motion",
        mission="missions/depth_behavior_missions/depth_behavior_motion",
        summary="BHV_PeriodicSurface motion matrix covering surfacing cycles, status variables, wait windows, timeout reset behavior, mark-variable resets, acomms extensions, ascent-grade branches, current-speed mode, invalid period/ascent/status/acomms settings, missing nav mail, and missing depth domain.",
        proof="Checks surfaced-depth evidence, timeout/reset evidence, behavior status variables, vertical actuator evidence, and mission-owned error outcomes.",
        gifs=(
            ("Surfacing Cycle", "periodic_surface_pass", "periodic-surface-cycle.gif"),
            ("Wait Window", "periodic_surface_wait_window_pass", "periodic-surface-wait-window.gif"),
        ),
        run="./zlaunch.sh --case=periodic_surface_pass --gui 10",
        notes=(
            "Vehicle-side overlays own the behavior timing inputs, including acomms extension, so the evaluated app receives the same mail as it would in a live vehicle community.",
            "Expected-fail cases distinguish malformed behavior parameters from missing navigation or domain support.",
        ),
    ),
    Harness(
        slug="max-depth-motion",
        title="H04 Max Depth Motion",
        family="Depth Behavior",
        path="harnesses/depth_behavior_harnesses/H04-max_depth_motion",
        mission="missions/depth_behavior_missions/depth_behavior_motion",
        summary="BHV_MaxDepth motion matrix covering max-depth guarding, zero-depth clamps, negative command clipping, tight and zero tolerance, unconstrained shallow commands, malformed max-depth/tolerance settings, unsupported ascent-field config, missing depth mail, and missing depth domain.",
        proof="Checks bridged NAV_DEPTH limits, slack/mismatch telemetry, behavior error evidence, and elevator response under commanded over-depth pressure.",
        gifs=(
            ("Max Depth Guard", "max_depth_guard_pass", "max-depth-guard.gif"),
            ("Unconstrained Shallow", "max_depth_unconstrained_shallow_pass", "max-depth-unconstrained.gif"),
        ),
        run="./zlaunch.sh --case=max_depth_guard_pass --gui 10",
        notes=(
            "This harness grades the guard behavior while another behavior creates pressure to go deeper than the configured limit.",
            "Expected-fail cases prove both bad configuration and missing vertical state are caught by the mission evaluator.",
        ),
    ),
    Harness(
        slug="min-altitude-motion",
        title="H05 Min Altitude Motion",
        family="Depth Behavior",
        path="harnesses/depth_behavior_harnesses/H05-min_altitude_motion",
        mission="missions/depth_behavior_missions/depth_behavior_motion",
        summary="BHV_MinAltitude motion matrix covering bottom-clearance guarding, shallow-bottom response, unconstrained deep-bottom behavior, clearance boundary behavior, zero-minimum behavior, zero altitude failures, invalid configuration, missing nav inputs, and noncritical missing-altitude handling.",
        proof="Checks bridged NAV_DEPTH and NAV_ALTITUDE, min-altitude clearance bands, behavior error evidence, and elevator response under simulated bottom-clearance pressure.",
        gifs=(
            ("Min Altitude Guard", "min_altitude_guard_pass", "min-altitude-guard.gif"),
            ("Deep Bottom", "min_altitude_unconstrained_deep_bottom_pass", "min-altitude-unconstrained.gif"),
        ),
        run="./zlaunch.sh --case=min_altitude_guard_pass --gui 10",
        notes=(
            "This harness isolates bottom-clearance behavior from the other depth behaviors while reusing the same simulated UUV stack.",
            "The noncritical missing-altitude case documents the configured warning-only mode separately from critical guard failures.",
        ),
    ),
    Harness(
        slug="colregs-classification",
        title="H01 COLREGS Classification",
        family="COLREGS",
        path="harnesses/colregs_harnesses/H01-colregs_classification",
        mission="missions/colregs_missions/colregs_unit",
        summary="Canonical two-vessel COLREGS classification suite for BHV_AvdColregsV22.",
        proof="Checks expected mode/index selection across head-on, crossing, overtaking, and overtaken encounter geometry.",
        gifs=(
            ("Head-on Classification", "head_on_colregs_pass", "colregs-classification-head-on.gif"),
            ("Crossing Give-way", "crossing_starboard_giveway_pass", "colregs-classification-crossing.gif"),
        ),
        run="./zlaunch.sh --case=head_on_colregs_pass --gui 10",
        notes=(
            "This is the first COLREGS layer: select the correct rule family before judging maneuver quality.",
            "Cases cover canonical head-on, crossing, overtaking, and overtaken-vessel geometry.",
        ),
    ),
    Harness(
        slug="colregs-thresholds",
        title="H02 COLREGS Thresholds",
        family="COLREGS",
        path="harnesses/colregs_harnesses/H02-colregs_thresholds",
        mission="missions/colregs_missions/colregs_unit",
        summary="Geometry-edge suite for classification thresholds and near-boundary COLREGS behavior.",
        proof="Uses below, edge, above, mirrored, and family-grouped probes to catch subtle threshold regressions.",
        gifs=(
            ("Give-way Bow Distance", "giveway_bowdist_edge_pass", "colregs-thresholds-giveway-bowdist.gif"),
            ("Overtaking Threshold", "overtaking_thresh_edge_pass", "colregs-thresholds-overtaking-triplet.gif"),
        ),
        run="./zlaunch.sh --group=headon --gui 10",
        notes=(
            "This harness owns near-boundary geometry so H01 can stay focused on stable canonical cases.",
            "The below, edge, and above naming pattern makes threshold regressions easier to localize.",
        ),
    ),
    Harness(
        slug="colregs-execution",
        title="H03 COLREGS Execution",
        family="COLREGS",
        path="harnesses/colregs_harnesses/H03-colregs_execution",
        mission="missions/colregs_missions/colregs_unit",
        summary="Execution-quality layer for COLREGS cases after classification is known to be correct.",
        proof="Runs through completion and checks realized CPA bands, final side relationship, collisions, and loose wall-time envelopes.",
        gifs=(
            ("Head-on Resolution", "head_on_execution_pass", "colregs-execution-head-on.gif"),
            ("Overtaken Midrange", "overtaken_starboard_standon_midrange_execution_pass", "colregs-execution-overtaken-midrange.gif"),
            ("Crossing Give-way", "crossing_starboard_giveway_execution_pass", "colregs-execution-crossing-giveway.gif"),
        ),
        run="./zlaunch.sh --case=head_on_execution_pass --gui 10",
        notes=(
            "This layer assumes classification is correct and then checks whether the completed maneuver is acceptable.",
            "The key evidence is realized closest approach, relative side outcome, timing envelope, and zero collisions.",
        ),
    ),
    Harness(
        slug="colregs-parameters",
        title="H04 COLREGS Parameters",
        family="COLREGS",
        path="harnesses/colregs_harnesses/H04-colregs_parameters",
        mission="missions/colregs_missions/colregs_unit",
        summary="Parameter-regression suite varying one BHV_AvdColregsV22 knob at a time.",
        proof="Keeps trusted geometry fixed while proving selected tuning changes remain stable or change in one expected way.",
        gifs=(
            ("Bow Distance Threshold", "giveway_bow_dist_high_pass", "colregs-parameters-bow-distance.gif"),
            ("Turn Radius Branch", "turn_radius_high_pass", "colregs-parameters-turn-radius.gif"),
        ),
        run="./zlaunch.sh --group=min_util_cpa_dist --gui 10",
        notes=(
            "This harness changes behavior parameters while keeping the underlying geometry controlled.",
            "The goal is to make tuning changes safe by proving expected stability or expected change.",
        ),
    ),
    Harness(
        slug="collision-behavior-motion",
        title="H01 Avoid-Collision Behavior",
        family="Behavior Correctness",
        path="harnesses/collision_behavior_harnesses/H01-collision_behavior_motion",
        mission="missions/collision_behavior_missions/collision_behavior_motion",
        summary="Moving correctness harness for BHV_AvoidCollision independent of app-level contact-manager assertions.",
        proof="Checks alert request, contact info, per-contact outputs, behavior lifecycle, resolution, arrival, and collision-free transit.",
        gifs=(
            ("Head-on Resolve", "head_on_resolve_pass", "collision-behavior-head-on-resolve.gif"),
            ("No Alert Request Fail", "no_alert_request_fail", "collision-behavior-no-alert-fail.gif"),
            ("Baseline Resolve", "default_resolve_pass", "collision-behavior-default-resolve.gif"),
        ),
        run="./zlaunch.sh --case=head_on_resolve_pass --gui 10",
        notes=(
            "This harness isolates the avoid-collision behavior contract from contact-manager implementation details.",
            "A case can fail even without a collision when the required behavior lifecycle or resolution evidence is missing.",
        ),
    ),
    Harness(
        slug="obstacle-behavior-motion",
        title="H01 Avoid-Obstacle Behavior",
        family="Behavior Correctness",
        path="harnesses/obstacle_behavior_harnesses/H01-obstacle_behavior_motion",
        mission="missions/obstacle_behavior_missions/obstacle_behavior_motion",
        summary="Moving correctness harness for BHV_AvoidObstacleV24 with deterministic obstacle-manager input.",
        proof="Checks auto-request, obstacle alert receipt, behavior-owned range/CPA flags, resolution, arrival, encounters, and expected fail modes.",
        gifs=(
            ("Default Auto Request", "default_auto_request_pass", "obstacle-behavior-default-auto-request.gif"),
            ("Sequential Obstacle Alerts", "two_obstacles_clean_pass", "obstacle-behavior-two-obstacles.gif"),
            ("Avoid Disabled Fail", "avoid_disabled_fail", "obstacle-behavior-avoid-disabled.gif"),
        ),
        run="./zlaunch.sh --case=two_obstacles_clean_pass --gui 10",
        notes=(
            "This harness isolates the avoid-obstacle behavior contract while keeping obstacle-manager input deterministic.",
            "Helper-flag cases check behavior-specific observability in addition to mission outcome.",
        ),
    ),
    Harness(
        slug="opregion-safety",
        title="H01 OpRegion Safety",
        family="Behavior Correctness",
        path="harnesses/opregion_harnesses/H01-opregion_safety",
        mission="missions/opregion_missions/opregion_motion",
        summary="Moving safety harness for BHV_OpRegionV24 save regions, halt regions, timing gates, reset, and runtime region updates.",
        proof="Checks nominal containment, save recovery, generated buffers, halt breaches, entry/exit timing gates, reset handling, max-time failure, and dynamic region enforcement.",
        gifs=(
            ("Save Recovery", "save_recover_pass", "opregion-safety-save-recover.gif"),
            ("Dynamic Region Update", "dynamic_region_update_pass", "opregion-safety-dynamic-update.gif"),
            ("Entry Gate", "entry_gate_start_outside_pass", "opregion-safety-entry-gate.gif"),
        ),
        run="./zlaunch.sh --case=save_recover_pass --gui 10",
        notes=(
            "This harness isolates the operating-region safety contract around save/halt envelopes and timing gates.",
            "Expected-fail cases prove that true halt, max-time, or configured save-buffer breaches are caught by the mission verdict.",
        ),
    ),
    Harness(
        slug="waypoint-behavior-motion",
        title="H01 Waypoint Behavior",
        family="Behavior Correctness",
        path="harnesses/waypoint_behavior_harnesses/H01-waypoint_behavior_motion",
        mission="missions/waypoint_behavior_missions/waypoint_behavior_motion",
        summary="Moving correctness harness for BHV_Waypoint route traversal, runtime point updates, cycle flags, capture modes, and malformed inputs.",
        proof="Checks completion, waypoint-hit flags, end flags, repeat/cycle handling, dynamic route updates, capture/slip/line modes, status variables, and expected invalid-input failures.",
        gifs=(
            ("Multi-point Sequence", "multi_point_sequence_pass", "waypoint-behavior-multipoint.gif"),
            ("Dynamic Route Update", "xpoints_update_pass", "waypoint-behavior-dynamic-update.gif"),
            ("Repeat Forever Cycle", "repeat_forever_cycle_pass", "waypoint-behavior-repeat-forever.gif"),
        ),
        run="./zlaunch.sh --case=multi_point_sequence_pass --gui 10",
        notes=(
            "This harness keeps the vehicle on a short route while checking behavior-owned waypoint completion evidence.",
            "Runtime update cases prove that the behavior can accept, reject, or preserve traversal state across point updates.",
        ),
    ),
    Harness(
        slug="loiter-behavior-motion",
        title="H01 Loiter Behavior",
        family="Behavior Correctness",
        path="harnesses/loiter_behavior_harnesses/H01-loiter_behavior_motion",
        mission="missions/loiter_behavior_missions/loiter_behavior_motion",
        summary="Moving correctness harness for BHV_Loiter acquisition, polygon variants, center updates, speed modes, reports, and invalid inputs.",
        proof="Checks loiter mode, acquisition state, polygon distance/ETA, bearing accumulation, suffixed outputs, runtime polygon updates, and expected malformed-polygon failures.",
        gifs=(
            ("Radial Clockwise", "radial_clockwise_pass", "loiter-behavior-radial.gif"),
            ("Runtime Radius Expand", "mod_poly_rad_expand_pass", "loiter-behavior-radius-expand.gif"),
            ("Center Assign Pair", "center_assign_pair_pass", "loiter-behavior-center-assign-pair.gif"),
        ),
        run="./zlaunch.sh --case=radial_clockwise_pass --gui 10",
        notes=(
            "This harness checks both stable loiter acquisition and the output signals that make loiter state observable in CI.",
            "Dynamic center and polygon cases cover runtime geometry changes without copying the stem mission.",
        ),
    ),
    Harness(
        slug="stationkeep-behavior-motion",
        title="H01 StationKeep Behavior",
        family="Behavior Correctness",
        path="harnesses/stationkeep_behavior_harnesses/H01-stationkeep_behavior_motion",
        mission="missions/stationkeep_behavior_missions/stationkeep_behavior_motion",
        summary="Moving correctness harness for BHV_StationKeep station points, radii, hibernation, runtime retargeting, speed settings, warnings, and invalid inputs.",
        proof="Checks station distance, mode transitions, radius/speed updates, hibernation seek/settle behavior, warning recovery, visual hints, and expected parameter failures.",
        gifs=(
            ("Static Station", "static_station_pass", "stationkeep-behavior-static.gif"),
            ("Hibernation Settle", "hibernation_settle_pass", "stationkeep-behavior-hibernation.gif"),
            ("Runtime Radius Expand", "radius_update_expand_pass", "stationkeep-behavior-radius-expand.gif"),
        ),
        run="./zlaunch.sh --case=static_station_pass --gui 10",
        notes=(
            "This harness grades the station-keeping behavior through mode and distance outputs rather than only final vehicle position.",
            "Runtime retargeting and hibernation cases make the behavior's state transitions explicit for regression testing.",
        ),
    ),
    Harness(
        slug="trail-behavior-motion",
        title="H01 Trail Behavior",
        family="Behavior Correctness",
        path="harnesses/trail_behavior_harnesses/H01-trail_behavior_motion",
        mission="missions/trail_behavior_missions/trail_behavior_motion",
        summary="Two-vehicle moving correctness harness for BHV_Trail relative/absolute trailing geometry, runtime updates, pursuit relevance, and missing-contact paths.",
        proof="Checks trail distance, relevance, range, pursuit state, update handling, extrapolation, missing-contact warnings/failures, and malformed parameter rejection.",
        gifs=(
            ("Relative Port Trail", "relative_port_pass", "trail-behavior-relative-port.gif"),
            ("Lead Turn Angle Update", "lead_turn_angle_update_pass", "trail-behavior-lead-turn-angle-update.gif"),
            ("Runtime Range Extend", "runtime_range_extend_pass", "trail-behavior-runtime-range-extend.gif"),
        ),
        run="./zlaunch.sh --case=static_trail_pass --gui 10",
        notes=(
            "This harness uses a target vehicle and a chaser so trailing geometry is tested against moving contact state.",
            "Relevance and runtime-update cases prove the behavior can turn pursuit on/off and reframe the desired trail point.",
        ),
    ),
    Harness(
        slug="convoy-behavior-motion",
        title="H01 Convoy Behavior",
        family="Behavior Correctness",
        path="harnesses/convoy_behavior_harnesses/H01-convoy_behavior_motion",
        mission="missions/convoy_behavior_missions/convoy_behavior_motion",
        summary="Two-vehicle moving correctness harness for BHV_Convoy mark queues, following geometry, speed branches, runtime updates, warnings, and missing-contact failures.",
        proof="Checks queue length, track length, max range, average spacing, chaser/target speed aliases, visual breadcrumbs, geometry recovery, runtime updates, and expected parameter failures.",
        gifs=(
            ("Static Convoy", "static_convoy_pass", "convoy-behavior-static.gif"),
            ("Angled Entry", "angled_entry_pass", "convoy-behavior-angled-entry.gif"),
            ("Lead S-turn", "lead_s_turn_pass", "convoy-behavior-lead-s-turn.gif"),
        ),
        run="./zlaunch.sh --case=static_convoy_pass --gui 10",
        notes=(
            "This harness uses a leader/follower pair so queue and speed-branch outputs can be graded during real motion.",
            "Geometry-entry cases check recovery into convoy following from less tidy starting conditions.",
        ),
    ),
    Harness(
        slug="cutrange-behavior-motion",
        title="H01 CutRange Behavior",
        family="Behavior Correctness",
        path="harnesses/cutrange_behavior_harnesses/H01-cutrange_behavior_motion",
        mission="missions/cutrange_behavior_missions/cutrange_behavior_motion",
        summary="Two-vehicle moving correctness harness for BHV_CutRange pursuit, give-up behavior, relevance, runtime updates, and malformed inputs.",
        proof="Checks range closure, pursue/give-up flags, target geometry branches, relevance gates, warning recovery, runtime updates, and expected configuration failures.",
        gifs=(
            ("Head-on Closure", "headon_cutrange_pass", "cutrange-behavior-headon.gif"),
            ("Crossing Closure", "crossing_cutrange_pass", "cutrange-behavior-crossing.gif"),
            ("S-turn Target", "s_turn_target_pass", "cutrange-behavior-s-turn.gif"),
        ),
        run="./zlaunch.sh --case=static_cutrange_pass --gui 10",
        notes=(
            "This harness uses a chaser/target pair so range reduction is graded against live contact geometry instead of a static input.",
            "Runtime update and give-up cases make the behavior's pursuit state explicit enough for CI to catch subtle regressions.",
        ),
    ),
    Harness(
        slug="fixedturn-behavior-motion",
        title="H01 FixedTurn Behavior",
        family="Behavior Correctness",
        path="harnesses/fixedturn_behavior_harnesses/H01-fixedturn_behavior_motion",
        mission="missions/fixedturn_behavior_missions/fixedturn_behavior_motion",
        summary="Moving correctness harness for BHV_FixedTurn direction, scheduled turns, runtime updates, timeout completion, and invalid turn configuration.",
        proof="Checks fixed-turn completion, final heading bands, turn time/distance, scheduled-turn flags, runtime update recovery, and behavior error state.",
        gifs=(
            ("Starboard 90", "starboard_90_pass", "fixedturn-behavior-starboard-90.gif"),
            ("Port 360", "port_360_pass", "fixedturn-behavior-port-360.gif"),
            ("Turn Spec Sequence", "turn_spec_sequence_pass", "fixedturn-behavior-turn-spec-sequence.gif"),
        ),
        run="./zlaunch.sh --case=starboard_90_pass --gui 10",
        notes=(
            "This harness starts with a short approach leg and then activates the fixed-turn behavior so turn completion can be measured from mission-owned outputs.",
            "The scheduled-turn and runtime-update cases exercise configuration paths that are hard to prove from one static mission.",
        ),
    ),
    Harness(
        slug="periodic-speed-behavior-motion",
        title="H01 PeriodicSpeed Behavior",
        family="Behavior Correctness",
        path="harnesses/periodic_speed_behavior_harnesses/H01-periodic_speed_behavior_motion",
        mission="missions/periodic_speed_behavior_missions/periodic_speed_behavior_motion",
        summary="Moving correctness harness for BHV_PeriodicSpeed lazy/busy cycling, reset behavior, alias parameters, zero-speed windows, and invalid configuration.",
        proof="Checks periodic speed timer outputs, busy-count transitions, observed NAV_SPEED response, reset-on-reactivation behavior, alias acceptance, and expected malformed-configuration failures.",
        gifs=(
            ("Baseline Lazy/Busy Cycle", "baseline_cycle_pass", "periodic-speed-baseline-cycle.gif"),
            ("Reset False Re-Enable", "reset_false_visual_pass", "periodic-speed-reset-false-reenable.gif"),
        ),
        run="./zlaunch.sh --case=baseline_cycle_pass --gui --port_base=15000 10",
        notes=(
            "This harness keeps heading control separate so BHV_PeriodicSpeed owns the evaluated speed contract.",
            "The first case matrix focuses on deterministic status variables before adding more timing-sensitive speed-profile assertions.",
        ),
    ),
    Harness(
        slug="memoryturnlimit-behavior-motion",
        title="H01 MemoryTurnLimit Behavior",
        family="Behavior Correctness",
        path="harnesses/memoryturnlimit_behavior_harnesses/H01-memoryturnlimit_behavior_motion",
        mission="missions/memoryturnlimit_behavior_missions/memoryturnlimit_behavior_motion",
        summary="Moving correctness harness for BHV_MemoryTurnLimit recent-heading averaging, turn-window damping, runtime limiter updates, speed scaling, and malformed configuration.",
        proof="Checks memory-heading averages, ownship heading response, heading mismatch, speed evidence, runtime update acceptance, and expected malformed-configuration failures.",
        gifs=(
            ("Tight Turn Window", "tight_window_pass", "memoryturnlimit-behavior-tight-window.gif"),
            ("Runtime Range Widen", "runtime_widen_range_pass", "memoryturnlimit-behavior-runtime-widen.gif"),
        ),
        run="./zlaunch.sh --case=baseline_memory_pass --gui --port_base=15000 10",
        notes=(
            "This harness applies a sustained constant-heading turn demand so the memory limiter owns the evaluated course damping effect.",
            "The tight, relaxed, runtime-update, and speed-scaled cases prove that limiter settings produce distinct, mission-visible heading outcomes.",
        ),
    ),
    Harness(
        slug="timer-behavior-motion",
        title="H01 Timer Behavior",
        family="Behavior Correctness",
        path="harnesses/timer_behavior_harnesses/H01-timer_behavior_motion",
        mission="missions/timer_behavior_missions/timer_behavior_motion",
        summary="Moving correctness harness for BHV_Timer idle/running duration counters, custom status variable names, suffix handling, and invalid timer status configuration.",
        proof="Checks timer-posted idle and running counters, custom/default status outputs, active-at-start timing, and expected malformed-configuration failures.",
        gifs=(
            ("Pause/Resume Counters", "pause_resume_pass", "timer-behavior-pause-resume.gif"),
            ("Runtime Status Update", "runtime_update_pass", "timer-behavior-runtime-update.gif"),
        ),
        run="./zlaunch.sh --case=baseline_idle_running_pass --gui --port_base=15000 10",
        notes=(
            "This harness keeps vehicle motion simple while BHV_Timer owns the evaluated idle/running duration contract.",
            "The cases focus on status publication names and timing transitions because BHV_Timer intentionally returns no IvP function.",
        ),
    ),
    Harness(
        slug="testfailure-behavior-unit",
        title="H01 TestFailure Behavior",
        family="Behavior Correctness",
        path="harnesses/testfailure_behavior_harnesses/H01-testfailure_behavior_unit",
        mission="missions/testfailure_behavior_missions/testfailure_behavior_unit",
        summary="Headless unit harness for BHV_TestFailure completion-triggered crash, burn, hang alias, default burn timing, malformed burn timing, negative/zero burn timing, and unsupported failure-type default behavior.",
        proof="Checks completion endflags, pHelmIvP iteration-gap evidence for wall-clock burn/hang stalls, immediate-completion burn variants, process-watch evidence for crash/default-crash outcomes, and a non-completing armed baseline.",
        gifs=(
            ("Burn Gap Detection", "burn_gap_detected_pass", "testfailure-burn-gap.gif"),
            ("Crash Process Loss", "crash_on_complete_fail", "testfailure-crash-process-loss.gif"),
        ),
        run="./zlaunch.sh --case=burn_gap_detected_pass --port_base=15000 10",
        notes=(
            "This harness seeds only the minimum helm navigation state required for behavior evaluation; it does not simulate vehicle motion.",
            "Crash cases grade on pHelmIvP process loss, while burn and hang cases grade on direct PHELMIVP_ITER_GAP evidence because uLoadWatch does not classify this completion stall as a breach.",
        ),
    ),
    Harness(
        slug="hostinfo-unit",
        title="H01 pHostInfo Unit",
        family="Utility Infrastructure",
        path="harnesses/hostinfo_harnesses/H01-hostinfo_unit",
        mission="missions/hostinfo_missions/hostinfo_unit",
        summary="Headless utility harness for pHostInfo host IP, MOOSDB port, and PHI_HOST_INFO route reporting.",
        proof="Checks forced host IPs and exact valid, multi-route, mixed, non-UDP, and invalid pShare route normalization in the posted PHI_HOST_INFO payload.",
        gifs=(
            ("pShare Route Payload", "hostinfo_pshare_route_pass", "hostinfo-pshare-route-payload.gif"),
            ("Invalid Route Omitted", "hostinfo_invalid_pshare_route_pass", "hostinfo-invalid-route-omitted.gif"),
        ),
        run="./zlaunch.sh --jobs=3 --port_base=11000 10",
        notes=(
            "This is a shoreside-only infrastructure harness: no vehicle or behavior stack is needed to prove the host-info publications.",
            "The route cases exact-check the generated payload so malformed route filtering and non-UDP route preservation are visible regressions.",
        ),
    ),
    Harness(
        slug="loadwatch-unit",
        title="H01 uLoadWatch Unit",
        family="Utility Infrastructure",
        path="harnesses/loadwatch_harnesses/H01-loadwatch_unit",
        mission="missions/loadwatch_missions/loadwatch_unit",
        summary="Headless utility harness for uLoadWatch threshold detection, near-breach counters, hard-breach counters, and trigger holdoff behavior.",
        proof="Checks load near/hard breach counters, near and hard threshold boundaries, low-threshold ignore behavior, clamped near-threshold behavior, breach-trigger holdoff, app-specific threshold matching, and threshold-name case sensitivity.",
        gifs=(
            ("Near-Breach Band", "loadwatch_near_breach_pass", "loadwatch-near-breach-band.gif"),
            ("Trigger Holdoff", "loadwatch_trigger_second_breaches_pass", "loadwatch-trigger-holdoff.gif"),
        ),
        run="./zlaunch.sh --jobs=3 --port_base=11200 10",
        notes=(
            "This is a shoreside-only infrastructure harness: scripted DB_UPTIME mail feeds uLoadWatch without depending on process-watch or host-info state.",
            "The cases isolate threshold semantics by changing only uLoadWatch config and timed DB_UPTIME publications.",
        ),
    ),
    Harness(
        slug="processwatch-unit",
        title="H01 uProcessWatch Unit",
        family="Utility Infrastructure",
        path="harnesses/processwatch_harnesses/H01-processwatch_unit",
        mission="missions/processwatch_missions/processwatch_unit",
        summary="Headless utility harness for uProcessWatch process-presence reporting, mapped posts, full summaries, events, and missing-process detection.",
        proof="Checks process custom posts, multi-process summaries, summary post mapping, full-summary mapping, event mapping, and expected missing-process failure.",
        gifs=(
            ("Mapped Summary", "processwatch_post_mapping_pass", "processwatch-mapped-summary.gif"),
            ("AWOL Detection", "processwatch_missing_awol_fail", "processwatch-awol-detection.gif"),
        ),
        run="./zlaunch.sh --jobs=3 --port_base=11600 10",
        notes=(
            "This is a shoreside-only infrastructure harness: pHostInfo and uLoadWatch are launched as watched peers, not as graded utilities.",
            "The missing-process case is expected to fail and waits long enough to cross uProcessWatch's built-in AWOL delay.",
        ),
    ),
    Harness(
        slug="pshare-unit",
        title="H01 pShare Unit",
        family="Utility Infrastructure",
        path="harnesses/pshare_harnesses/H01-pshare_unit",
        mission="missions/pshare_missions/pshare_unit",
        summary="Headless two-community harness for pShare direct, renamed, wildcard, source-qualified wildcard, multicast, duration-limited, shorthand, fanout, command-line, and frequency-throttled routes.",
        proof="Checks routed mail arriving in the receiver MOOSDB under direct and renamed destinations, max_shares limiting, wildcard source matching, wildcard source-app qualifiers, multicast aliases, wildcard destination-prefix renaming, caret wildcard renaming, route duration expiry, shorthand route syntax, multi-destination fanout, command-line -o route configuration, and share-frequency throttling.",
        gifs=(
            ("Direct Route", "pshare_direct_route_pass", "pshare-direct-route.gif"),
            ("Wildcard Route", "pshare_wildcard_route_pass", "pshare-wildcard-route.gif"),
        ),
        run="./zlaunch.sh --jobs=2 --port_base=11000 10",
        notes=(
            "This harness uses two local MOOS communities so pShare is tested through real UDP route delivery rather than synthetic summary mail.",
            "The mission owns the pass/fail grade by evaluating the receiver-side variables after routed mail should have arrived.",
        ),
    ),
    Harness(
        slug="pshare-topology",
        title="H02 pShare Topology",
        family="Utility Infrastructure",
        path="harnesses/pshare_harnesses/H02-pshare_topology",
        mission="missions/pshare_missions/pshare_topology",
        summary="Headless four-community harness for pShare route behavior that needs multiple senders, multiple input ports, input route-list parsing, multicast listeners, custom multicast channels, relay proof, route-list branching, app aliases, runtime input-route insertion, or runtime output-route insertion.",
        proof="Checks two-sender fan-in, competing sender updates, one receiver listening on multiple pShare input ports, one receiver input line expanding multiple route-list ports, multicast delivery to both evaluator and relay, relay proof routed back to the evaluator, dynamic unicast and multicast input-route insertion through PSHARE_CMD, custom multicast base/address mapping, unicast branching to a relay, route-list branching across communities, alias-specific command routing, and dynamic output-route insertion through PSHARE_CMD.",
        gifs=(
            ("Fan-in", "pshare_topology_fanin_pass", "pshare-topology-fanin.gif"),
            ("Multicast Relay Proof", "pshare_topology_multicast_multi_listener_pass", "pshare-topology-multicast-relay-proof.gif"),
        ),
        run="./zlaunch.sh --jobs=2 --port_base=11000 --max_time=65 10",
        notes=(
            "The stem mission runs four local MOOS communities: a shoreside evaluator, two sender peers, and one relay/listener peer.",
            "The shoreside community owns the final pMissionEval grade; relay-local pMissionEval flags are used only as proof that the relay received the relevant multicast or unicast branch.",
        ),
    ),
    Harness(
        slug="plogger-unit",
        title="H01 pLogger Unit",
        family="Utility Infrastructure",
        path="harnesses/plogger_harnesses/H01-plogger_unit",
        mission="missions/plogger_missions/plogger_unit",
        summary="Headless artifact harness for pLogger explicit logs, wildcard omit and exclusion logs, dynamic log requests, datatype marking, sync logs, copy-file requests, and fixed artifact naming.",
        proof="Checks mission-owned live mail grades plus harness-owned .alog, .slog, .xlog, and copied-file evidence for explicit, wildcard, omitted, dynamically requested, numeric, typed, synchronous, fixed-name, and copy-request artifacts.",
        gifs=(
            ("Explicit Log Capture", "plogger_explicit_log_pass", "plogger-explicit-log-capture.gif"),
            ("Wildcard Omit", "plogger_wildcard_omit_pass", "plogger-wildcard-omit.gif"),
        ),
        run="./zlaunch.sh --jobs=2 --port_base=12000 10",
        notes=(
            "pLogger's real product is an artifact on disk, so this harness supplements pMissionEval with narrow .alog content checks.",
            "The artifact checks look only for the variables that define each case rather than treating the whole log as a golden file.",
        ),
    ),
    Harness(
        slug="pantler-unit",
        title="H01 pAntler Unit",
        family="Utility Infrastructure",
        path="harnesses/pantler_harnesses/H01-pantler_unit",
        mission="missions/pantler_missions/pantler_unit",
        summary="Headless launch-composition harness for pAntler baseline launches, aliases, launch filters, explicit system-path launches, and extra process parameters.",
        proof="Checks that pAntler starts the expected configured apps, honors MOOS-name aliases, launches multiple aliases of the same binary, filters a launch set, accepts explicit system-path lookup, and forwards extra process parameters.",
        gifs=(
            ("Alias Launch", "pantler_alias_launch_pass", "pantler-alias-launch.gif"),
            ("Multi-alias Launch", "pantler_multi_alias_launch_pass", "pantler-multi-alias-launch.gif"),
        ),
        run="./zlaunch.sh --jobs=2 --port_base=12200 10",
        notes=(
            "The graded flags are emitted only by apps launched through pAntler, keeping the verdict tied to launch composition.",
            "These remain deliberately small smoke tests; deeper pAntler failure-mode coverage would need process-exit and stderr inspection.",
        ),
    ),
    Harness(
        slug="pmissioneval-unit",
        title="H01 pMissionEval Unit",
        family="pMissionEval",
        path="harnesses/mission_utility_harnesses/H01-pmissioneval_unit",
        mission="missions/mission_utility_missions/mission_utility_unit",
        summary="Headless lifecycle harness for pMissionEval grading, staged logic sequences, flags, report formats, and macro expansion.",
        proof="Checks pass and fail grading, built-in finish publication, staged sequence pass and fail paths, lead-only and fail-only evaluator shapes, explicit fail conditions, flags and mailflags, numeric and mission-hash macro expansion, literal numeric flags, CSP report formatting, clock macros, and no-hash report behavior.",
        gifs=(
            ("Baseline Evaluation", "eval_baseline_pass", "pmissioneval-baseline-evaluation.gif"),
            ("Two-stage Logic", "eval_sequence_two_stage_pass", "pmissioneval-two-stage-logic.gif"),
        ),
        run="./zlaunch.sh --jobs=3 --port_base=7100 10",
        notes=(
            "This is a shoreside-only lifecycle harness focused on the grading machinery used by other CI missions.",
            "The harness still launches uMayFinish directly with unique aliases so pMissionEval completion remains observable through process exit behavior.",
        ),
    ),
    Harness(
        slug="pmissionhash-unit",
        title="H02 pMissionHash Unit",
        family="pMissionHash",
        path="harnesses/mission_utility_harnesses/H02-pmissionhash_unit",
        mission="missions/mission_utility_missions/mission_utility_unit",
        summary="Headless lifecycle harness for pMissionHash publication names, disabled outputs, and reset behavior.",
        proof="Checks custom long and short hash variables, short-hash disable behavior, long-hash disable behavior, and RESET_MHASH-driven hash changes.",
        gifs=(
            ("Custom Hash Vars", "hash_custom_vars_pass", "pmissionhash-custom-vars.gif"),
            ("Hash Reset", "hash_reset_changes_pass", "pmissionhash-reset.gif"),
        ),
        run="./zlaunch.sh --jobs=3 --port_base=7300 10",
        notes=(
            "This harness uses pMissionEval as the mission-owned grading consumer, but the cases isolate pMissionHash publication behavior.",
            "The default port block starts at 7300 so it can run alongside the pMissionEval split harness.",
        ),
    ),
    Harness(
        slug="umayfinish-unit",
        title="H03 uMayFinish Unit",
        family="uMayFinish",
        path="harnesses/mission_utility_harnesses/H03-umayfinish_unit",
        mission="missions/mission_utility_missions/mission_utility_unit",
        summary="Headless lifecycle harness for uMayFinish default completion, custom finish variables, mismatched finish values, and timeout exits.",
        proof="Checks default MISSION_EVALUATED exit, custom finish-variable exit, custom finish-value mismatch timeout, and missing-finish timeout.",
        gifs=(
            ("Default Finish Exit", "mayfinish_default_exit_pass", "umayfinish-default-exit.gif"),
            ("Custom Value Timeout", "mayfinish_custom_value_timeout_fail", "umayfinish-custom-value-timeout.gif"),
        ),
        run="./zlaunch.sh --jobs=3 --port_base=7400 10",
        notes=(
            "This harness launches uMayFinish directly with unique aliases so exit-code behavior stays visible.",
            "The default port block starts at 7400 so it can run alongside the other mission utility split harnesses.",
        ),
    ),
    Harness(
        slug="zigzag-behavior-motion",
        title="H01 ZigZag Behavior",
        family="Behavior Correctness",
        path="harnesses/zigzag_behavior_harnesses/H01-zigzag_behavior_motion",
        mission="missions/zigzag_behavior_missions/zigzag_behavior_motion",
        summary="Moving correctness harness for BHV_ZigZag side selection, angle boundaries, completion limits, active-time capture, runtime speed updates, visual hints, and invalid inputs.",
        proof="Checks zig/zag counts, side-entry and side-exit flags, stem odometry, active stem heading/speed macros, runtime update effects, and expected malformed-configuration failures.",
        gifs=(
            ("Baseline Port First", "baseline_port_first_pass", "zigzag-behavior-baseline-port.gif"),
            ("Wide Angle", "wide_angle_pass", "zigzag-behavior-wide-angle.gif"),
            ("Fierce Zigging", "fierce_zigging_pass", "zigzag-behavior-fierce-zigging.gif"),
        ),
        run="./zlaunch.sh --case=baseline_port_first_pass --gui --port_base=15000 10",
        notes=(
            "This harness starts with a short approach leg so ZigZag activates with live navigation state and then owns the evaluated motion contract.",
            "Expected-fail cases document invalid parameter boundaries and the unsupported stale-nav-threshold configuration path.",
        ),
    ),
    Harness(
        slug="legrun-behavior-motion",
        title="H01 LegRun Behavior",
        family="Behavior Correctness",
        path="harnesses/legrun_behavior_harnesses/H01-legrun_behavior_motion",
        mission="missions/legrun_behavior_missions/legrun_behavior_motion",
        summary="Moving correctness harness for BHV_LegRun leg selection, geometry forms, capture handling, turn shaping, speed schedules, runtime updates, flags, and invalid configuration.",
        proof="Checks LegRun-owned leg, turn, mid-leg, mid-turn, completion, geometry parsing, capture-line modes, turn parameter aliases, runtime update, speed schedule, initialization mode, flag alias, and expected parameter-failure signals.",
        gifs=(
            ("Baseline Cycle", "baseline_cycle_pass", PENDING_GIF),
            ("Far Turn Init", "init_far_turn_pass", PENDING_GIF),
            ("Individual Turn Params", "individual_turn_params_pass", PENDING_GIF),
        ),
        run="./zlaunch.sh --case=baseline_cycle_pass --gui --port_base=4000 10",
        notes=(
            "This harness keeps one simulated vehicle on a compact two-leg pattern so LegRun owns the evaluated motion contract.",
            "The far-turn initialization case is graded separately because it intentionally starts on the far leg path instead of the default first leg.",
        ),
    ),
    Harness(
        slug="shadow-behavior-motion",
        title="H01 Shadow Behavior",
        family="Behavior Correctness",
        path="harnesses/shadow_behavior_harnesses/H01-shadow_behavior_motion",
        mission="missions/shadow_behavior_missions/shadow_behavior_motion",
        summary="Two-vehicle moving correctness harness for BHV_Shadow contact telemetry, relevance gates, speed/heading following, runtime updates, and malformed inputs.",
        proof="Checks shadow contact heading/speed output, active relevance, stopped relevance, runtime recovery, warning-only paths, contact flags, and expected parameter failures.",
        gifs=(
            ("Static Shadow", "static_shadow_pass", "shadow-behavior-static.gif"),
            ("Turn North Shadow", "turn_north_shadow_pass", "shadow-behavior-turn-north.gif"),
            ("Runtime PWT On", "runtime_pwt_outer_on_pass", "shadow-behavior-runtime-pwt-on.gif"),
        ),
        run="./zlaunch.sh --case=static_shadow_pass --gui 10",
        notes=(
            "This harness uses one target and one chaser so shadowing can be graded against changing contact heading and speed.",
            "Relevance and missing-contact cases distinguish clean inactive behavior from warning and error paths.",
        ),
    ),
    Harness(
        slug="performance-obstacle-gauntlet",
        title="P01 Obstacle Gauntlet",
        family="Performance",
        path="harnesses/performance_harnesses/P01-obstacle_gauntlet",
        mission="missions/performance_missions/P01-obstacle_gauntlet",
        summary="Deterministic and randomized obstacle-field performance harness.",
        proof="Checks loop completion, zero collisions, bounded near misses/encounters, wall time, timeout, and warning-free logs.",
        gifs=(
            ("Baseline Field", "baseline_field_pass", "performance-obstacle-gauntlet-baseline.gif"),
            ("Dense Field", "dense_field_pass", "performance-obstacle-gauntlet-dense.gif"),
            ("Endurance Random", "endurance_random_pass", "performance-obstacle-gauntlet-endurance.gif"),
        ),
        run="./zlaunch.sh --case=baseline_field_pass --gui 10",
        notes=(
            "This harness moves beyond single encounters into repeated obstacle-field traversal.",
            "Shell-side checks add wall-time and warning-log constraints around mission-owned verdicts.",
        ),
    ),
    Harness(
        slug="performance-colregs-joust",
        title="P02 COLREGS Joust",
        family="Performance",
        path="harnesses/performance_harnesses/P02-colregs_joust",
        mission="missions/performance_missions/P02-colregs_joust",
        summary="Two- and three-vehicle COLREGS pressure harness focused on sustained safe spacing.",
        proof="Checks mission completion, zero collisions, closest-range envelopes, near misses, wall time, and warning-free logs.",
        gifs=(
            ("Baseline Joust", "baseline_colregs_pass", "performance-colregs-joust-baseline.gif"),
            ("Dense Joust", "dense_colregs_pass", "performance-colregs-joust-dense.gif"),
        ),
        run="./zlaunch.sh --case=dense_colregs_pass --gui 10",
        notes=(
            "This harness tests sustained COLREGS pressure rather than a single isolated encounter.",
            "Closest-range telemetry is the primary spacing signal for this mission family.",
        ),
    ),
    Harness(
        slug="performance-traffic-ring",
        title="P03 COLREGS Traffic Ring",
        family="Performance",
        path="harnesses/performance_harnesses/P03-colregs_traffic_ring",
        mission="missions/performance_missions/P03-colregs_traffic_ring",
        summary="Fixed-seed five-vehicle traffic-ring harness with repeated reassignment pressure.",
        proof="Checks zero collisions, assignment activity floors, fixed runtime windows, warning-free logs, and sustained randomized traffic pressure.",
        gifs=(
            ("Baseline Traffic Ring", "baseline_circle_pass", "performance-traffic-ring-baseline.gif"),
            ("Mixed-Speed Traffic Ring", "mixed_speed_circle_pass", "performance-traffic-ring-mixed-speed.gif"),
            ("Non-Cooperative Traffic Ring", "noncoop_circle_pass", "performance-traffic-ring-noncoop.gif"),
        ),
        run="./zlaunch.sh --case=baseline_circle_pass --gui 10",
        notes=(
            "Fixed RNG seeds keep runs comparable, while asynchronous completion may change the exact assignment order.",
            "Assignment activity and zero-collision checks are the primary health signals.",
        ),
    ),
)


FAMILIES: tuple[Family, ...] = (
    Family(
        name="pContactMgrV20",
        label="Contact Management",
        summary="Detects and reports relevant contacts so downstream avoidance behaviors can react to them.",
        slugs=("cmgr-unit", "cmgr-motion"),
    ),
    Family(
        name="pObstacleMgr",
        label="Obstacle Management",
        summary="Accepts obstacle inputs, builds obstacle representations, and publishes alerts used by obstacle avoidance.",
        slugs=("obmgr-unit", "obmgr-motion"),
    ),
    Family(
        name="pMarinePIDV22",
        label="Marine PID",
        summary="Converts desired heading, speed, and depth mail into direct actuator commands under override, stale-input, and yaw-source constraints.",
        slugs=("pid-unit", "pid-motion"),
    ),
    Family(
        name="uSimMarineV22",
        label="uSimMarineV22",
        summary="Checks simulator motion, actuator response, limits, drift/current inputs, reset, pause, and navigation-state publication.",
        slugs=("usim-marine-motion",),
    ),
    Family(
        name="pNodeReporter",
        label="pNodeReporter",
        summary="Checks node-report construction, platform metadata, alternate nav streams, runtime updates, pause/resume, and odometry metrics.",
        slugs=("pnodereporter-unit",),
    ),
    Family(
        name="uPokeDB",
        label="uPokeDB",
        summary="Checks command-line MOOSDB pokes across connection modes, value forms, cache parsing, short aliases, overwrites, quiet operation, and time macros.",
        slugs=("upokedb-unit",),
    ),
    Family(
        name="uXMS",
        label="uXMS",
        summary="Checks terminal MOOSDB scoping output across variable scopes, display columns, history, filters, source selection, config, aliases, refresh modes, and truncation.",
        slugs=("uxms-unit",),
    ),
    Family(
        name="uQueryDB",
        label="uQueryDB",
        summary="Checks command-line MOOSDB query pass/fail logic, timeout behavior, mission-file configuration, compound conditions, and check-variable output formats.",
        slugs=("uquerydb-unit",),
    ),
    Family(
        name="pEchoVar",
        label="pEchoVar",
        summary="Checks live echo mappings, boolean inversion, EFlipper component extraction, filters, separators, cycle suppression, and duplicate mapping behavior.",
        slugs=("pechovar-unit",),
    ),
    Family(
        name="uTimerScript",
        label="uTimerScript",
        summary="Checks exact event payloads, control ordering, reset and timing paths, macro expansion, delayed-client block-on, awake policies, and quit behavior.",
        slugs=("utimerscript-unit",),
    ),
    Family(
        name="pDeadManPost",
        label="pDeadManPost",
        summary="Checks watchdog deadflag posting across active-at-start behavior, heartbeat suppression, stale heartbeat detection, and numeric/string/multiple deadflags.",
        slugs=("pdeadmanpost-unit",),
    ),
    Family(
        name="pSpoofNode",
        label="pSpoofNode",
        summary="Checks spoofed NODE_REPORT generation, defaults, runtime requests, motion advancement, duration expiry, cancellation, and malformed request rejection.",
        slugs=("pspoofnode-unit",),
    ),
    Family(
        name="uTermCommand",
        label="uTermCommand",
        summary="Checks terminal command mapping, typed posts, partial matching, duplicate precedence, tab expansion, and unknown command absence.",
        slugs=("utermcommand-unit",),
    ),
    Family(
        name="pSearchGrid",
        label="pSearchGrid",
        summary="Checks grid construction, full and delta publication, node-report ingestion, custom output variables, community filters, and invalid/outside-grid absence.",
        slugs=("psearchgrid-unit",),
    ),
    Family(
        name="uField Communications",
        label="Field Messaging",
        summary="Checks field communications delivery, broker bridge setup, and route recovery paths that connect vehicle and shoreside pShare communities.",
        slugs=("ufield-comms-unit", "ufield-broker-bridge", "ufield-route-resilience"),
    ),
    Family(
        name="uFldPathCheck",
        label="uFldPathCheck",
        summary="Checks path-history, odometry, trip-reset, and speed-report contracts from controlled node-report mail.",
        slugs=("ufld-pathcheck-unit",),
    ),
    Family(
        name="uFldMessageHandler",
        label="uFldMessageHandler",
        summary="Checks NODE_MESSAGE routing, addressing, payload forwarding, summary counters, and configured flag outputs.",
        slugs=("ufld-message-handler-unit",),
    ),
    Family(
        name="uFldContactRangeSensor",
        label="uFldContactRangeSensor",
        summary="Checks contact-ledger range requests, report variable modes, sensor arcs, echo filters, ping waits, and range limits.",
        slugs=("ufld-contact-range-sensor-unit",),
    ),
    Family(
        name="uFldBeaconRangeSensor",
        label="uFldBeaconRangeSensor",
        summary="Checks beacon range requests, report modes, ground-truth output, range gates, ping policies, markers, and malformed requests.",
        slugs=("ufld-beacon-range-sensor-unit",),
    ),
    Family(
        name="uFldCollisionDetect",
        label="uFldCollisionDetect",
        summary="Checks encounter ranking, collision and near-miss thresholds, clear-report controls, range gates, filters, and flag outputs.",
        slugs=("ufld-collision-detect-unit",),
    ),
    Family(
        name="uFldCollObDetect",
        label="uFldCollObDetect",
        summary="Checks vehicle-obstacle collisions, near misses, encounter thresholds, minimum-distance tracking, clearing gates, and flags.",
        slugs=("ufld-collob-detect-unit",),
    ),
    Family(
        name="uFldScope",
        label="uFldScope",
        summary="Checks scope table appcasts, field aliases, same-key replacement including blank overwrites, multi-row display, invalid-scope recovery, and missing field/key rendering.",
        slugs=("ufld-scope-unit",),
    ),
    Family(
        name="BHV_ConstantDepth",
        label="Depth Behavior",
        summary="Checks held depth, surfacing, runtime updates, bad config, missing depth mail, and actuator authority. H01 in shared depth behavior group.",
        slugs=("constant-depth-motion",),
    ),
    Family(
        name="BHV_GoToDepth",
        label="Depth Behavior",
        summary="Checks depth sequences, repeats, arrivals, crossings, invalid inputs, and missing depth state. H02, not H01, in shared depth behavior group.",
        slugs=("goto-depth-motion",),
    ),
    Family(
        name="BHV_PeriodicSurface",
        label="Depth Behavior",
        summary="Checks surfacing cycles, waits, status variables, acomms extensions, ascent modes, and bad timing inputs. H03, not H01, in shared depth behavior group.",
        slugs=("periodic-surface-motion",),
    ),
    Family(
        name="BHV_MaxDepth",
        label="Depth Behavior",
        summary="Checks max-depth guarding, clamps, tolerances, slack telemetry, bad config, and missing depth state. H04, not H01, in shared depth behavior group.",
        slugs=("max-depth-motion",),
    ),
    Family(
        name="BHV_MinAltitude",
        label="Depth Behavior",
        summary="Checks bottom-clearance guarding, shallow-bottom response, boundary behavior, bad config, and missing altitude inputs.",
        slugs=("min-altitude-motion",),
    ),
    Family(
        name="BHV_MemoryTurnLimit",
        label="Behavior Correctness",
        summary="Checks recent-heading averaging, tight versus relaxed limiter windows, and missing memory limiter configuration.",
        slugs=("memoryturnlimit-behavior-motion",),
    ),
    Family(
        name="BHV_AvdColregsV22",
        label="COLREGS Behavior",
        summary="Exercises COLREGS classification, threshold edges, execution quality, parameter sensitivity, and multi-vehicle stress cases.",
        slugs=(
            "colregs-classification",
            "colregs-thresholds",
            "colregs-execution",
            "colregs-parameters",
            "performance-colregs-joust",
            "performance-traffic-ring",
        ),
    ),
    Family(
        name="BHV_AvoidCollision",
        label="Collision Avoidance Behavior",
        summary="Owns contact-alert requests, behavior lifecycle, and clean resolution of collision-avoidance encounters.",
        slugs=("collision-behavior-motion",),
    ),
    Family(
        name="BHV_AvoidObstacleV24",
        label="Obstacle Avoidance Behavior",
        summary="Checks obstacle-avoidance lifecycle, helper flags, clean transit outcomes, and longer obstacle-field stress cases.",
        slugs=(
            "obstacle-behavior-motion",
            "performance-obstacle-gauntlet",
        ),
    ),
    Family(
        name="BHV_OpRegionV24",
        label="Operating Region Behavior",
        summary="Checks save and halt envelopes, entry/exit timing gates, reset behavior, and runtime region updates.",
        slugs=("opregion-safety",),
    ),
    Family(
        name="BHV_Waypoint",
        label="Waypoint Behavior",
        summary="Checks route traversal, capture modes, cycle flags, runtime point updates, status outputs, and invalid route inputs.",
        slugs=("waypoint-behavior-motion",),
    ),
    Family(
        name="BHV_Loiter",
        label="Loiter Behavior",
        summary="Checks loiter acquisition, polygon forms, center updates, speed modes, status reports, and invalid polygon inputs.",
        slugs=("loiter-behavior-motion",),
    ),
    Family(
        name="BHV_StationKeep",
        label="Station-Keeping Behavior",
        summary="Checks station-point holding, hibernation, radii, speed updates, warning recovery, and invalid station-keeping inputs.",
        slugs=("stationkeep-behavior-motion",),
    ),
    Family(
        name="BHV_Trail",
        label="Trail Behavior",
        summary="Checks moving target trailing geometry, pursuit relevance, runtime trail updates, and missing-contact handling.",
        slugs=("trail-behavior-motion",),
    ),
    Family(
        name="BHV_Convoy",
        label="Convoy Behavior",
        summary="Checks mark queues, leader/follower geometry, speed branches, runtime updates, visual breadcrumbs, and missing-contact handling.",
        slugs=("convoy-behavior-motion",),
    ),
    Family(
        name="BHV_CutRange",
        label="Cut-Range Behavior",
        summary="Checks pursuit relevance, range reduction, give-up behavior, target geometry branches, runtime updates, and malformed inputs.",
        slugs=("cutrange-behavior-motion",),
    ),
    Family(
        name="BHV_FixedTurn",
        label="Fixed-Turn Behavior",
        summary="Checks fixed-turn direction, scheduled turn specifications, runtime updates, timeout completion, and invalid turn configuration.",
        slugs=("fixedturn-behavior-motion",),
    ),
    Family(
        name="BHV_PeriodicSpeed",
        label="Periodic Speed Behavior",
        summary="Checks lazy/busy speed windows, initially-busy startup, reset behavior, alias acceptance, zero-speed handling, status outputs, and invalid parameter configuration.",
        slugs=("periodic-speed-behavior-motion",),
    ),
    Family(
        name="BHV_Timer",
        label="Timer Behavior",
        summary="Checks idle and running duration counters, custom/default status variables, suffix handling, and invalid timer status configuration.",
        slugs=("timer-behavior-motion",),
    ),
    Family(
        name="BHV_TestFailure",
        label="TestFailure Behavior",
        summary="Checks completion-triggered burn, hang, parser edge cases, crash/default-crash process loss, and an armed non-completing baseline.",
        slugs=("testfailure-behavior-unit",),
    ),
    Family(
        name="pHostInfo",
        label="Host Info Utility",
        summary="Checks host IP, MOOSDB port, and exact route-normalized PHI_HOST_INFO payloads.",
        slugs=("hostinfo-unit",),
    ),
    Family(
        name="uLoadWatch",
        label="Load Watch Utility",
        summary="Checks near and hard threshold detection, trigger holdoff, threshold boundaries, and app matching.",
        slugs=("loadwatch-unit",),
    ),
    Family(
        name="uProcessWatch",
        label="Process Watch Utility",
        summary="Checks process-presence summaries, mapped posts, event mapping, and expected missing-process detection.",
        slugs=("processwatch-unit",),
    ),
    Family(
        name="pShare",
        label="pShare",
        summary="Checks routed mail, wildcard routes, multicast topology, throttling, route-list parsing, and runtime route insertion.",
        slugs=("pshare-unit", "pshare-topology"),
    ),
    Family(
        name="pLogger",
        label="pLogger",
        summary="Checks explicit log capture, wildcard omit and exclusion logs, dynamic log requests, sync logs, numeric and typed values, copy-file requests, and fixed artifact names.",
        slugs=("plogger-unit",),
    ),
    Family(
        name="pAntler",
        label="pAntler",
        summary="Checks baseline process launch, MOOS-name aliases, multiple aliases, launch filters, explicit system-path lookup, and extra process parameters.",
        slugs=("pantler-unit",),
    ),
    Family(
        name="pMissionEval",
        label="pMissionEval",
        summary="Checks mission grading, staged logic, result flags, report formatting, macro expansion, and no-hash report behavior.",
        slugs=("pmissioneval-unit",),
    ),
    Family(
        name="pMissionHash",
        label="pMissionHash",
        summary="Checks mission hashes, custom output variables, disabled outputs, and reset behavior.",
        slugs=("pmissionhash-unit",),
    ),
    Family(
        name="uMayFinish",
        label="uMayFinish",
        summary="Checks default finish exits, custom finish variables, mismatched finish values, and timeout exits.",
        slugs=("umayfinish-unit",),
    ),
    Family(
        name="uFldPathCheck",
        label="uFldPathCheck",
        summary="Checks path-history, odometry, trip-reset, and speed-report contracts from controlled node-report mail.",
        slugs=("ufld-pathcheck-unit",),
    ),
    Family(
        name="uFldMessageHandler",
        label="uFldMessageHandler",
        summary="Checks NODE_MESSAGE routing, addressing, payload forwarding, summary counters, and configured flag outputs.",
        slugs=("ufld-message-handler-unit",),
    ),
    Family(
        name="uFldContactRangeSensor",
        label="uFldContactRangeSensor",
        summary="Checks contact-ledger range requests, report variable modes, sensor arcs, echo filters, ping waits, and range limits.",
        slugs=("ufld-contact-range-sensor-unit",),
    ),
    Family(
        name="uField Obstacle Simulation",
        label="uFldObstacleSim",
        summary="Checks obstacle-field source publication, simulated point sensing, refresh, reset, visual, and range-gating behavior.",
        slugs=("ufld-obstacle-sim-unit",),
    ),
    Family(
        name="BHV_ZigZag",
        label="ZigZag Behavior",
        summary="Checks first-side selection, zig-angle boundaries, leg and odometry completion, active-time capture, runtime speed updates, visual hints, and invalid inputs.",
        slugs=("zigzag-behavior-motion",),
    ),
    Family(
        name="BHV_LegRun",
        label="LegRun Behavior",
        summary="Checks leg selection, leg and turn progression, completion, speed schedules, runtime updates, and invalid leg-run inputs.",
        slugs=("legrun-behavior-motion",),
    ),
    Family(
        name="BHV_Shadow",
        label="Shadow Behavior",
        summary="Checks contact speed/heading following, relevance gates, warning recovery, runtime updates, and malformed contact/configuration inputs.",
        slugs=("shadow-behavior-motion",),
    ),
)


TEST_STYLE: dict[str, str] = {
    "cmgr-unit": "Simple correctness tests for pContactMgrV20 output behavior. These cases keep the mission controlled and verify that contact alerts, reports, filters, runtime requests, and multi-contact selections appear only when expected.",
    "cmgr-motion": "Moving correctness tests for contact-management evidence. These cases check whether contact-manager alerts arrive early enough for downstream avoidance to produce a safe transit, while expected-fail cases prove the gate catches missing or late avoidance evidence.",
    "obmgr-unit": "Simple correctness tests for pObstacleMgr output behavior. These cases keep vehicle dynamics minimal and verify accepted obstacles, rejected obstacles, alert messages, point-cluster hulls, distance reports, and obstacle lifecycle messages.",
    "obmgr-motion": "Moving correctness tests for obstacle-manager alert output. These cases check whether obstacle alerts are actionable enough to support clean obstacle-avoidance transit, and whether intentionally bad setups fail for the expected reason.",
    "pid-unit": "Simple correctness tests for pMarinePIDV22 output behavior. These cases keep the mission to one MOOS community and verify rudder, thrust, elevator, override, stale-input, yaw-source, and debug publication paths.",
    "pid-motion": "Moving correctness tests for pMarinePIDV22 closed-loop behavior. These cases add pHelmIvP and uSimMarineV22 and verify that PID output drives arrival, turn recovery, speed-PID transit, depth response, and expected authority failures.",
    "usim-marine-motion": "App-level correctness tests for uSimMarineV22. These cases directly verify simulator publications under scripted actuator mail, embedded PID coupling, limit parameters, drift/current inputs, water-depth altitude, pause, reset, disabled-nav, and stop-control inputs.",
    "pnodereporter-unit": "App-level correctness tests for pNodeReporter. These cases directly verify node-report construction, platform metadata, helm-mode fields, JSON modes, alternate nav streams, coordinate cross-fill policies, runtime metadata updates, pause/resume behavior, odometry evidence, and expected blackout-interval failure detection.",
    "upokedb-unit": "Utility app correctness tests for uPokeDB. These cases verify that command-line, mission-file, and cached pokes publish the intended numeric, string, boolean-looking, overwritten, repeated, alias-driven, and time-macro values to a live MOOSDB.",
    "uxms-unit": "Utility app correctness tests for uXMS. These cases verify terminal scoping output for named variables, all/alll display, source/time/community columns, history, truncation, config-file variables, clean CLI overrides, filters, source selection, novirgins, connection aliases, refresh modes, shortcuts, and color mapping.",
    "uquerydb-unit": "Utility app correctness tests for uQueryDB. These cases verify query return codes, CLI and ProcessConfig pass/fail conditions, fail-only queries, missing-variable timeouts, halt_max_time, numeric comparisons, compound logic, unique client names, and check-variable file formats.",
    "pechovar-unit": "Utility app correctness tests for pEchoVar. These cases verify live echo mapping, boolean inversion, fan-out, duplicate mapping de-duplication, latest-value handling, EFlipper component maps, filters, custom separators, cycle suppression, invalid flipper suppression, and independent named flippers.",
    "utimerscript-unit": "Live uTimerScript correctness tests. Cases verify exact scheduled payloads, suppression and release ordering, reset counts and delays, timing windows, status output, polygon-pair containment, delayed-client block-on, awake policies, and quit-driven process exit.",
    "pdeadmanpost-unit": "Utility app correctness tests for pDeadManPost. These cases verify deadflag posting and suppression across active-at-start, inactive-until-first-heartbeat, stale heartbeat, custom heartbeat variables, once/repeat/reset post policies, invalid policy fallback, and typed deadflag configurations.",
    "pspoofnode-unit": "Utility app correctness tests for pSpoofNode. These cases verify structured NODE_REPORT output for config and runtime spoof requests, generated names, moving contacts, name/group/contact cancellation, expiration, defaults and startup ordering, runtime normalization, color/type edge behavior, and malformed requests.",
    "utermcommand-unit": "Utility app correctness tests for uTermCommand. These cases verify terminal command mapping for numeric and string posts, arrow syntax, unique and ambiguous partial keys, exact-prefix handling, delete editing, duplicate-key precedence, command config parsing, multi-command configs, and unknown command absence.",
    "psearchgrid-unit": "Utility app correctness tests for pSearchGrid. These cases verify initial grid output, local/global node-report deltas, repeated and multi-cell delta behavior, reset clearing semantics, full-grid publication, custom grid variables, single and list filter blocking, malformed reports, and outside-grid absence.",
    "ufield-comms-unit": "App-level correctness tests for uFldNodeComms. These cases verify report and message delivery under controlled range, group, stale-report, payload, shared-report, pulse, runtime-mail, and drop-policy conditions.",
    "ufield-broker-bridge": "Broker-level correctness tests for uFldNodeBroker and uFldShoreBroker. These cases verify broker handshakes, pShare command generation, qbridge expansion, custom bridge expansion, mediated bridge selection, vnode discovery, keyword mismatch status, and auto-bridge suppression.",
    "ufield-route-resilience": "Integration correctness tests for uFldNodeBroker, uFldShoreBroker, and pShare route lifecycle behavior. These cases verify startup/runtime route parsing, dead-first-route blocking, secondary dead-route tolerance, runtime route timing, duplicate suppression, invalid route rejection, numeric loopback routes, per-node route gaps, and shore-driven vnode discovery.",
    "ufld-obstacle-sim-unit": "App-level correctness tests for uFldObstacleSim. These cases verify obstacle-file ingestion, truth and vehicle-facing obstacle publications, visual toggles, point-sensor mode, sensor-range boundaries, runtime point-size mail, refresh intervals, reset gating, and visual style settings.",
    "ufld-pathcheck-unit": "App-level correctness tests for uFldPathCheck. These cases verify speed and odometry reports, trip-reset behavior, local report handling, invalid-report suppression, stationary tracks, independent multi-node accounting, and history-window speed calculations.",
    "ufld-message-handler-unit": "App-level correctness tests for uFldMessageHandler. These cases verify broad and specific addressing, strict-addressing rejection, invalid-message handling, numeric and string payload forwarding, summary counters, and good/bad flag macro expansion.",
    "ufld-contact-range-sensor-unit": "App-level correctness tests for uFldContactRangeSensor. These cases verify report variable modes, ground-truth output, echo-type filtering, sensor arcs, ping wait, pulse suppression, local reports, unknown requesters, and unlimited range overrides.",
    "ufld-beacon-range-sensor-unit": "App-level correctness tests for uFldBeaconRangeSensor. These cases verify request report forms, ground-truth output, NODE_REPORT_LOCAL handling, request and reply range gates, malformed and unknown request rejection, node-level unlimited range, default and node-specific ping wait suppression, ping-payment retry semantics, marker style output, and unsolicited frequency reports.",
    "ufld-collision-detect-unit": "App-level correctness tests for uFldCollisionDetect. These cases verify collision, near-miss, and clear encounter rankings, clear-report suppression by default, closest-range publications and suppression, reset behavior, pulse and ring suppression, range normalization, group filters, condition gates, encounter-range blocking, and configured collision/near/encounter flags.",
    "ufld-collob-detect-unit": "App-level correctness tests for uFldCollObDetect. These cases verify obstacle collision flags, near-miss and encounter-only flags, strict collision/near threshold boundaries, normalized range ordering, numeric distance flags, global minimum distance, invalid obstacle suppression, fresh, aged, and named obstacle clearing, and configured macro flag output.",
    "ufld-scope-unit": "App-level correctness tests for uFldScope. These cases verify appcast table construction, field alias headers, same-key row replacement including blank overwrites, multi-vehicle rows, recovery after invalid scope configuration, missing-field blank cells, and missing-key blank rows.",
    "constant-depth-motion": "Moving correctness tests for BHV_ConstantDepth. These cases verify held depths, surfacing, negative-depth clipping, shape parameters, runtime updates, malformed update preservation, finite-duration completion, malformed config, missing inputs/domain, and disabled depth-control authority.",
    "goto-depth-motion": "Moving correctness tests for BHV_GoToDepth. These cases verify multi-level sequences, repeated cycles and exhaustion, vertical target crossings, zero-delta arrivals, single-level targets, malformed update preservation, unsupported perpetual config, invalid sequences, malformed repeat values, missing inputs, and missing domain support.",
    "periodic-surface-motion": "Moving correctness tests for BHV_PeriodicSurface. These cases verify periodic surfacing, status variables, wait windows, timeout reset behavior, mark-variable resets, acomms extension, ascent profiles, current-speed mode, malformed status/ascent parameters, and missing inputs/domain.",
    "max-depth-motion": "Moving correctness tests for BHV_MaxDepth. These cases verify max-depth guarding, zero-depth clamps, negative command clipping, tight and zero tolerances, unconstrained shallow commands, invalid configuration, unsupported ascent-field config, missing depth inputs, and missing depth domain support.",
    "min-altitude-motion": "Moving correctness tests for BHV_MinAltitude. These cases verify bottom-clearance guarding, shallow-bottom response, unconstrained deep-bottom behavior, clearance boundary behavior, zero-minimum behavior, zero altitude failures, invalid configuration, missing nav inputs, and noncritical warning mode.",
    "colregs-classification": "Classification correctness tests for BHV_AvdColregsV22. These cases verify that canonical two-vessel geometries enter the expected COLREGS mode before execution quality is evaluated elsewhere.",
    "colregs-thresholds": "Boundary correctness tests for COLREGS classification. These cases probe below, edge, above, and mirrored geometries to catch regressions near rule-transition thresholds.",
    "colregs-execution": "Execution correctness tests for BHV_AvdColregsV22 after classification is known. These cases run encounters through completion and grade the realized maneuver using CPA, side outcome, timing, and collision evidence.",
    "colregs-parameters": "Parameter-regression tests for BHV_AvdColregsV22. These cases vary one tuning knob at a time while holding trusted geometry steady, verifying expected stability or one deliberate behavioral change.",
    "collision-behavior-motion": "Behavior correctness tests for BHV_AvoidCollision. These cases isolate the behavior contract: alert requests, contact information, lifecycle evidence, per-contact outputs, resolution signals, and collision-free transit.",
    "obstacle-behavior-motion": "Behavior correctness tests for BHV_AvoidObstacleV24. These cases isolate the behavior-owned contract for obstacle alert requests, helper flags, lifecycle evidence, resolution signals, and clean transit outcomes.",
    "opregion-safety": "Behavior correctness tests for BHV_OpRegionV24. These cases isolate the operating-region safety contract: save-region warnings, halt-region failures, generated buffers, entry/exit timing gates, reset handling, and runtime polygon updates.",
    "waypoint-behavior-motion": "Behavior correctness tests for BHV_Waypoint. These cases verify route completion, waypoint-hit and end flags, repeat/cycle behavior, runtime point updates, capture modes, status variables, and invalid route handling.",
    "loiter-behavior-motion": "Behavior correctness tests for BHV_Loiter. These cases verify stable loiter acquisition, polygon input forms, clockwise selection, center updates, speed modes, reports, and malformed polygon/update handling.",
    "stationkeep-behavior-motion": "Behavior correctness tests for BHV_StationKeep. These cases verify station arrival, hold/swing modes, hibernation, radius and speed updates, retargeting, warning recovery, and invalid parameter handling.",
    "trail-behavior-motion": "Behavior correctness tests for BHV_Trail. These cases verify relative and absolute trailing geometry, pursuit relevance, runtime trail updates, extrapolation choices, missing-contact behavior, and malformed parameter handling.",
    "convoy-behavior-motion": "Behavior correctness tests for BHV_Convoy. These cases verify convoy mark queues, following geometry, speed-control branches, runtime updates, warning paths, geometry recovery, and invalid parameter handling.",
    "cutrange-behavior-motion": "Behavior correctness tests for BHV_CutRange. These cases verify range closure, target geometry variants, pursuit and give-up flags, relevance gates, runtime updates, warning recovery, and invalid parameter handling.",
    "fixedturn-behavior-motion": "Behavior correctness tests for BHV_FixedTurn. These cases verify fixed-turn direction, scheduled turn specifications, inherited and fixed speed branches, timeout completion, runtime updates, and invalid turn configuration.",
    "periodic-speed-behavior-motion": "Behavior correctness tests for BHV_PeriodicSpeed. These cases verify lazy/busy speed cycling, initially-busy startup, reset behavior, alias parameters, accepted zero-speed windows, status variable outputs, and invalid parameter configuration.",
    "memoryturnlimit-behavior-motion": "Behavior correctness tests for BHV_MemoryTurnLimit. These cases verify recent-heading average output, tight and relaxed turn-window effects, runtime limiter updates, speed-scaling branches, heading mismatch evidence, and missing limiter configuration.",
    "timer-behavior-motion": "Behavior correctness tests for BHV_Timer. These cases verify idle and running duration counters, custom and default status variable names, suffix handling, active-at-start timing, and invalid status configuration.",
    "testfailure-behavior-unit": "Behavior correctness tests for BHV_TestFailure. These cases verify completion-triggered burn and hang stalls, default/malformed/negative/zero burn timing, crash/default-crash process loss, and an armed baseline that must not complete.",
    "hostinfo-unit": "Utility infrastructure tests for pHostInfo. These cases verify deterministic host reporting, MOOSDB port publication, and exact pShare route normalization for valid, multi-route, mixed, non-UDP, and invalid route specifications.",
    "loadwatch-unit": "Utility infrastructure tests for uLoadWatch. These cases verify threshold counters, near and hard threshold boundary behavior, low-threshold ignore behavior, clamped near-threshold behavior, breach-trigger holdoff, app-specific threshold matching, and threshold-name case sensitivity.",
    "processwatch-unit": "Utility infrastructure tests for uProcessWatch. These cases verify process summary publications, custom present posts, event and summary post remapping, full summaries, and expected missing-process detection.",
    "pshare-unit": "Utility infrastructure tests for pShare. These cases verify direct route delivery, destination renaming, max-share limiting, wildcard source matching, source-app-qualified wildcards, multicast aliases, wildcard prefix renaming, caret wildcard renaming, duration expiry, shorthand route syntax, multi-destination fanout, command-line -o route configuration, and frequency throttling.",
    "pshare-topology": "Utility infrastructure tests for pShare topology behavior. These cases verify two-sender fan-in, competing updates to the same destination, one receiver listening on multiple UDP input ports, input route-list parsing, multicast delivery to more than one listener, custom multicast base/address mapping, relay proof of receipt, dynamic unicast and multicast receiver input-route insertion, unicast branching to a relay, route-list branching across communities, alias-specific command routing, and runtime output-route insertion through PSHARE_CMD.",
    "plogger-unit": "Utility infrastructure tests for pLogger. These cases verify explicit .alog capture, wildcard logging with omit patterns, dynamic log requests through PLOGGER_CMD, numeric mail capture, datatype marking and precision, synchronous .slog columns, wildcard exclusion .xlog output, copy-file requests, and fixed file naming.",
    "pantler-unit": "Utility infrastructure tests for pAntler. These cases verify ordinary launch composition, MOOS-name alias launch, multiple aliases of the same binary, launch filtering, explicit system-path process lookup, and extra process parameters.",
    "pmissioneval-unit": "Mission utility tests for pMissionEval. These cases verify pass/fail grading, built-in finish publication, staged logic sequences, fail-condition precedence, lead-only and fail-only evaluator shapes, flags and mailflags, numeric and mission-hash macros, literal numeric flags, CSP report output, clock macros, and no-hash report output.",
    "pmissionhash-unit": "Mission utility tests for pMissionHash. These cases verify custom hash variable names, short-hash disable behavior, long-hash disable behavior, and RESET_MHASH-driven hash changes.",
    "umayfinish-unit": "Mission utility tests for uMayFinish. These cases verify default MISSION_EVALUATED exits, custom finish variables, mismatched finish-value timeouts, and missing-finish timeouts.",
    "zigzag-behavior-motion": "Behavior correctness tests for BHV_ZigZag. These cases verify first-side selection and aliases, zig-angle boundaries, leg-limit and stem-odometry completion, active-time heading and speed capture, runtime speed updates, visual hints, and invalid parameter handling.",
    "legrun-behavior-motion": "Behavior correctness tests for BHV_LegRun. These cases verify leg geometry forms, initialization modes, capture handling, turn shaping, leg and turn progression, behavior completion, scheduled speeds, runtime updates, flag aliases, and invalid parameter handling.",
    "shadow-behavior-motion": "Behavior correctness tests for BHV_Shadow. These cases verify contact heading and speed following, relevance gating, runtime recovery, warning paths, contact flags, and invalid parameter handling.",
    "performance-obstacle-gauntlet": "Performance and endurance tests for obstacle avoidance. These cases exercise repeated obstacle-field traversal and grade completion, collision safety, warning cleanliness, and wall-time behavior.",
    "performance-colregs-joust": "Performance tests for sustained COLREGS pressure. These cases run repeated multi-vehicle interaction and grade safe spacing, completion, warning cleanliness, and runtime bounds.",
    "performance-traffic-ring": "Seeded traffic-stress tests for COLREGS behavior. These cases replay five-vehicle traffic pressure and grade assignment activity, fixed runtime windows, zero collisions, and warning-free logs.",
}


STEM_CONTEXT: dict[str, str] = {
    "cmgr-unit": "The stem mission is a small single-ownship setup in the lower-band Forrest 19 / MIT_SP frame. `alpha` is the ownship; contacts such as `bravo` or `intruder` are synthetic targets introduced by individual cases so pContactMgrV20 can be checked without a full behavior stack.",
    "cmgr-motion": "The stem mission places `alpha` on a short transit with one or more synthetic contacts. The harness keeps the geometry compact and grades whether contact-manager output gives the avoidance behavior enough evidence to arrive safely.",
    "obmgr-unit": "The stem mission keeps the ownship context simple and introduces given obstacles or point clusters through the case inputs. That isolates pObstacleMgr message behavior before any moving obstacle-avoidance outcome is judged.",
    "obmgr-motion": "The stem mission sends one ownship through a short corridor with obstacle layouts that vary by case. The harness grades whether obstacle-manager alerts support arrival without collisions, near misses, or unresolved encounters.",
    "pid-unit": "The stem mission runs one shoreside MOOS community with scripted desired/nav mail and pMarinePIDV22 using suffixed outputs. It deliberately avoids a simulated vehicle so the cases can grade the PID app's direct actuator contract.",
    "pid-motion": "The stem mission runs one simulated vehicle and one shoreside evaluation community. The vehicle uses pHelmIvP, pMarinePIDV22, and uSimMarineV22; the shoreside evaluator grades bridged nav and actuator evidence.",
    "usim-marine-motion": "The stem mission runs one MOOS community with uSimMarineV22, uTimerScript, pMissionEval, pAutoPoke, and logging/watchdog support. Case overlays change only simulator configuration, scripted input mail, and mission-owned pass/fail conditions.",
    "constant-depth-motion": "The shared depth stem mission runs one simulated UUV and one shoreside evaluation community. The vehicle uses pHelmIvP, pMarinePIDV22, and uSimMarineV22; the horizontal waypoint keeps the vehicle underway while BHV_ConstantDepth owns the vertical-control verdict.",
    "goto-depth-motion": "The shared depth stem mission runs one simulated UUV and one shoreside evaluation community. The vehicle uses pHelmIvP, pMarinePIDV22, and uSimMarineV22; the horizontal waypoint keeps the vehicle underway while BHV_GoToDepth owns the depth-sequence verdict.",
    "periodic-surface-motion": "The shared depth stem mission runs one simulated UUV and one shoreside evaluation community. The vehicle uses pHelmIvP, pMarinePIDV22, and uSimMarineV22; the horizontal waypoint keeps the vehicle underway while BHV_PeriodicSurface owns the surfacing-cycle verdict.",
    "max-depth-motion": "The shared depth stem mission runs one simulated UUV and one shoreside evaluation community. The vehicle uses pHelmIvP, pMarinePIDV22, and uSimMarineV22; the horizontal waypoint keeps the vehicle underway while BHV_MaxDepth owns the over-depth guard verdict.",
    "min-altitude-motion": "The shared depth stem mission runs one simulated UUV and one shoreside evaluation community. The vehicle uses pHelmIvP, pMarinePIDV22, and uSimMarineV22; the horizontal waypoint keeps the vehicle underway while BHV_MinAltitude owns the bottom-clearance verdict.",
    "colregs-classification": "The shared COLREGS stem mission uses two vessels, `ben` and `abe`; `ben` is the evaluated ownship. Case overlays vary the encounter geometry for head-on, crossing, overtaking, and overtaken situations.",
    "colregs-thresholds": "The shared COLREGS stem mission uses two vessels, `ben` and `abe`; `ben` is the evaluated ownship. Threshold cases reuse the same stem while moving the geometry just below, at, or above classification boundaries.",
    "colregs-execution": "The shared COLREGS stem mission uses two vessels, `ben` and `abe`; `ben` is the evaluated ownship. Execution cases reuse trusted classification geometry and then judge the maneuver that actually unfolds.",
    "colregs-parameters": "The shared COLREGS stem mission uses two vessels, `ben` and `abe`; `ben` is the evaluated ownship. Parameter cases keep the encounter setup stable while changing one behavior setting at a time.",
    "collision-behavior-motion": "The stem mission puts one ownship in a compact moving encounter with a synthetic contact. Unlike the app-level contact-manager harnesses, this stem focuses on what BHV_AvoidCollision requests, publishes, and resolves.",
    "obstacle-behavior-motion": "The stem mission runs one ownship through deterministic obstacle layouts with obstacle-manager input held stable. The cases focus on what BHV_AvoidObstacleV24 requests, flags, and resolves.",
    "opregion-safety": "The stem mission keeps one ownship on a compact transit through configured operating-region envelopes. Case overlays reshape save/halt regions or timing parameters so the behavior's safety flags and breach handling can be graded directly.",
    "waypoint-behavior-motion": "The stem mission keeps one simulated vehicle on a short waypoint corridor. Case overlays change route shape, capture settings, runtime point updates, or status variables while the mission grades behavior-owned completion evidence.",
    "loiter-behavior-motion": "The stem mission starts one simulated vehicle near a compact loiter area. Case overlays vary polygon geometry, acquisition conditions, center updates, and speed behavior while grading loiter-owned status outputs.",
    "stationkeep-behavior-motion": "The stem mission starts one simulated vehicle near a station point. Case overlays change the station geometry, hibernation settings, runtime retargeting, and speed/radius settings while grading mode and distance outputs.",
    "trail-behavior-motion": "The stem mission uses two simulated vehicles: `abe` runs BHV_Trail while `ben` provides the moving contact track. Case overlays vary trailing geometry, relevance settings, runtime updates, and missing-contact behavior.",
    "convoy-behavior-motion": "The stem mission uses two simulated vehicles: `abe` runs BHV_Convoy while `ben` creates the breadcrumb trail. Case overlays vary mark queues, following geometry, speed branches, and runtime updates.",
    "cutrange-behavior-motion": "The stem mission uses two simulated vehicles: `abe` runs BHV_CutRange and tries to reduce range to `ben`. Case overlays vary target route geometry, relevance distances, give-up conditions, runtime updates, and warning/error paths.",
    "fixedturn-behavior-motion": "The stem mission runs one simulated vehicle through a short approach leg before activating BHV_FixedTurn. Case overlays vary turn direction, fixed-turn magnitude, scheduled turn specifications, speed selection, and timeout behavior.",
    "periodic-speed-behavior-motion": "The stem mission runs one simulated vehicle with BHV_ConstantHeading providing course control while BHV_PeriodicSpeed owns the speed objective. Case overlays vary startup mode, lazy/busy periods, reset policy, alias parameters, period speed, and malformed parameter values while the evaluator grades behavior status variables and observed NAV_SPEED.",
    "memoryturnlimit-behavior-motion": "The stem mission runs one simulated vehicle with a constant speed objective, a sustained constant-heading turn demand, and BHV_MemoryTurnLimit as the evaluated limiter. Case overlays vary memory_time, turn_range, priority weight, speed, runtime updates, and malformed or missing configuration while the evaluator grades MEM_HDG_AVG, NAV_HEADING, NAV_SPEED, heading mismatch, and warning/error state.",
    "timer-behavior-motion": "The stem mission runs one simulated vehicle through a short waypoint leg while BHV_Timer is held idle and then activated. Case overlays vary status variable names, suffixes, activation timing, and malformed status configuration while the evaluator grades timer-posted counters.",
    "hostinfo-unit": "The stem mission runs a single shoreside MOOS community with pHostInfo, uTimerScript, pAutoPoke, and pMissionEval. Case overlays change only pHostInfo configuration and mission-owned host-info pass/fail conditions.",
    "loadwatch-unit": "The stem mission runs a single shoreside MOOS community with uLoadWatch, uTimerScript, pAutoPoke, and pMissionEval. Case overlays change only load-watch configuration, scripted DB_UPTIME mail, and mission-owned threshold pass/fail conditions.",
    "processwatch-unit": "The stem mission runs a single shoreside MOOS community with uProcessWatch plus small watched peer apps. Case overlays change only process-watch configuration and mission-owned process-presence pass/fail conditions.",
    "pshare-unit": "The stem mission runs two local MOOS communities connected by pShare. Case overlays change only pShare route configuration, scripted sender mail, and receiver-side mission-owned pass/fail conditions.",
    "pshare-topology": "The stem mission runs four local MOOS communities: a shoreside evaluator, two sender peers, and one relay/listener peer. Case overlays keep the topology fixed while changing pShare routes, scripted sender mail, and the evaluator conditions needed to prove multi-peer delivery.",
    "plogger-unit": "The stem mission runs a single shoreside MOOS community with pLogger, uTimerScript, pMissionEval, and pMissionHash. The harness adds focused .alog/.slog/.xlog/copied-file checks because the logged files are the behavior under test.",
    "pantler-unit": "The stem mission runs a single shoreside MOOS community whose graded flags come from apps started by pAntler. Case overlays change the ANTLER launch block, matching aliased app config blocks, launcher-supplied filter argument, system path lookup, and extra process parameter forwarding.",
    "pnodereporter-unit": "The stem mission runs a single MOOS community with pNodeReporter, uTimerScript, pMissionEval, pAutoPoke, pMissionHash, and logging/watchdog support. Case overlays change only reporter configuration, scripted nav/helm/platform mail, and mission-owned report pass/fail conditions.",
    "upokedb-unit": "The stem mission runs one MOOS community with MOOSDB, pLogger, pMissionEval, and pMissionHash. The harness runs uPokeDB externally against that live DB, then pMissionEval grades the exact variables that should have been posted.",
    "uxms-unit": "The stem mission runs one MOOS community with uTimerScript publishing controlled mail and pMissionEval proving publisher readiness. The harness runs bounded uXMS terminal captures and grades required and forbidden display tokens.",
    "uquerydb-unit": "The stem mission runs one MOOS community with uTimerScript publishing controlled query variables and pMissionEval proving publisher readiness. The harness runs bounded uQueryDB invocations and grades return codes plus .checkvars content.",
    "pechovar-unit": "The stem mission runs one MOOS community with pEchoVar, uTimerScript, pMissionEval, pMissionHash, and pLogger. The harness writes case-specific echo/flip mappings and scripted source mail, then grades direct echo variables plus alog evidence for structured EFlipper payloads and suppression.",
    "utimerscript-unit": "The stem mission runs one MOOS community with uTimerScript, pMissionEval, pMissionHash, and pLogger. The harness writes case-specific script/evaluator blocks, uses external uPokeDB for control mail, and starts one delayed uXMS client for the block-on contract.",
    "pdeadmanpost-unit": "The stem mission runs one MOOS community with pDeadManPost and a case-generated heartbeat schedule. The harness grades exact deadflag variables and absence conditions through pMissionEval, then uses alog counts for policy cases where posting multiplicity matters.",
    "pspoofnode-unit": "The stem mission runs one MOOS community with pSpoofNode and case-generated spoof/cancel mail. The harness uses pMissionEval for readiness and alog checks for structured NODE_REPORT payload fields.",
    "utermcommand-unit": "The stem mission runs one MOOS community with MOOSDB, pMissionEval, and logging while the harness drives uTermCommand externally through stdin and grades the resulting posts.",
    "psearchgrid-unit": "The stem mission runs one MOOS community with pSearchGrid and case-generated NODE_REPORT mail. The harness uses pMissionEval for readiness and alog payload checks for grid and delta publications.",
    "ufield-comms-unit": "The stem mission runs one shoreside community and two static vehicle communities with uFldNodeComms, uFldNodeBroker, uFldShoreBroker, pShare, uTimerScript, and pMissionEval. Case overlays change communication policy and scripted report/message traffic while the harness verifies payload-level effects.",
    "ufield-broker-bridge": "The stem mission runs the same two-vehicle uField setup but focuses on broker configuration. Case overlays change shore broker bridges, vnode discovery, keywords, mediated node bridging, and auto-bridge settings while the harness verifies broker pShare command output.",
    "ufield-route-resilience": "The stem mission runs the same two static vehicle communities and one shoreside community, but startup and runtime route setup is delayed, invalid, duplicated, partially supplied, or supplied by shore vnode discovery. The mission grade proves communications recovered or intentionally failed, and harness alog checks prove which route path was used.",
    "ufld-obstacle-sim-unit": "The stem mission runs one shoreside community with uFldObstacleSim, uTimerScript, one stock pEchoVar adapter, pMissionEval, pMissionHash, and pLogger. Case overlays own scripted inputs, subject settings, and parser-safe mission-owned grading; the shell only prepares, schedules, and aggregates results.",
    "ufld-pathcheck-unit": "The shared uField app stem mission runs a single shoreside MOOS community with one selected app, uTimerScript, pMissionEval, and pLogger. This harness generates case-specific uFldPathCheck config and scripted node-report mail, then checks path and speed report payloads from the alog.",
    "ufld-message-handler-unit": "The shared uField app stem mission runs a single shoreside MOOS community with one selected app, uTimerScript, pMissionEval, and pLogger. This harness generates case-specific uFldMessageHandler config and scripted NODE_MESSAGE mail, then checks forwarded variables, counters, flags, and expected absence from the alog.",
    "ufld-contact-range-sensor-unit": "The shared uField app stem mission runs a single shoreside MOOS community with one selected app, uTimerScript, pMissionEval, and pLogger. This harness scripts static contact geometry and range requests, then checks range-report, ground-truth, and pulse outputs from the alog.",
    "ufld-beacon-range-sensor-unit": "The shared uField app stem mission runs a single shoreside MOOS community with one selected app, uTimerScript, pMissionEval, and pLogger. This harness scripts static node and beacon geometry, then checks beacon range-report, ground-truth, marker, pulse, local-report, and ping-payment outputs from the alog.",
    "ufld-collision-detect-unit": "The shared uField app stem mission runs a single shoreside MOOS community with one selected app, uTimerScript, pMissionEval, and pLogger. This harness scripts controlled contact report sequences, then checks encounter ranking, counters, closest-range state, filters, ring/pulse controls, range normalization, conditions, and flag outputs from the alog.",
    "ufld-collob-detect-unit": "The shared uField app stem mission runs a single shoreside MOOS community with one selected app, uTimerScript, pMissionEval, and pLogger. This harness scripts known-obstacle and node-report geometry, then checks obstacle encounter, near-miss, collision, range-normalization, global-minimum, and flag outputs from the alog.",
    "ufld-scope-unit": "The shared uField app stem mission runs a single shoreside MOOS community with one selected app, uTimerScript, pMissionEval, and pLogger. This harness scripts scoped MOOS mail and appcast requests, then checks only uFldScope appcast payloads for table content and recovery behavior.",
    "pmissioneval-unit": "The stem mission runs a single shoreside MOOS community with pMissionHash, pMissionEval, uTimerScript, logging, and process-watch support. Case overlays change pMissionEval configuration and scripted MOOS mail while the harness starts uniquely aliased uMayFinish instances so completion remains observable.",
    "pmissionhash-unit": "The stem mission runs a single shoreside MOOS community with pMissionHash, pMissionEval, uTimerScript, logging, and process-watch support. Case overlays change pMissionHash settings while pMissionEval consumes the hash mail as the mission-owned grader.",
    "umayfinish-unit": "The stem mission runs a single shoreside MOOS community with pMissionEval, uTimerScript, logging, and process-watch support. The harness starts uMayFinish directly with unique aliases so each case can assert the process exit code.",
    "zigzag-behavior-motion": "The stem mission runs one simulated vehicle through a short approach leg before activating BHV_ZigZag. Case overlays vary first-side selection, angle limits, completion settings, active-time capture settings, runtime speed updates, and malformed behavior parameters.",
    "legrun-behavior-motion": "The stem mission runs one simulated vehicle on a compact two-leg LegRun pattern. Case overlays vary geometry input form, initialization mode, capture and turn controls, scheduled speeds, runtime updates, event flags, and malformed behavior parameters.",
    "shadow-behavior-motion": "The stem mission uses two simulated vehicles: `abe` runs BHV_Shadow while `ben` provides controlled contact headings and speeds. Case overlays vary target motion, relevance distance, runtime updates, and missing-contact behavior.",
    "performance-obstacle-gauntlet": "The stem mission is a repeatable obstacle-field loop. Individual cases change field density or duration so the same avoidance stack can be tested under baseline, dense, and longer-running pressure.",
    "performance-colregs-joust": "The stem mission creates sustained two- or three-vehicle COLREGS encounters. Cases adjust traffic density and duration to test whether safe spacing holds beyond a single isolated encounter.",
    "performance-traffic-ring": "The stem mission keeps five vehicles moving through a fixed-seed traffic-ring assignment pattern. Runs remain comparable for CI while asynchronous completion can change the exact assignment order.",
}


def repo_url(path: str) -> str:
    return f"{REPO_BLOB}/{path}"


def ctest_targets():
    if str(SCRIPTS_DIR) not in sys.path:
        sys.path.insert(0, str(SCRIPTS_DIR))
    import check_cpp_tests

    return check_cpp_tests.all_targets()


def count_gtest_cases(path: Path) -> int:
    count = 0
    for source in path.rglob("*Test.cpp"):
        text = source.read_text(encoding="utf-8", errors="ignore")
        count += len(re.findall(r"^\s*TEST(?:_F)?\s*\(", text, re.MULTILINE))
    return count


def ctest_area_label(area: str) -> str:
    explicit = {
        "alogavg": "ALog Average",
        "alogbin": "ALog Bin",
        "alogcat": "ALog Cat",
        "alogcd": "ALog Collision Detect",
        "alogcheck": "ALog Check",
        "alogclip": "ALog Clip",
        "alogeplot": "ALog EPlot",
        "alogeval": "ALog Eval",
        "aloggrep": "ALog Grep",
        "aloghelm": "ALog Helm",
        "alogiter": "ALog Iter",
        "alogload": "ALog Load",
        "alogmhash": "ALog Mission Hash",
        "alogpare": "ALog Pare",
        "alogpick": "ALog Pick",
        "alogrm": "ALog Remove",
        "alogscan": "ALog Scan",
        "alogsort": "ALog Sort",
        "alogsplit": "ALog Split",
        "alogtest": "ALog Test",
        "alogtm": "ALog Time Mark",
        "apputil": "App Utilities",
        "behaviors": "Behavior Core",
        "behaviors_colregs": "COLREGS Behaviors",
        "behaviors_marine": "Marine Behaviors",
        "bhvutil": "Behavior Utilities",
        "contacts": "Contact Records",
        "dep_behaviors": "Deprecated Behaviors",
        "encounters": "Encounters",
        "evalutil": "Evaluation Utilities",
        "gen_moos_app": "MOOS App Generator",
        "genutil": "General Utilities",
        "geodaid": "Geodesy Aids",
        "helmivp": "Helm IvP",
        "ipfview": "IPF View",
        "isay": "iSay",
        "uhelmscope": "uHelmScope",
        "ivpbuild": "IvP Build",
        "ivpcore": "IvP Core",
        "ivpsolve": "IvP Solve",
        "logutils": "Log Utilities",
        "marine_pid": "Marine PID",
        "marineview": "Marine Viewer",
        "mbutil": "MB Utilities",
        "manifest": "Manifest",
        "moosgeodesy": "MOOS Geodesy",
        "nspatch": "NSPatch",
        "nsplug": "NSPlug",
        "obstacles": "Obstacles",
        "pechovar": "pEchoVar",
        "pickpos": "Pick Position",
        "pluck": "Pluck",
        "polar": "Polar Geometry",
        "prealm": "pRealm",
        "projfield": "Project Field",
        "realm": "Realm Core",
        "survey": "Survey Utilities",
        "tagrep": "Tag Replace",
        "turngeo": "Turn Geometry",
        "ucommand": "Command Utilities",
        "ufield": "Field Utilities",
        "ufldbeaconrangesensor": "uFldBeaconRangeSensor",
        "ufldcollisiondetect": "uFldCollisionDetect",
        "uflddelve": "uFldDelve",
        "uplotviewer": "uPlotViewer",
        "utimerscript": "uTimerScript",
        "zaicview": "ZAIC View",
    }
    if area in explicit:
        return explicit[area]
    return area.replace("_", " ").title()


def ctest_area_description(area: str) -> str:
    explicit = {
        "alogavg": "ALog averaging handlers, time-window parsing, numeric aggregation, and malformed log-input edges.",
        "alogbin": "ALog binning handlers, variable bucketing, interval boundaries, and report formatting.",
        "alogcat": "ALog concatenation handlers, file ordering, header handling, and timestamp normalization.",
        "alogcd": "ALog collision-detection reporting over contact and CPA-related log records.",
        "alogcheck": "ALog check condition parsing, log evaluation, pass/fail reporting, and malformed specification handling.",
        "alogclip": "ALog clipping handlers, inclusive time windows, header preservation, preserved variables, and CLI-facing prechecks.",
        "alogeplot": "ALog expression plotting helpers, variable extraction, source filtering, and expression/report behavior.",
        "alogeval": "ALog evaluation helpers for expression parsing, time windows, condition handling, and result summaries.",
        "aloggrep": "ALog grep handlers, variable/source filters, time gates, format options, and malformed selector handling.",
        "aloghelm": "ALog helm report extraction, helm summary parsing, iteration handling, and report formatting.",
        "alogiter": "ALog iteration handlers, timestamp bucketing, iteration boundaries, and summary output.",
        "alogload": "ALog load-report helpers, per-app load parsing, threshold handling, and output summaries.",
        "alogmhash": "ALog mission-hash reporting, hash extraction, missing-field behavior, and report formatting.",
        "alogpare": "ALog pare engine behavior for variable/source filtering, retained records, and file output.",
        "alogpick": "ALog pick handlers for field selection, output formatting, and malformed selector behavior.",
        "alogrm": "ALog removal filters, variable/source exclusion, retained headers, and filter edge cases.",
        "alogscan": "ALog scan handlers, variable discovery, source summaries, and scan-output formatting.",
        "alogsort": "ALog sort handlers, timestamp ordering, stable header behavior, and malformed-line handling.",
        "alogsplit": "ALog split handlers, split-key parsing, output naming, batch behavior, and file prechecks.",
        "alogtest": "ALog test condition parsing, truth evaluation, time-window checks, and result reporting.",
        "alogtm": "ALog time-mark grep handlers, mark selection, time extraction, and malformed marker handling.",
        "apputil": "AppCast, InfoCast, and display-formatting helpers used by app-facing utilities.",
        "behaviors": "Core IvP behavior state, contact behavior state, and lifecycle records.",
        "behaviors_colregs": "COLREGS behavior support logic, velocity filtering, AOF helpers, and behavior contracts.",
        "behaviors_marine": "Marine behavior implementations such as waypoint, loiter, station keeping, collision avoidance, and obstacle avoidance.",
        "bhvutil": "Behavior utility engines, AOF helpers, refineries, waypoint/loiter helpers, and fixed-turn support.",
        "contacts": "Node record and rider parsing, serialization, and contact-report behavior.",
        "dep_behaviors": "Deprecated behavior and obstacle-model code kept under regression coverage.",
        "encounters": "CPA encounter events and alog-facing encounter records.",
        "evalutil": "Mission-evaluation helpers, logic-test sequences, and variable-check utilities.",
        "gen_moos_app": "MOOS app generator source transformations, file planning, naming rules, and generated text checks.",
        "genutil": "General-purpose string, file, pipe, and utility helpers.",
        "geodaid": "Contact-ledger and geodesy-aid logic used by contact-aware apps.",
        "geometry": "Geometry primitives, parsers, CPA utilities, shape lifecycles, grids, paths, and polygon generation.",
        "helmivp": "Helm behavior-loading and core helm state helpers.",
        "ipfview": "IPF viewer parsing and model support.",
        "isay": "iSay utterance parsing, voice validation, priority queue ordering, and audio-command-adjacent helper behavior.",
        "uhelmscope": "uHelmScope behavior records, iteration-block parsing, behavior-list summaries, decision-variable tracking, and mode formatting.",
        "ivpbuild": "AOFs, ZAICs, PDMaps, reflector internals, and IvP function construction.",
        "ivpcore": "Core IvP objects, domains, boxes, functions, and priority data structures.",
        "ivpsolve": "IvP problem-solving and encoded-function behavior.",
        "logic": "Logic conditions, info buffers, conditional ledgers, and related parsing helpers.",
        "logutils": "ALog parsing, log files, plot data, app logs, and analysis-plot utilities.",
        "manifest": "Manifest file parsing, population, and manifest-set behavior.",
        "marine_pid": "Marine PID engines and pMarinePIDV22 app-level control logic.",
        "marineview": "Marine viewer shapes, GUI-adjacent models, image handling, and viewer support classes.",
        "mbutil": "MOOS-IvP utility objects, formatting, timers, macros, hashes, JSON helpers, and node messages.",
        "moosgeodesy": "WGS-84 datum initialization, UTM and local-grid projection, inverse conversion, zone and latitude-band boundaries, safe value semantics, and four disabled PROJ-migration contracts for seam continuity and input validation.",
        "nspatch": "NSPatch patch-file parsing, named-block replacement, line patch behavior, and conflict/edge semantics.",
        "nsplug": "NSPlug expansion helpers, macro handling, conditional expansion, and template-processing behavior.",
        "obstacles": "Obstacle parsing, representation, and obstacle-manager support objects.",
        "pechovar": "pEchoVar EFlipper parsing, component mapping, separator handling, and filter suppression behavior.",
        "pickpos": "Pick-position parsing, geometry selection, output formatting, and invalid-input handling.",
        "pluck": "Pluck handlers for extracting selected fields, formatting output, and rejecting malformed requests.",
        "polar": "Polar plotting and simulator-facing polar helpers.",
        "prealm": "pRealm PipeWay parsing, display flag handling, expiry math, content descriptors, and equality semantics.",
        "projfield": "Field projection helpers, input parsing, projection geometry, and output formatting.",
        "realm": "RealmCast and WatchCast core records and channel logic.",
        "survey": "Survey pattern generation and survey-update helpers.",
        "tagrep": "Tag replacement handlers, tag parsing, replacement rules, and malformed template behavior.",
        "turngeo": "Turn-generation geometry and leg-run turn helpers.",
        "ucommand": "Command item, command folio, command summary, and command-routing helpers.",
        "ufield": "Field utilities, host records, pShare-facing records, and field communication helpers.",
        "ufldbeaconrangesensor": "uFldBeaconRangeSensor beacon-buoy state, frequency parsing, range settings, drawing hints, counters, and spec formatting.",
        "ufldcollisiondetect": "uFldCollisionDetect CPA monitor state, NODE_REPORT admission, group filters, range thresholds, contact density, and CPA event emission.",
        "uflddelve": "uFldDelve transmission records, message counters, latest-source tracking, rate-window math, and pruning boundaries.",
        "uplotviewer": "uPlotViewer partition records, histogram bucket boundaries, running averages, range filtering, and color/name helpers.",
        "utimerscript": "uTimerScript random variables, random pairs, event parsing, scheduling helpers, math macro expansion, and block-app handling.",
        "zaicview": "ZAIC viewer models and GUI-adjacent support code.",
    }
    if area in explicit:
        return explicit[area]
    return f"Source-level checks for the {ctest_area_label(area)} component group."


def ctest_area_rows(targets=None) -> list[CTestArea]:
    targets = list(ctest_targets() if targets is None else targets)
    area_targets: dict[str, list[object]] = {}
    for target in targets:
        area = target.file.relative_to(CPP_TEST_DIR).parts[0]
        area_targets.setdefault(area, []).append(target)

    areas: list[CTestArea] = []
    for area, grouped_targets in area_targets.items():
        area_path = CPP_TEST_DIR / area
        labels: set[str] = set()
        for target in grouped_targets:
            labels.update(target.values("LABELS"))
        areas.append(
            CTestArea(
                key=area,
                label=ctest_area_label(area),
                target_count=len(grouped_targets),
                source_count=sum(1 for _ in area_path.rglob("*Test.cpp")),
                case_count=count_gtest_cases(area_path),
                description=ctest_area_description(area),
                labels=tuple(sorted(label for label in labels if label)),
                path=f"tests/cpp/{area}",
            )
        )
    return sorted(areas, key=lambda item: (-item.target_count, item.label))


def ctest_total_target_count(targets=None) -> int:
    return len(list(ctest_targets() if targets is None else targets))


def ctest_total_source_count() -> int:
    return sum(1 for _ in CPP_TEST_DIR.rglob("*Test.cpp"))


def ctest_total_case_count() -> int:
    return count_gtest_cases(CPP_TEST_DIR)


def ctest_area_count(targets=None) -> int:
    return len(ctest_area_rows(targets))


def inline_code(text: str) -> str:
    parts = re.split(r"(`[^`]+`)", text)
    rendered: list[str] = []
    for part in parts:
        if part.startswith("`") and part.endswith("`"):
            rendered.append(f"<code>{escape(part[1:-1])}</code>")
        else:
            rendered.append(escape(part))
    return "".join(rendered)


def page_shell(title: str, body: str, prefix: str = "") -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{escape(title)} | MOOS-IvP CI/CD</title>
  <link rel="stylesheet" href="{prefix}styles.css?v={ASSET_VERSION}">
  <script src="{prefix}theme.js?v={ASSET_VERSION}"></script>
</head>
<body>
  <header class="site-header">
    <a class="brand" href="{prefix}index.html">
      <span class="brand-mark">CI</span>
      <span>MOOS-IvP CI/CD</span>
    </a>
    <div class="header-actions">
      <nav>
        <a href="{prefix}quick-start.html">Quick Start</a>
        <a href="{prefix}index.html#families">Harnesses</a>
        <a href="{prefix}ctest-coverage.html">Unit Tests</a>
        <a href="{prefix}examples.html">Examples</a>
      </nav>
      <label class="theme-switch" title="Toggle Frost theme">
        <input type="checkbox" data-theme-toggle aria-label="Frost theme">
        <span class="theme-switch-track" aria-hidden="true"><!-- CSS-rendered track --></span>
      </label>
    </div>
  </header>
  {body}
  <footer class="site-footer">
    <span>Overview site for the MOOS-IvP CI/CD test workspace.</span>
    <span>Source mission and harness links are included for readers who want implementation detail.</span>
  </footer>
</body>
</html>
"""


def phrase_colregs_case(case_name: str) -> str:
    name = case_name.removesuffix("_pass")
    name = name.removesuffix("_execution")
    name = name.replace("_execution", "")

    mirror = " Mirrored geometry checks the same branch on the opposite side." if "_mirror" in name else ""
    spacing = ""
    if "_far" in name or "_range_far" in name:
        spacing = " with a longer-range setup"
    elif "_close" in name:
        spacing = " with a tighter setup"
    elif "_small_gap" in name:
        spacing = " with a smaller lateral gap"
    elif "_large_gap" in name:
        spacing = " with a larger lateral gap"
    elif "_midrange" in name:
        spacing = " with a midrange live-encounter setup"

    if name.startswith("head_on_cpa_fallback"):
        return f"Near-head-on geometry expected to fall back to CPA rather than true head-on classification{spacing}."
    if name.startswith("head_on_port_offset"):
        return "Offset head-on encounter on the port side; expected to remain in the head-on family."
    if name.startswith("head_on_starboard_offset"):
        return "Offset head-on encounter on the starboard side; expected to remain in the head-on family."
    if name.startswith("head_on"):
        return f"Head-on encounter used to check the head-on COLREGS branch{spacing}."

    if name.startswith("crossing_starboard_giveway"):
        return f"Starboard crossing where ownship should take the give-way role{spacing}."
    if name.startswith("crossing_port_standon_close_unsure_bow"):
        return "Tight port-side crossing expected to enter the stand-on unsure-bow branch before resolving."
    if name.startswith("crossing_port_standon_unsure_bow"):
        return "Port-side crossing expected to enter the stand-on unsure-bow branch before resolving."
    if name.startswith("crossing_port_standon_stern"):
        return "Port-side crossing expected to settle into the stand-on stern branch."
    if name.startswith("crossing_port_standon_unsure"):
        return "Port-side crossing expected to enter the generic stand-on unsure branch."
    if name.startswith("crossing_port_standon"):
        return f"Port-side crossing where ownship should stand on{spacing}."

    if name.startswith("overtaking_starboard"):
        side = "mirrored passing side" if "_mirror" in name else "starboard passing side"
        return f"Ownship overtakes on the {side}{spacing}; classification should remain in the overtaking family.{mirror}"
    if name.startswith("overtaken_port"):
        return f"Ownship is being overtaken on its port side{spacing}; the stand-on overtaken role should be preserved."
    if name.startswith("overtaken_starboard"):
        return f"Ownship is being overtaken on its starboard side{spacing}; the stand-on overtaken role should be preserved."

    return ""


def phrase_threshold_case(case_name: str) -> str:
    name = case_name.removesuffix("_pass")
    mirror = " mirrored" if name.endswith("_mirror") or "_mirror_" in name else ""
    base = name.replace("_mirror", "")

    side = ""
    if "_below" in base:
        side = "below"
    elif "_edge" in base:
        side = "at the calibrated edge of"
    elif "_above" in base:
        side = "above"

    if base.startswith("head_on_thresh"):
        return f"Probes {side} the head-on entry cutoff{mirror}; expected classification should land on the calibrated side of head-on vs CPA."
    if base.startswith("giveway_bowdist"):
        return f"Probes {side} the give-way bow-distance split{mirror}; expected classification should stay stern-side or flip bow-side as calibrated."
    if base.startswith("giveway_turngap"):
        return f"Probes {side} the give-way turn-gap split{mirror}; expected classification should follow the stock turn-gap branch."
    if base.startswith("standon_unsurebow"):
        return f"Probes {side} the stand-on unsure-bow transition; expected classification should remain on the calibrated side of unsure-bow vs bow."
    if base.startswith("standon_band350_unsurebow_alt"):
        return "Alternate band-350 stand-on geometry expected to remain in the unsure-bow branch."
    if base.startswith("standon_band350_unsurebow"):
        return "Band-350 stand-on geometry expected to remain in the unsure-bow branch."
    if base.startswith("standon_band350_bow"):
        return "Band-350 stand-on geometry expected to resolve to the bow branch."
    if base.startswith("standon_band315_unsure_bow"):
        return "Band-315 stand-on geometry expected to enter the unsure-bow branch."
    if base.startswith("standon_band315_unsure"):
        return "Band-315 stand-on geometry expected to enter the generic unsure branch."
    if base.startswith("standon_band315_bow"):
        return "Band-315 stand-on geometry expected to resolve to the bow branch."
    if base.startswith("standon_band270_stern"):
        return "Band-270 stand-on geometry expected to resolve to the stern branch."
    if base.startswith("standon_southwest_unsurebow"):
        return "Southwest stand-on probe expected to enter the unsure-bow branch."
    if base.startswith("standon_southwest_unsure"):
        return "Southwest stand-on probe expected to enter the generic unsure branch."
    if base.startswith("standon_southwest_stern"):
        return "Southwest stand-on probe expected to resolve to the stern branch."
    if base.startswith("standon_ot_inextremis_range"):
        return f"Probes {side} the overtaken-vessel in-extremis range cutoff; expected classification should follow the calibrated range branch."
    if base.startswith("standon_ot_inextremis_cpa"):
        return f"Probes {side} the overtaken-vessel in-extremis CPA cutoff; expected classification should follow the calibrated CPA branch."
    if base.startswith("standon_inextremis_range"):
        return f"Probes {side} the stand-on in-extremis range cutoff; expected classification should follow the calibrated range branch."
    if base.startswith("standon_inextremis_cpa"):
        return f"Probes {side} the stand-on in-extremis CPA cutoff; expected classification should follow the calibrated CPA branch."
    if base.startswith("overtaking_thresh"):
        return f"Probes {side} the overtaking classification threshold{mirror}; expected classification should stay on the calibrated side of overtaking vs fallback."
    if base.startswith("overtaken_thresh"):
        return f"Probes {side} the overtaken-vessel classification threshold{mirror}; expected classification should stay on the calibrated side of stand-on overtaken vs fallback."
    if base.startswith("outer_dist"):
        return f"Probes {side} the COLREGS outer-distance relevance gate; expected behavior should activate only on the calibrated side."
    return ""


def phrase_parameter_case(case_name: str) -> str:
    name = case_name.removesuffix("_pass")
    if name.startswith("min_util_cpa_"):
        level = name.removeprefix("min_util_cpa_")
        return f"Runs fixed stand-on geometry with {level} `min_util_cpa_dist`; expected classification should reflect the CPA-distance setting."
    if name.startswith("headon_only_"):
        state = name.removeprefix("headon_only_")
        return f"Runs crossing geometry with `headon_only={state}` to verify non-head-on encounters are either admitted or demoted as expected."
    if name.startswith("giveway_bow_dist_"):
        level = name.removeprefix("giveway_bow_dist_")
        return f"Runs fixed give-way bow-distance geometry with the {level} threshold setting."
    if name.startswith("max_util_cpa_"):
        level = name.removeprefix("max_util_cpa_")
        return f"Runs fixed stand-on geometry with {level} `max_util_cpa_dist`; expected classification should reflect the widened CPA envelope."
    if name.startswith("velocity_filter_"):
        state = name.removeprefix("velocity_filter_")
        return f"Runs fixed stand-on geometry with velocity filtering {state}; expected classification should show whether the filter changes effective CPA evaluation."
    if name.startswith("eval_tol_"):
        level = name.removeprefix("eval_tol_")
        return f"Runs fixed overtaking geometry with {level} `eval_tol`; expected execution quality should remain in the configured CPA band."
    if name.startswith("pwt_outer_dist_"):
        level = name.removeprefix("pwt_outer_dist_")
        return f"Runs fixed range-gate geometry with {level} `pwt_outer_dist`; expected relevance should admit or suppress COLREGS behavior accordingly."
    if name.startswith("pwt_inner_dist_"):
        level = name.removeprefix("pwt_inner_dist_")
        return f"Runs fixed stand-on geometry with {level} `pwt_inner_dist`; expected posted priority weight should follow the configured inner-distance band."
    if name.startswith("pwt_grade_"):
        grade = name.removeprefix("pwt_grade_")
        return f"Runs fixed relevance geometry with `pwt_grade={grade}` and checks the expected priority-weight curve."
    if name.startswith("pts_port_turns_ok_"):
        state = name.removeprefix("pts_port_turns_ok_")
        return f"Runs fixed give-way geometry with `pts_port_turns_ok={state}` and checks the early side relationship."
    if name.startswith("turn_radius_"):
        level = name.removeprefix("turn_radius_")
        return f"Runs fixed give-way turn-gap geometry with {level} `turn_radius`; expected classification should reflect the turn-radius branch."
    if name.startswith("check_plateaus_"):
        state = name.removeprefix("check_plateaus_")
        return f"Runs CPA fallback geometry with `check_plateaus={state}` and checks whether refinery diagnostics are posted."
    if name.startswith("completed_dist_"):
        level = name.removeprefix("completed_dist_")
        return f"Runs CPA fallback geometry with {level} `completed_dist` and checks whether the encounter has completed at the shared checkpoint."
    if name.startswith("refinery_"):
        state = name.removeprefix("refinery_")
        return f"Runs CPA fallback geometry with refinery {state}; expected classification should remain CPA while diagnostics follow the refinery setting."
    return ""


def phrase_performance_case(slug: str, case_name: str) -> str:
    if slug == "performance-obstacle-gauntlet":
        return {
            "baseline_field_pass": "Baseline obstacle-field traversal; expected to complete the loop with zero collisions and clean warning logs.",
            "dense_field_pass": "Denser obstacle-field traversal; expected to preserve clean completion under heavier obstacle pressure.",
            "endurance_random_pass": "Longer randomized obstacle-field run; expected to preserve completion and safety over an extended field.",
        }.get(case_name, "")
    if slug == "performance-colregs-joust":
        return {
            "baseline_colregs_pass": "Baseline sustained COLREGS joust; expected to complete with zero collisions and safe closest-range telemetry.",
            "dense_colregs_pass": "Denser COLREGS joust; expected to preserve safe spacing under added multi-vehicle pressure.",
            "endurance_colregs_pass": "Longer COLREGS joust; expected to preserve warning-free, collision-free behavior over an extended run.",
        }.get(case_name, "")
    if slug == "performance-traffic-ring":
        return {
            "baseline_circle_pass": "Baseline fixed-seed five-vehicle traffic ring; expected to maintain assignment activity with zero collisions.",
            "mixed_speed_circle_pass": "Traffic ring with mixed vehicle speeds; expected to keep assignment pressure active while remaining collision-free.",
            "endurance_circle_pass": "Longer traffic-ring run; expected to sustain repeated assignments over the endurance window with zero collisions.",
            "noncoop_circle_pass": "Traffic ring with one non-cooperative vehicle; expected to remain collision-free while `eve` runs with avoidance disabled.",
        }.get(case_name, "")
    return ""


def describe_case(slug: str, case_name: str) -> str:
    explicit_cases = {
        "reset_false_visual_pass": "Slower visual version of reset_upon_running=false: RUN_PS_ALL turns off, the timer continues aging, and speed returns after re-enable.",
    }
    if case_name in explicit_cases:
        return explicit_cases[case_name]

    if slug == "colregs-thresholds":
        desc = phrase_threshold_case(case_name)
    elif slug == "colregs-parameters":
        desc = phrase_parameter_case(case_name)
    elif slug in {"colregs-classification", "colregs-execution"}:
        desc = phrase_colregs_case(case_name)
        if slug == "colregs-execution" and desc:
            desc = desc.replace("classification", "realized maneuver").replace("classify", "complete")
    elif slug.startswith("performance-"):
        desc = phrase_performance_case(slug, case_name)
    else:
        desc = ""

    if desc:
        return desc

    clean = case_name.replace("_", " ").replace("-", " ")
    clean = re.sub(r"\bpass\b", "expected pass", clean)
    clean = re.sub(r"\bfail\b", "expected fail", clean)
    clean = re.sub(r"\babsent\b", "absence check", clean)
    return f"Covers {clean}."


def normalize_description(text: str, max_len: int | None = 165) -> str:
    text = text.replace("`", "")
    text = re.sub(r"\bpatched mission\b", "case", text, flags=re.IGNORECASE)
    text = re.sub(r"\bis patched to\b", "is configured in this case to", text, flags=re.IGNORECASE)
    text = re.sub(r"\bis patched with\b", "is configured in this case with", text, flags=re.IGNORECASE)
    text = re.sub(r"\bis patched so\b", "is configured in this case so", text, flags=re.IGNORECASE)
    text = re.sub(r"\bthe behavior patch sets\b", "this case sets", text, flags=re.IGNORECASE)
    text = re.sub(r"\bthe behavior patch provides\b", "this case provides", text, flags=re.IGNORECASE)
    text = re.sub(r"\bpatched\b", "configured for this case", text, flags=re.IGNORECASE)
    text = re.sub(r"\s+", " ", text).strip()
    text = text.strip(" :-")
    if not text:
        return ""
    if max_len is not None and len(text) > max_len:
        text = text[: max_len - 3].rsplit(" ", 1)[0] + "..."
    return text


def zlaunch_case_order(h: Harness) -> list[str]:
    zlaunch = ROOT.parent / h.path / "zlaunch.sh"
    if not zlaunch.exists():
        return []

    text = zlaunch.read_text(encoding="utf-8", errors="ignore")
    return zlaunch_all_cases(text)


def zlaunch_all_cases(text: str) -> list[str]:
    arrays: dict[str, list[str]] = {}
    for match in CASE_ARRAY_RE.finditer(text):
        name, body = match.groups()
        try:
            arrays[name] = shlex.split(body, comments=True, posix=True)
        except ValueError:
            arrays[name] = CASE_NAME_RE.findall(body)

    root_array = "ALL_CASES" if "ALL_CASES" in arrays else "CASES"
    if root_array not in arrays:
        return []

    def expand_array(name: str, stack: tuple[str, ...] = ()) -> list[str]:
        if name in stack:
            return []
        expanded: list[str] = []
        for token in arrays.get(name, []):
            ref = ARRAY_REF_RE.match(token)
            if ref and ref.group(1) in arrays:
                expanded.extend(expand_array(ref.group(1), stack + (name,)))
            elif CASE_NAME_RE.search(token):
                expanded.append(token)
        return expanded

    names: list[str] = []
    seen: set[str] = set()
    for token in expand_array(root_array):
        if token not in seen:
            names.append(token)
            seen.add(token)
    return names


def zlaunch_case_names(h: Harness) -> set[str]:
    return set(zlaunch_case_order(h))


def extract_case_docs(h: Harness, max_len: int | None = None) -> list[tuple[str, str]]:
    generated_description_slugs: set[str] = set()
    ordered_cases = zlaunch_case_order(h)
    if h.slug in generated_description_slugs:
        return [(case, describe_case(h.slug, case)) for case in ordered_cases]

    readme = ROOT.parent / h.path / "README.md"
    if not readme.exists():
        return [(case, describe_case(h.slug, case)) for case in ordered_cases]

    lines = readme.read_text(encoding="utf-8", errors="ignore").splitlines()
    found: dict[str, str] = {}
    seen: set[str] = set()
    actual_cases = set(ordered_cases)
    case_line = re.compile(r"^\s*-\s+`([^`]+)`\s*:?\s*(.*)$")

    for i, line in enumerate(lines):
        match = case_line.match(line)
        if not match:
            continue

        case_name = match.group(1).strip()
        if case_name in seen:
            continue
        if not re.search(r"(_pass|_fail|_absent|group=| threshold group|parameter)", case_name):
            continue
        if case_name not in actual_cases:
            continue

        parts = [match.group(2).strip()]
        for follow in lines[i + 1:]:
            stripped = follow.strip()
            if not stripped:
                continue
            if stripped.startswith("```") or stripped.startswith("#") or stripped.startswith("- `") or re.match(r"^\s*-\s+\S", follow):
                break
            if follow.startswith(" ") or follow.startswith("\t"):
                parts.append(stripped)
                continue
            break

        desc = normalize_description(" ".join(parts), max_len=max_len)
        if desc:
            found[case_name] = desc
            seen.add(case_name)

    if not found:
        return [(case, describe_case(h.slug, case)) for case in ordered_cases]

    return [(case, found.get(case, describe_case(h.slug, case))) for case in ordered_cases]


def case_rows(h: Harness) -> str:
    return "\n".join(
        f"""
        <article class="case-row">
          <code>{escape(case_name)}</code>
          <p>{escape(description)}</p>
        </article>
"""
        for case_name, description in extract_case_docs(h)
    )


def gif_card(gif: tuple[str, str, str], descriptions: dict[str, str], prefix: str) -> str:
    title, case_name, filename = gif
    description = descriptions.get(case_name, describe_case("", case_name))
    if filename == PENDING_GIF:
        data_file = "pending"
        frame_class = "gif-frame gif-frame--pending"
        media = ""
    else:
        media_filename = published_media_name(filename)
        asset = f"{prefix}assets/gifs/{media_filename}?v={ASSET_VERSION}"
        data_file = media_filename
        frame_class = "gif-frame"
        media = (
            f'\n          <video src="{asset}" aria-label="{escape(title)} animation" '
            'autoplay muted loop playsinline controls preload="metadata" '
            'onerror="this.style.display=\'none\'"></video>'
        )
    return f"""
      <article class="gif-card">
        <div class="{frame_class}" data-file="{escape(data_file)}">{media}
        </div>
        <div class="gif-meta">
          <h3>{escape(title)}</h3>
          <p>Description: {escape(description)}</p>
        </div>
      </article>
"""


def harness_card(h: Harness) -> str:
    return f"""
      <a class="harness-card" href="harnesses/{h.slug}.html">
        <span class="eyebrow">{escape(h.family)}</span>
        <h3>{escape(h.title)}</h3>
        <p>{escape(h.summary)}</p>
      </a>
"""


def family_panel(family: Family, harness_by_slug: dict[str, Harness]) -> str:
    cards = "\n".join(harness_card(harness_by_slug[slug]) for slug in family.slugs)
    count = len(family.slugs)
    noun = "harness" if count == 1 else "harnesses"
    return f"""
      <details class="family-panel">
        <summary>
          <span class="family-label">{escape(family.label)}</span>
          <span class="family-name">{escape(family.name)}</span>
          <span class="family-summary">{escape(family.summary)}</span>
          <span class="family-count">{count} {noun}</span>
        </summary>
        <div class="family-harnesses">
          {cards}
        </div>
      </details>
"""


def harness_case_counts() -> dict[str, int]:
    counts: dict[str, int] = {}
    for harness in HARNESSES:
        zlaunch = ROOT.parent / harness.path / "zlaunch.sh"
        text = zlaunch.read_text()
        all_cases = zlaunch_all_cases(text)
        if not all_cases:
            raise ValueError(f"No ALL_CASES or CASES entries found in {zlaunch}")
        counts[zlaunch.parent.name] = len(all_cases)
    return counts


def harness_count() -> int:
    return len(harness_case_counts())


def app_behavior_target_count() -> int:
    roots = {
        Path(harness.path).parts[1]
        for harness in HARNESSES
        if Path(harness.path).parts[1] != "performance_harnesses"
    }
    return len(roots)


def total_case_count() -> int:
    return sum(harness_case_counts().values())


def render_stats() -> str:
    stats = (
        (str(ctest_total_case_count()), "Unit Test Cases", "C++ unit tests for individual MOOS-IvP classes and functions."),
        (str(ctest_area_count()), "Libraries & Components", "MOOS-IvP areas covered by the C++ unit tests."),
        (str(total_case_count()), "Harness Cases", "Mission-run cases with expected outcomes and generated result summaries."),
        (str(app_behavior_target_count()), "Apps & Behaviors", "MOOS apps and IvP behaviors covered by mission harness cases."),
    )
    return "\n".join(
        f"""
      <article class="stat-card">
        <strong>{escape(value)}</strong>
        <span>{escape(label)}</span>
        <p>{escape(text)}</p>
      </article>
"""
        for value, label, text in stats
    )


def ctest_area_table_rows(areas: list[CTestArea]) -> str:
    rows = []
    for area in areas:
        rows.append(
            f"""
            <tr class="ctest-summary-row">
              <th>
                <span class="component-key"><code>{escape(area.key)}</code></span>
                <span class="component-name">{escape(area.label)}</span>
              </th>
              <td>{area.target_count}</td>
              <td>{area.case_count}</td>
              <td class="ctest-description">{escape(area.description)}</td>
            </tr>
"""
        )
    return "\n".join(rows)


def render_ctest_coverage() -> str:
    targets = ctest_targets()
    areas = ctest_area_rows(targets)
    body = f"""
  <main>
    <section class="page-hero page-hero--wide-lede">
      <a class="back-link" href="index.html">Back to overview</a>
      <h1>C++ Unit Tests</h1>
      <p class="lede">Tests check individual classes and functions without running a mission. Organized into focused groups dubbed 'component families' for libraries and other source-level logic like mbutil, geometry, contacts, moosgeodesy, etc.</p>
      <div class="hero-actions">
        <a class="button primary" href="#buckets">Browse component families</a>
        <a class="button secondary" href="{repo_url('tests/cpp/README.md')}">README</a>
      </div>
    </section>

    <section class="content-section stats-section">
      <div class="section-heading">
        <p class="eyebrow">Current Snapshot</p>
        <h2>Unit test coverage at a glance</h2>
      </div>
      <div class="stats-grid stats-grid--two">
        <article class="stat-card">
          <strong>{ctest_total_case_count()}</strong>
          <span>Test Cases</span>
          <p>Individual C++ unit tests covering expected and edge-case behavior.</p>
        </article>
        <article class="stat-card">
          <strong>{len(areas)}</strong>
          <span>Component Families</span>
          <p>Groups such as behaviors, geometry, utilities, viewers, and IvP tools.</p>
        </article>
      </div>
    </section>

    <section id="buckets" class="content-section">
      <div class="section-heading">
        <h2>Component Family Catalog</h2>
      </div>
      <div class="table-wrap">
        <table class="ctest-table">
          <thead>
            <tr>
              <th>Component family</th>
              <th>Targets</th>
              <th>Cases</th>
              <th>Description</th>
            </tr>
          </thead>
          <tbody>
            {ctest_area_table_rows(areas)}
          </tbody>
        </table>
      </div>
    </section>
  </main>
"""
    return page_shell("Unit Tests", body)


def render_quick_start() -> str:
    body = """
  <main>
    <section class="page-hero page-hero--wide-lede">
      <a class="back-link" href="index.html">Back to overview</a>
      <h1>Developer Quick Start</h1>
      <p class="lede">Check out the MOOS-IvP branch containing your changes, build it, then use this repository to run a focused CTest group and its mission harness.</p>
      <div class="hero-actions">
        <a class="button primary" href="#build">Build</a>
        <a class="button secondary" href="#example">Run an example</a>
      </div>
    </section>

    <section id="build" class="content-section">
      <div class="section-heading">
        <p class="eyebrow">1. Build</p>
        <h2>Build the edited MOOS-IvP branch and the tests</h2>
      </div>
      <div class="explain-stack">
        <article>
          <h3>Build both</h3>
          <pre><code>cd /path/to/moos-ivp
git switch my-branch
./build.sh

cd /path/to/moos-ivp-cicd
./build.sh</code></pre>
        </article>
      </div>
    </section>

    <section id="example" class="content-section">
      <div class="section-heading">
        <p class="eyebrow">2. Test</p>
        <h2>Example: editing <code>pEchoVar</code></h2>
        <p>Run the focused CTest group, then the full <code>pEchoVar</code> harness.</p>
      </div>
      <div class="explain-stack">
        <article>
          <h3>Run the <code>pechovar</code> CTest group</h3>
          <pre><code>cd tests/cpp
./ctests.sh --pechovar</code></pre>
          <p>Run <code>./ctests.sh</code> with no family option to test everything, or use <code>--help</code> to list the available families.</p>
          <p>The first focused run may configure and build the selected CTest executables before testing. Later runs rebuild incrementally.</p>
          <p><strong>Example success output</strong></p>
          <pre><code>100% tests passed, 0 tests failed out of 31</code></pre>
        </article>
        <article>
          <h3>Run the full <code>pEchoVar</code> harness</h3>
          <pre><code>cd harnesses/pechovar_harnesses/H01-pechovar_unit
./zlaunch.sh 10</code></pre>
          <p><strong>Example success output</strong></p>
          <pre><code>results=.../results.txt failures=0 total=33 jobs=1 elapsed_seconds=...</code></pre>
        </article>
      </div>
    </section>

    <section id="build-matrix" class="content-section">
      <div class="section-heading">
        <p class="eyebrow">Optional build matrix</p>
        <h2>Check the native and Linux builds</h2>
        <p>Run the normal build on this computer, then compile the same local MOOS-IvP checkout for each supported Linux and compiler combination.</p>
      </div>
      <div class="explain-stack">
        <article>
          <pre><code>cd /path/to/moos-ivp-cicd
./build-matrix.sh</code></pre>
          <p><strong>Example success output</strong></p>
          <pre><code>Build matrix result: 5 passed, 0 failed</code></pre>
          <p>Run <code>./build-matrix.sh --help</code> for native-only testing, focused Linux targets, and compatibility builds.</p>
        </article>
      </div>
    </section>

    <section id="harness-options" class="content-section">
      <div class="section-heading">
        <p class="eyebrow">Harness reference</p>
        <h2>Common launch options</h2>
        <p>Harness defaults vary with the mission. Run <code>./zlaunch.sh --help</code> for the exact values and case names supported by the harness you are using.</p>
      </div>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Option</th>
              <th>Typical default</th>
              <th>Purpose</th>
            </tr>
          </thead>
          <tbody>
            <tr><td><code>[time_warp]</code></td><td><code>10</code></td><td>Set the MOOS time warp.</td></tr>
            <tr><td><code>--case=NAME</code></td><td>All cases</td><td>Run one named case.</td></tr>
            <tr><td><code>--jobs=N</code></td><td><code>1</code></td><td>Run cases concurrently.</td></tr>
            <tr><td><code>--max_time=SECONDS</code></td><td>Harness-specific</td><td>Override the per-case timeout.</td></tr>
            <tr><td><code>--port_base=N</code></td><td>Harness-specific</td><td>Move the run to another MOOS port range.</td></tr>
            <tr><td><code>--port_stride=N</code></td><td>Harness-specific</td><td>Change spacing between case port blocks, when supported.</td></tr>
            <tr><td><code>--log=minimal|full</code></td><td><code>minimal</code></td><td>Reduce CPU usage with minimal logging, or capture full logs for debugging.</td></tr>
            <tr><td><code>--keep_workdirs</code></td><td>Off</td><td>Preserve isolated case directories after the run.</td></tr>
            <tr><td><code>--gui</code> / <code>--nogui</code></td><td><code>--nogui</code></td><td>Enable or disable the mission viewer.</td></tr>
            <tr><td><code>--just_make</code>, <code>-j</code></td><td>Off</td><td>Generate mission files without launching.</td></tr>
            <tr><td><code>--verbose</code>, <code>-v</code></td><td>Off</td><td>Show rolling scheduler activity.</td></tr>
            <tr><td><code>--help</code>, <code>-h</code></td><td>&mdash;</td><td>List the harness options and case names.</td></tr>
          </tbody>
        </table>
      </div>
      <div class="explain-stack">
        <article>
          <h3>Rerun a failure with full diagnostics</h3>
          <pre><code>./zlaunch.sh --case=CASE --log=full --keep_workdirs 10</code></pre>
          <p><code>--log=full</code> restores comprehensive logging. <code>--keep_workdirs</code> retains the generated mission and logs; the final <code>workdirs=...</code> field gives their location.</p>
        </article>
      </div>
      <p>Some harnesses also provide specialized selectors such as <code>--group=NAME</code> or performance timing profiles such as <code>--profile=local|ci</code>.</p>
    </section>

    <section class="workflow">
      <p class="eyebrow">Result</p>
      <h2>Confirm the result</h2>
      <p>CTest passes with <code>100% tests passed</code>. The harness passes with <code>failures=0</code>. The optional build matrix passes with <code>0 failed</code>. Open <code>results.txt</code> only when you want the per-case harness details.</p>
    </section>
  </main>
"""
    return page_shell("Developer Quick Start", body)


def render_index() -> str:
    harness_by_slug = {h.slug: h for h in HARNESSES}
    family_sections = "\n".join(family_panel(family, harness_by_slug) for family in FAMILIES)

    body = f"""
  <main>
    <section class="hero">
      <div class="hero-copy">
        <h1>CI/CD Pipeline for MOOS-IvP Apps, Behaviors, and Libraries</h1>
        <p class="lede">C++ unit tests check individual classes and functions, while mission harnesses test live MOOS processes, vehicle motion, and system-level outcomes.</p>
        <div class="hero-actions">
          <a class="button primary" href="quick-start.html">Developer quick start</a>
          <a class="button secondary" href="#families">Harnesses</a>
          <a class="button secondary" href="ctest-coverage.html">Unit Tests</a>
          <a class="button secondary" href="examples.html">Examples</a>
        </div>
      </div>
      <div class="hero-panel hero-panel--actions">
        <img class="actions-screenshot" src="assets/images/github-actions-runtime-harnesses.png" alt="GitHub Actions runtime harness matrix with passing jobs">
      </div>
    </section>

    <section class="content-section stats-section">
      <div class="section-heading">
        <p class="eyebrow">Repository Snapshot</p>
        <h2>Current coverage at a glance</h2>
      </div>
      <div class="stats-grid">
        {render_stats()}
      </div>
    </section>

    <section id="families" class="content-section">
      <div class="section-heading">
        <h2>Harness Catalog</h2>
        <p>MOOS apps and IvP behaviors under test</p>
      </div>
      <div class="family-list">
        {family_sections}
      </div>
    </section>

    <section id="workflow" class="workflow">
      <p class="eyebrow">Mission Harness Flow</p>
      <h2>From scenario to mission result</h2>
      <ol>
        <li>Stem missions define reusable MOOS community layouts, behavior configs, and baseline geometry.</li>
        <li>Harness overlays use small patches so each run isolates one scenario or regression risk.</li>
        <li>The harness <code>zlaunch.sh</code> wrapper selects the case and then delegates to the shared <code>xlaunch.sh</code> path, keeping local and CI runs aligned.</li>
        <li><code>pMissionEval</code> reports and shell-side checks turn each run into a clear pass/fail result.</li>
      </ol>
      <div class="workflow-actions">
        <a class="text-link" href="examples.html">See the tests catch real mutations</a>
      </div>
    </section>
  </main>
"""
    return page_shell("Home", body)


def render_harness(h: Harness) -> str:
    descriptions = dict(extract_case_docs(h, max_len=None))
    gifs = "\n".join(gif_card(g, descriptions, "../") for g in h.gifs)
    gif_grid_class = "gif-grid"
    if len(h.gifs) == 2:
        gif_grid_class += " gif-grid--two"
    examples_section = ""
    if h.gifs:
        examples_section = f"""
    <section class="content-section">
      <div class="section-heading">
        <p class="eyebrow">Examples</p>
        <h2>Representative runs</h2>
      </div>
      {{visual_note}}
      <div class="{gif_grid_class}">{gifs}
      </div>
    </section>
"""
    test_style = TEST_STYLE.get(h.slug, h.proof)
    stem_context = STEM_CONTEXT.get(h.slug, "")
    visual_note_text = VISUAL_NOTES.get(h.slug, "")
    visual_note = ""
    if visual_note_text:
        visual_note = f"""
      <p class="visual-note">{escape(visual_note_text)} The visuals call out the evidence that makes each case pass.</p>
"""
    stem_section = ""
    if stem_context:
        stem_section = f"""
    <section class="content-section compact-section">
      <article class="stem-card">
        <p class="eyebrow">Stem Mission</p>
        <h2>Baseline scenario context</h2>
        <p>{inline_code(stem_context)}</p>
      </article>
    </section>
"""
    body = f"""
  <main>
    <section class="page-hero">
      <a class="back-link" href="../index.html#families">Back to catalog</a>
      <p class="eyebrow">{escape(h.family)}</p>
      <h1>{escape(h.title)}</h1>
      <p class="lede">{escape(test_style)}</p>
    </section>

    {stem_section}

    {examples_section.format(visual_note=visual_note) if examples_section else ""}

    <section class="content-section">
      <div class="section-heading">
        <p class="eyebrow">Case Matrix</p>
        <h2>All cases</h2>
      </div>
      <div class="case-matrix">
        {case_rows(h)}
      </div>
    </section>

    <section class="source-strip">
      <h2>Source links</h2>
      <a href="{repo_url(h.path + '/README.md')}">Harness README</a>
      <a href="{repo_url(h.mission + '/README.md')}">Mission README</a>
    </section>
  </main>
"""
    return page_shell(h.title, body, "../")


def upstream_url(path: str, revision: str = UPSTREAM_REVISION) -> str:
    return f"https://github.com/moos-ivp/moos-ivp/blob/{revision}/{path}"


def render_feature_commit_links(example: Example) -> str:
    links = []
    for revision, label in example.feature_commits:
        links.append(
            f'<a href="https://github.com/moos-ivp/moos-ivp/commit/{revision}">'
            f'<code>{escape(revision)}</code></a> {escape(label)}'
        )
    return " · ".join(links)


def render_example_verification(example: RealExample) -> str:
    return f"""
      <div class="example-verification">
        <strong>Real upstream PR</strong>
        <span><a href="https://github.com/moos-ivp/moos-ivp/pull/{example.pr_number}">PR #{example.pr_number}</a> by {escape(example.pr_author)}</span>
        <span>{escape(example.pr_status)} · failing <a href="https://github.com/moos-ivp/moos-ivp/commit/{example.failing_revision}"><code>{example.failing_revision}</code></a> · corrected <a href="https://github.com/moos-ivp/moos-ivp/commit/{example.fixed_revision}"><code>{example.fixed_revision}</code></a></span>
      </div>"""


def render_example_card(example: RealExample, number: int) -> str:
    return f"""
      <article class="example-card">
        <div class="example-card-topline">
          <span class="example-number">{number:02d}</span>
          <span class="example-category">{escape(example.category)}</span>
        </div>
        <h2>{escape(example.title)}</h2>
        <p>{escape(example.summary)}</p>
        <dl class="example-card-facts">
          <div>
            <dt>Incomplete solution</dt>
            <dd>{escape(example.incomplete_solution)}</dd>
          </div>
          <div>
            <dt>Result</dt>
            <dd><span class="result-fail">Test caught it</span></dd>
          </div>
        </dl>
        <a class="text-link" href="examples/{example.slug}.html">Read the full example</a>
      </article>
"""


def render_examples() -> str:
    cards = "\n".join(
        render_example_card(example, number)
        for number, example in enumerate(EXAMPLES, start=1)
    )
    body = f"""
  <main>
    <section class="page-hero page-hero--wide-lede">
      <a class="back-link" href="index.html">Back to overview</a>
      <h1>Real Regression Detection</h1>
      <p class="lede">Each story follows a real MOOS-IvP change from an incomplete solution through a focused failure to the corrected upstream result.</p>
      <div class="example-verification">
        <strong>No reconstructed edits</strong>
        <span>Three upstream PRs</span>
        <span>Real revisions, commands, failures, and corrections</span>
      </div>
    </section>

    <section class="content-section">
      <div class="section-heading">
        <h2>Three Real Failure Stories</h2>
        <p>The PROJ restoration comes first because it shows this repository improving another contributor's PR. The two contributor-authored fixes follow, including one mission-harness failure and one source-level configuration failure.</p>
      </div>
      <div class="example-grid">
        {cards}
      </div>
    </section>

    <section class="workflow example-method">
      <p class="eyebrow">Method</p>
      <h2>Problem, failure, correction</h2>
      <ol>
        <li>Start with the real problem an upstream PR tried to solve.</li>
        <li>Show the plausible but incomplete implementation.</li>
        <li>Capture the focused test or harness failure that exposed the gap.</li>
        <li>Trace the corrected implementation and its upstream status.</li>
      </ol>
    </section>
  </main>
"""
    return page_shell("Examples", body)


def render_example(example: RealExample) -> str:
    example_index = EXAMPLES.index(example)
    next_example = EXAMPLES[(example_index + 1) % len(EXAMPLES)]
    body = f"""
  <main>
    <section class="page-hero page-hero--wide-lede">
      <a class="back-link" href="../examples.html">Back to examples</a>
      <p class="eyebrow">Real example {example_index + 1:02d} · {escape(example.category)}</p>
      <h1>{escape(example.title)}</h1>
      <p class="lede">{escape(example.summary)}</p>
      {render_example_verification(example)}
    </section>

    <section class="content-section example-section">
      <div class="section-heading">
        <p class="eyebrow">The upstream problem</p>
        <h2>A plausible solution was incomplete</h2>
      </div>
      <div class="example-story-grid">
        <article class="example-explanation">
          <h3>The problem</h3>
          <p>{escape(example.problem)}</p>
          <h3>The incomplete solution</h3>
          <p>{escape(example.incomplete_solution)}</p>
          <p><a class="text-link" href="{upstream_url(example.source_path, example.failing_revision)}">Open the source at the failing revision</a></p>
        </article>
        <article class="example-code-panel">
          <p class="code-label">{escape(example.diff_label)}</p>
          <pre class="mutation-diff"><code>{escape(example.diff)}</code></pre>
        </article>
      </div>
    </section>

    <section class="content-section example-section">
      <div class="section-heading">
        <p class="eyebrow">The test</p>
        <h2>Run the focused check</h2>
      </div>
      <div class="example-run-grid">
        <article class="example-code-panel">
          <h3>Command</h3>
          <pre><code>{escape(example.command)}</code></pre>
        </article>
        <article class="example-failure">
          <div>
            <p class="eyebrow">At the incomplete revision</p>
            <h3>The focused check fails</h3>
          </div>
          <pre><code>{escape(example.failure)}</code></pre>
        </article>
      </div>
    </section>

    <section class="content-section">
      <div class="section-heading">
        <p class="eyebrow">The correction</p>
        <h2>What changed before the final upstream result</h2>
      </div>
      <div class="example-lessons">
        <article>
          <h3>What the test proved</h3>
          <p>{escape(example.what_caught_it)}</p>
          <p><a class="text-link" href="{repo_url(example.test_path)}">Open the protecting test</a></p>
        </article>
        <article>
          <h3>Corrected solution</h3>
          <p>{escape(example.corrected_approach)}</p>
          <p><a class="text-link" href="{upstream_url(example.source_path, example.fixed_revision)}">Open the corrected source</a></p>
        </article>
        <article>
          <h3>Upstream result</h3>
          <p>{escape(example.corrected_result)}</p>
          <p><a class="text-link" href="https://github.com/moos-ivp/moos-ivp/pull/{example.pr_number}">Open PR #{example.pr_number}</a></p>
        </article>
      </div>
    </section>

    <section class="workflow example-next">
      <p class="eyebrow">Next example</p>
      <h2>{escape(next_example.title)}</h2>
      <a class="button secondary" href="{next_example.slug}.html">Continue</a>
    </section>
  </main>
"""
    return page_shell(example.title, body, "../")
def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized = ""
    if content:
        normalized = "\n".join(line.rstrip() for line in content.splitlines()) + "\n"
    path.write_text(normalized, encoding="utf-8")


def render_gif_manifest() -> str:
    lines = [
        "# Visual Asset Manifest",
        "",
        "Source render scripts produce GIFs using the filenames below.",
        "Run `python3 docs/tools/convert_gifs_to_mp4.py --delete-source-gifs` after",
        "regenerating visuals so the published GitHub Pages assets are CRF-18 MP4s.",
        "Each harness page references the `.mp4` filename derived from the listed GIF.",
        "",
        "Maintainer note: use the harness wrapper command for capture because it applies",
        "case overlays before delegating to shared `xlaunch.sh`. Calling `xlaunch.sh`",
        "directly is useful inside those wrappers, but it is not the case-selection",
        "entry point for the harness pages.",
        "",
        "Generated visual standard: app-level unit, classification, and variable-heavy motion pages may use 16:9,",
        "map-style explanatory animations when a raw `pMarineViewer` capture would not make",
        "the pass condition legible. Keep the look close to the PMV captures: dark chart",
        "background, simple ownship/contact/obstacle geometry, compact labels, and one",
        "small pass-condition callout. The callout should name the MOOS publication being",
        "graded, because that is the evidence the harness is actually testing.",
        "",
        "Generated unit visuals live in `docs/tools/render_unit_harness_gifs.py`.",
        "Generated COLREGS classification visuals live in",
        "`docs/tools/render_colregs_classification_gifs.py`.",
        "Generated COLREGS threshold overlay visuals live in",
        "`docs/tools/render_colregs_threshold_gifs.py`.",
        "Generated COLREGS parameter comparison visuals live in",
        "`docs/tools/render_colregs_parameter_gifs.py`.",
        "Generated PID motion visuals live in `docs/tools/render_pid_motion_gifs.py`.",
        "Generated Timer behavior visuals live in `docs/tools/render_timer_behavior_gifs.py`.",
        "Generated PeriodicSpeed behavior visuals live in `docs/tools/render_periodic_speed_behavior_gifs.py`.",
        "Generated MemoryTurnLimit behavior visuals live in `docs/tools/render_memoryturnlimit_behavior_gifs.py`.",
        "Generated utility infrastructure visuals live in `docs/tools/render_utility_watch_gifs.py`.",
        "Generated simulator infrastructure visuals live in `docs/tools/render_simulator_infrastructure_gifs.py`.",
        "Generated mission utility visuals live in `docs/tools/render_mission_utility_gifs.py`.",
        "Generated uFldObstacleSim visuals live in `docs/tools/render_ufld_obstacle_sim_gifs.py`.",
        "Generated uField app visuals live in `docs/tools/render_ufield_app_gifs.py`.",
        "Headless harness runs remain the source of truth for the case behavior; the",
        "generated visuals are documentation views of that same geometry and variable-level",
        "evidence.",
        "",
    ]
    for harness in HARNESSES:
        lines.extend(
            [
                f"## {harness.title}",
                "",
                f"Capture from: `{harness.path}`",
                f"Typical capture launch: `{harness.run}`",
                "",
            ]
        )
        for title, case_name, filename in harness.gifs:
            if filename == PENDING_GIF:
                lines.append(f"- Visual pending - {title}; representative case `{case_name}`")
            else:
                lines.append(
                    f"- source `{filename}` -> published `{published_media_name(filename)}` - "
                    f"{title}; representative case `{case_name}`"
                )
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    write(ROOT / "index.html", render_index())
    write(ROOT / "quick-start.html", render_quick_start())
    write(ROOT / "ctest-coverage.html", render_ctest_coverage())
    write(ROOT / "examples.html", render_examples())
    for example in EXAMPLES:
        write(ROOT / "examples" / f"{example.slug}.html", render_example(example))
    for slug in STALE_EXAMPLE_SLUGS:
        (ROOT / "examples" / f"{slug}.html").unlink(missing_ok=True)
    for harness in HARNESSES:
        write(ROOT / "harnesses" / f"{harness.slug}.html", render_harness(harness))
    write(ROOT / "assets" / "gifs" / "README.md", render_gif_manifest())
    write(ROOT / ".nojekyll", "")
    (ROOT / "technical.html").unlink(missing_ok=True)


if __name__ == "__main__":
    main()
