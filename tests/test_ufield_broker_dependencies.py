from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HARNESS = Path("harnesses/ufield_comms_harnesses/H02-ufield_broker_bridge")
ROUTING_HARNESS = Path("harnesses/ufield_comms_harnesses/H03-ufield_route_resilience")


class BrokerDependencyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory(prefix="broker-preflight-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.harness = self.root / HARNESS
        self.harness.mkdir(parents=True)
        shutil.copy2(ROOT / HARNESS / "zlaunch.sh", self.harness / "zlaunch.sh")
        self.routing_harness = self.root / ROUTING_HARNESS
        self.routing_harness.mkdir(parents=True)
        shutil.copy2(ROOT / ROUTING_HARNESS / "zlaunch.sh", self.routing_harness / "zlaunch.sh")
        (self.root / "missions/ufield_comms_missions/ufield_comms_unit").mkdir(parents=True)
        (self.root / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/moos_scoped_teardown.sh", self.root / "scripts")
        self.fakebin = self.root / "fakebin"
        self.fakebin.mkdir()
        for command in ("dirname", "basename", "rmdir"):
            (self.fakebin / command).symlink_to(shutil.which(command))

    def run_harness(self, *args: str, routing: bool = False) -> subprocess.CompletedProcess[str]:
        # Exclude optional apps and rg even when the host has them installed.
        env = dict(os.environ, PATH=str(self.fakebin))
        harness = self.routing_harness if routing else self.harness
        return subprocess.run(
            [shutil.which("bash") or "/bin/bash", str(harness / "zlaunch.sh"), *args],
            cwd=self.root, env=env, text=True, capture_output=True, timeout=10,
        )

    def assert_no_run_started(self) -> None:
        for harness in (self.harness, self.routing_harness):
            self.assertFalse((harness / ".harness_runs").exists())
            self.assertFalse((harness / "results.txt").exists())

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

    def test_missing_ripgrep_fails_before_broker_run(self) -> None:
        result = self.run_harness("--case=broker_handshake_pass")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("live broker checks require ripgrep (rg)", result.stderr)
        self.assert_no_run_started()

    def test_missing_ripgrep_fails_before_routing_run(self) -> None:
        result = self.run_harness("--case=runtime_tryhost_default_rejected_pass", routing=True)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("live routing checks require ripgrep (rg)", result.stderr)
        self.assert_no_run_started()


if __name__ == "__main__":
    unittest.main()
