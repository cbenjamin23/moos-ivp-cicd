from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HARNESS = Path("harnesses/ufield_comms_harnesses/H02-ufield_broker_bridge")


class BrokerDependencyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory(prefix="broker-preflight-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.harness = self.root / HARNESS
        self.harness.mkdir(parents=True)
        shutil.copy2(ROOT / HARNESS / "zlaunch.sh", self.harness / "zlaunch.sh")
        (self.root / "missions/ufield_comms_missions/ufield_comms_unit").mkdir(parents=True)
        (self.root / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/moos_scoped_teardown.sh", self.root / "scripts")

    def run_harness(self, *args: str) -> subprocess.CompletedProcess[str]:
        # Core-only PATH deliberately excludes the user's extension binaries.
        env = dict(os.environ, PATH="/usr/bin:/bin")
        return subprocess.run(
            [shutil.which("bash") or "/bin/bash", str(self.harness / "zlaunch.sh"), *args],
            cwd=self.root, env=env, text=True, capture_output=True, timeout=10,
        )

    def assert_no_run_started(self) -> None:
        self.assertFalse((self.harness / ".harness_runs").exists())
        self.assertFalse((self.harness / "results.txt").exists())

    def test_missing_mediator_fails_before_creating_a_run(self) -> None:
        result = self.run_harness("--case=node_mediated_bridge_pass")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("requires pMediator from moos-ivp-swarm", result.stderr)
        self.assert_no_run_started()

    def test_core_selection_rejects_an_explicit_extension_case(self) -> None:
        result = self.run_harness("--core_only", "--case=node_mediated_bridge_pass")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("--core_only excludes node_mediated_bridge_pass", result.stderr)
        self.assert_no_run_started()


if __name__ == "__main__":
    unittest.main()
