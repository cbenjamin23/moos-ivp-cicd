from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
ROUTES = ROOT / "harnesses/ufield_comms_harnesses/H03-ufield_route_resilience"
NSPATCH_BINARY = os.environ.get("NSPATCH_BINARY", "")


class MergedUpstreamContractTests(unittest.TestCase):
    def test_launchers_avoid_shadowed_generic_nspatch_flags(self) -> None:
        launchers = list((ROOT / "harnesses").rglob("zlaunch.sh"))
        self.assertTrue(launchers)
        for launcher in launchers:
            if ".harness_runs" in launcher.parts:
                continue
            with self.subTest(launcher=str(launcher.relative_to(ROOT))):
                self.assertNotRegex(launcher.read_text(), r"--(?:stem|targ)=")

    def test_route_recovery_explicitly_opts_in_but_default_case_does_not(self) -> None:
        candidates = list(ROUTES.glob("*vehicle*.xmoos"))
        self.assertTrue(candidates)
        count = 0
        for patch in candidates:
            if not re.search(r"runtime|shore_vnode", patch.name):
                continue
            text = patch.read_text()
            with self.subTest(patch=patch.name):
                if "default_rejected" in patch.name:
                    self.assertNotIn("accept_try_shore_host", text)
                    self.assertIn("var=TRY_SHORE_HOST", text)
                else:
                    self.assertIn("accept_try_shore_host = true", text)
                    count += 1
        self.assertGreaterEqual(count, 20)
        grade = (ROUTES / "runtime_tryhost_default_rejected_pass-shoreside.xmoos").read_text()
        self.assertIn("pass_condition = UFSB_NODE_COUNT = 0", grade)
        self.assertIn("pass_condition = DIRECT_MSG_DELIVERED = false", grade)
        self.assertIn("report_file   = results.txt", grade)


@unittest.skipUnless(NSPATCH_BINARY, "set NSPATCH_BINARY to run the real upstream CLI")
class NspatchCliCompatibilityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory(prefix="nspatch-compat-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)

    def run_cli(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [NSPATCH_BINARY, *arguments], cwd=self.root,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10,
        )

    def test_positional_moos_patch_writes_a_real_sidecar(self) -> None:
        (self.root / "stem.moos").write_text("ProcessConfig = pFoo\n{\n  AppTick = 4\n}\n")
        (self.root / "patch.xmoos").write_text("pFoo::AppTick = 9\n")
        result = self.run_cli("stem.moos", "patch.xmoos", "target.moosx")
        self.assertEqual(result.returncode, 0, result.stdout)
        target = (self.root / "target.moosx").read_text()
        self.assertIn("AppTick = 9", target)
        self.assertNotIn("AppTick = 4", target)

    def test_positional_bhv_patch_writes_a_real_sidecar(self) -> None:
        (self.root / "stem.bhv").write_text(
            "// behavior stem\n\n\nBehavior = BHV_Timer\n{\n  name = timer\n  duration = 10\n}\n"
        )
        (self.root / "patch.xbhv").write_text("BHV_Timer@timer::duration = 25\n")
        result = self.run_cli("stem.bhv", "patch.xbhv", "target.bhvx")
        self.assertEqual(result.returncode, 0, result.stdout)
        target = (self.root / "target.bhvx").read_text()
        self.assertIn("duration = 25", target)
        self.assertNotIn("duration = 10", target)

    def test_vehicle_modifier_only_applies_the_matching_override(self) -> None:
        (self.root / "stem.bhv").write_text(
            "// behavior stem\n\n\nBehavior = BHV_Timer\n{\n  name = timer\n  duration = 10\n}\n"
        )
        (self.root / "patch.xbhv").write_text(
            "~abe BHV_Timer@timer::duration = 25\n"
            "~ben BHV_Timer@timer::duration = 90\n"
        )
        result = self.run_cli("stem.bhv", "patch.xbhv", "target.bhvx", "--vkey=abe")
        self.assertEqual(result.returncode, 0, result.stdout)
        target = (self.root / "target.bhvx").read_text()
        self.assertIn("duration = 25", target)
        self.assertNotIn("duration = 90", target)

    def test_missing_job_and_unknown_options_fail(self) -> None:
        for arguments in ((), ("--not-a-real-option",)):
            with self.subTest(arguments=arguments):
                self.assertNotEqual(self.run_cli(*arguments).returncode, 0)

    def test_unwritable_target_fails_without_a_sidecar(self) -> None:
        (self.root / "stem.moos").write_text("ProcessConfig = pFoo\n{\n  AppTick = 4\n}\n")
        (self.root / "patch.xmoos").write_text("pFoo::AppTick = 9\n")
        result = self.run_cli("stem.moos", "patch.xmoos", "missing/target.moosx")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse((self.root / "missing/target.moosx").exists())


if __name__ == "__main__":
    unittest.main()
