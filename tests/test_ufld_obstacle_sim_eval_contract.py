from __future__ import annotations

from pathlib import Path
import re
import unittest

from scripts.ci_harness_case_count import derive_case_order


ROOT = Path(__file__).resolve().parents[1]
HARNESS = (
    ROOT
    / "harnesses"
    / "ufld_obstacle_sim_harnesses"
    / "H01-ufld_obstacle_sim_unit"
)
MISSION = (
    ROOT
    / "missions"
    / "ufld_obstacle_sim_missions"
    / "ufld_obstacle_sim_unit"
)


def mission_eval_block(text: str) -> str:
    match = re.search(
        r"^ProcessConfig = pMissionEval\s*\n\{.*?^\}",
        text,
        re.MULTILINE | re.DOTALL,
    )
    if not match:
        raise AssertionError("missing pMissionEval block")
    return match.group(0)


class UfldObstacleSimEvalContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.launcher_text = (HARNESS / "zlaunch.sh").read_text(encoding="utf-8")
        cls.stem_text = (MISSION / "meta_shoreside.moos").read_text(
            encoding="utf-8"
        )
        cls.cases = derive_case_order(HARNESS / "zlaunch.sh")
        cls.overlays = sorted(HARNESS.glob("*-shoreside.xmoos"))

    def test_case_matrix_and_explicit_patch_map_are_complete(self) -> None:
        mappings = dict(
            re.findall(
                r"^\s*([a-z0-9_]+)\) "
                r'CASE_SHORE_PATCH="\$HARNESS_DIR/([^\"]+)" ;;$',
                self.launcher_text,
                re.MULTILINE,
            )
        )

        self.assertEqual(len(self.cases), 49)
        self.assertEqual(len(self.overlays), 48)
        self.assertEqual(set(mappings), set(self.cases) - {"fixed_field_publish_pass"})
        self.assertEqual({path.name for path in self.overlays}, set(mappings.values()))

    def test_launcher_uses_one_case_patch_and_no_shell_grader(self) -> None:
        self.assertIn(
            'shore_patches+=("$CASE_SHORE_PATCH")',
            self.launcher_text,
        )
        self.assertIn(
            '"${shore_patches[@]}" "$workdir/meta_shoreside.moosx"',
            self.launcher_text,
        )
        for legacy_token in (
            "EVAL_PATCH",
            "meta_case.moos",
            "evidence-eval-shoreside.xmoos",
            "aloggrep",
            "find_shore_alog",
            "extra_check_ok",
        ):
            self.assertNotIn(legacy_token, self.launcher_text)

    def test_launcher_stops_refill_after_teardown_failure(self) -> None:
        self.assertIn('if [ "$reason" = teardown_error ]', self.launcher_text)
        self.assertIn("FINISH_FATAL_REASON=teardown_error", self.launcher_text)
        self.assertIn("stop_refill_after_infrastructure_error", self.launcher_text)
        self.assertIn("scheduler_aborted_after_%s", self.launcher_text)
        self.assertIn('finish_one || finish_rc=$?', self.launcher_text)
        self.assertIn('if [ "$finish_rc" -eq 2 ]', self.launcher_text)

    def test_launcher_propagates_destructive_cleanup_failures(self) -> None:
        self.assertIn('if ! rm -rf -- "$RUN_ROOT"', self.launcher_text)
        self.assertNotIn("LOCK_DIR=", self.launcher_text)
        self.assertNotIn("HAVE_LOCK", self.launcher_text)
        self.assertIn("CLEANUP_FAILED=yes", self.launcher_text)
        self.assertIn('[ "$CLEANUP_FAILED" = no ]', self.launcher_text)
        self.assertIn('[ "$CLEANING" = no ] || return 0', self.launcher_text)
        self.assertIn("trap '' INT TERM PIPE", self.launcher_text)

    def test_launcher_forwards_timeout_and_isolates_case_ports(self) -> None:
        self.assertIn('--max_time="$MAX_TIME"', self.launcher_text)
        self.assertIn('--shore_mport="$((case_base + 0))"', self.launcher_text)
        self.assertIn('--veh_mport="$((case_base + 1))"', self.launcher_text)
        self.assertIn(
            '--shore_pshare="$((case_base + PSHARE_OFFSET))"',
            self.launcher_text,
        )
        self.assertIn("case_base=$((PORT_BASE + case_idx * PORT_STRIDE))", self.launcher_text)
        for extension in (
            "host_ephemeral_port_range",
            "run_stem_with_wall_guard",
            ".harness_launch_groups",
            "moos_scoped_teardown_stop_group",
            "runner_infrastructure_error",
            "reason=launch_timeout",
            "set -m",
        ):
            self.assertNotIn(extension, self.launcher_text)

    def test_runner_failures_preserve_sanitized_mission_provenance(self) -> None:
        self.assertIn("runner_provenance", self.launcher_text)
        for renamed in (
            'field="mission_case=${field#*=}"',
            'field="mission_grade=${field#*=}"',
            'field="mission_reason=${field#*=}"',
            'field="mission_launch_rc=${field#*=}"',
        ):
            self.assertIn(renamed, self.launcher_text)

    def test_mission_wrapper_guards_empty_result_array_on_failure(self) -> None:
        wrapper_text = (MISSION / "zlaunch.sh").read_text(encoding="utf-8")
        self.assertIn('if [ -n "$result_line" ]; then', wrapper_text)
        self.assertLess(
            wrapper_text.index('if [ -n "$result_line" ]; then'),
            wrapper_text.index('for field in "${result_fields[@]}"; do'),
        )
        self.assertIn("expected exactly one pMissionEval result row", wrapper_text)
        self.assertIn("grade=pass|fail", wrapper_text)
        self.assertIn("validate_port", wrapper_text)
        self.assertIn('[ "$TIME_WARP" -gt 0 ]', wrapper_text)
        self.assertIn('[ "$MAX_TIME" -gt 0 ]', wrapper_text)

    def test_stem_uses_direct_eval_and_narrow_upstream_adapter(self) -> None:
        self.assertEqual(self.stem_text.count("ProcessConfig = pMissionEval"), 1)
        self.assertEqual(self.stem_text.count("ProcessConfig = pEchoVar"), 1)
        self.assertNotIn("pHarnessEvidence", self.stem_text)
        self.assertLess(
            self.stem_text.index("Run = pMissionEval"),
            self.stem_text.index("Run = uFldObstacleSim"),
        )
        self.assertLess(
            self.stem_text.index("Run = pEchoVar"),
            self.stem_text.index("Run = uFldObstacleSim"),
        )

        adapter_vars = set(
            re.findall(r"dest_variable\s*=\s*(UFOS_EVAL_\w+)", self.stem_text)
        )
        self.assertEqual(
            adapter_vars,
            {
                "UFOS_EVAL_GIVEN_A",
                "UFOS_EVAL_GIVEN_B",
                "UFOS_EVAL_INACTIVE_A",
                "UFOS_EVAL_KNOWN_A",
                "UFOS_EVAL_KNOWN_B",
                "UFOS_EVAL_KNOWN_OB1",
                "UFOS_EVAL_POINT",
                "UFOS_EVAL_POINT_ALPHA",
                "UFOS_EVAL_POINT_BETA",
                "UFOS_EVAL_POINT_RED",
                "UFOS_EVAL_POINT_SIZE_1",
                "UFOS_EVAL_POINT_SIZE_2",
                "UFOS_EVAL_POINT_SIZE_2_5",
                "UFOS_EVAL_POINT_SIZE_3",
                "UFOS_EVAL_POINT_SIZE_5",
                "UFOS_EVAL_POLYGON_A",
                "UFOS_EVAL_POLYGON_REGION",
                "UFOS_EVAL_TRACKED_A",
                "UFOS_EVAL_TRACKED_B",
                "UFOS_EVAL_TRACKED_BETA",
            },
        )
        self.assertIn("FLIP:point    = dest_separator  = :", self.stem_text)
        self.assertIn("FLIP:point    = label         -> label", self.stem_text)
        self.assertIn("FLIP:point    = vertex_color -> color", self.stem_text)
        self.assertIn("FLIP:point    = vertex_size  -> size", self.stem_text)

        # pEchoVar ignores a configured filter when that field is absent.
        # Map every tested component so pMissionEval can compare the complete
        # normalized match rather than accepting a partial record.
        self.assertIn("FLIP:inactive_a = active == false", self.stem_text)
        self.assertIn("FLIP:inactive_a = active -> active", self.stem_text)
        self.assertIn("FLIP:inactive_a = label  -> label", self.stem_text)
        self.assertIn("FLIP:inactive_a = dest_separator  = :", self.stem_text)
        self.assertIn("FLIP:point_red = vertex_color -> color", self.stem_text)
        self.assertIn("FLIP:point_size_3 = vertex_size -> size", self.stem_text)
        self.assertNotIn("UFOS_EVAL_POINT_YELLOW", self.stem_text)
        self.assertNotIn("UFOS_EVAL_POINT_CYAN", self.stem_text)

        stem_eval = mission_eval_block(self.stem_text)
        self.assertIn("lead_condition = TEST_EVAL_READY = true", stem_eval)
        self.assertNotIn("pass_condition = TEST_EVAL_READY = true", stem_eval)
        self.assertIn(
            "pass_condition = KNOWN_OBSTACLE = $ (UFOS_EXPECT_OBSTACLE)",
            stem_eval,
        )
        self.assertIn(
            "pass_condition = VIEW_POLYGON = $ (UFOS_EXPECT_REGION_VIEW)",
            stem_eval,
        )
        self.assertIn("report_file      = results.txt", stem_eval)

    def test_every_overlay_owns_a_substantive_eval_contract(self) -> None:
        for overlay in self.overlays:
            text = overlay.read_text(encoding="utf-8")
            self.assertEqual(text.count("ProcessConfig = pMissionEval"), 1, overlay.name)
            block = mission_eval_block(text)
            self.assertIn(
                "lead_condition = TEST_EVAL_READY = true", block, overlay.name
            )
            self.assertNotIn(
                "pass_condition = TEST_EVAL_READY = true", block, overlay.name
            )
            self.assertRegex(
                block,
                r"(?m)^\s*(pass_condition|fail_condition)\s*=",
                overlay.name,
            )
            self.assertIn("report_file      = results.txt", block, overlay.name)

    def test_every_replaced_timer_waits_for_eval_subject_and_adapter(self) -> None:
        timer_overlays = [
            path
            for path in self.overlays
            if "ProcessConfig = uTimerScript" in path.read_text(encoding="utf-8")
        ]
        self.assertEqual(len(timer_overlays), 44)
        for overlay in timer_overlays:
            text = overlay.read_text(encoding="utf-8")
            self.assertIn(
                "block_on = pMissionEval, pEchoVar, uFldObstacleSim",
                text,
                overlay.name,
            )
        self.assertIn(
            "block_on = pMissionEval, pEchoVar, uFldObstacleSim",
            self.stem_text,
        )

    def test_auxiliary_state_is_limited_to_expected_data_and_field_matches(self) -> None:
        all_eval_text = self.stem_text + "\n" + "\n".join(
            path.read_text(encoding="utf-8") for path in self.overlays
        )
        self.assertNotRegex(all_eval_text, r"\b(?:SEEN|ABSENT|READY)_")
        self.assertNotIn("UFOS_EVIDENCE", all_eval_text)

        expected_vars = set(re.findall(r"\b(UFOS_EXPECT_[A-Z_]+)\b", all_eval_text))
        self.assertEqual(
            expected_vars,
            {
                "UFOS_EXPECT_OBSTACLE",
                "UFOS_EXPECT_POINT_LABEL",
                "UFOS_EXPECT_REGION_VIEW",
                "UFOS_EXPECT_VIEW",
            },
        )

        count_vars = set(re.findall(r"@\w+#(\w+_COUNT)=\$\[CNT\]", all_eval_text))
        self.assertEqual(
            count_vars,
            {
                "KNOWN_OBSTACLE_COUNT",
                "GIVEN_OBSTACLE_COUNT",
                "VIEW_POLYGON_COUNT",
                "TRACKED_FEATURE_ALPHA_COUNT",
                "VIEW_POINT_COUNT",
                "PMV_CONNECT_COUNT",
            },
        )

    def test_every_eval_condition_uses_parser_safe_rhs_syntax(self) -> None:
        sources = [("meta_shoreside.moos", self.stem_text)] + [
            (path.name, path.read_text(encoding="utf-8"))
            for path in self.overlays
        ]
        condition_re = re.compile(
            r"(?m)^\s*(?:lead_condition|pass_condition|fail_condition)\s*=\s*(.+)$"
        )
        for name, text in sources:
            for expression in condition_re.findall(mission_eval_block(text)):
                for literal in re.findall(r'"([^"]*)"', expression):
                    self.assertNotRegex(
                        literal,
                        r"[=<>!()]",
                        f"{name}: parser-unsafe quoted RHS in {expression}",
                    )
                if "$ (" in expression:
                    self.assertRegex(
                        expression,
                        r"[=!<>]=?\s*\$ \([A-Z][A-Z0-9_]*\)$",
                        f"{name}: malformed nsplug-safe RHS variable in {expression}",
                    )

        all_eval_text = "\n".join(text for _, text in sources)
        self.assertNotRegex(
            all_eval_text,
            r"(?m)^\s*(?:lead_condition|pass_condition|fail_condition)"
            r"\s*=.*(?:=|==)\s*[^$\s\"]+=[^\s]*$",
        )

    def test_distinct_history_contracts_keep_filtered_sentinels(self) -> None:
        expected_fragments = {
            "multi-field-labels-pass-shoreside.xmoos": (
                'pass_condition = UFOS_EVAL_KNOWN_A != ""',
                'pass_condition = UFOS_EVAL_KNOWN_B != ""',
                'pass_condition = UFOS_EVAL_GIVEN_A != ""',
                'pass_condition = UFOS_EVAL_GIVEN_B != ""',
                "pass_condition = KNOWN_OBSTACLE_COUNT = 2",
                "pass_condition = GIVEN_OBSTACLE_COUNT = 2",
            ),
            "post-points-multi-field-pass-shoreside.xmoos": (
                'pass_condition = UFOS_EVAL_KNOWN_A != ""',
                'pass_condition = UFOS_EVAL_KNOWN_B != ""',
                'pass_condition = UFOS_EVAL_TRACKED_A != ""',
                'pass_condition = UFOS_EVAL_TRACKED_B != ""',
            ),
            "post-points-multi-vehicle-pass-shoreside.xmoos": (
                'pass_condition = UFOS_EVAL_TRACKED_BETA != ""',
                'pass_condition = UFOS_EVAL_POINT_ALPHA != ""',
                'pass_condition = UFOS_EVAL_POINT_BETA != ""',
                "pass_condition = UFOS_EVAL_POINT == ufos_a",
            ),
            "reset-reuse-ids-false-pass-shoreside.xmoos": (
                "pass_condition = UFOS_EVAL_INACTIVE_A = $ (UFOS_EXPECT_OBSTACLE)",
                'pass_condition = UFOS_EVAL_KNOWN_OB1 != ""',
            ),
        }
        for name, fragments in expected_fragments.items():
            text = (HARNESS / name).read_text(encoding="utf-8")
            for fragment in fragments:
                self.assertIn(fragment, text, name)

        stem_eval = mission_eval_block(self.stem_text)
        self.assertIn(
            'pass_condition = UFOS_EVAL_POLYGON_A != ""',
            stem_eval,
        )

        draw_region = (HARNESS / "draw-region-false-pass-shoreside.xmoos").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            'fail_condition = UFOS_EVAL_POLYGON_REGION != ""', draw_region
        )

    def test_missing_file_fails_on_any_minimum_range_publication(self) -> None:
        text = (HARNESS / "missing-obstacle-file-absent-pass-shoreside.xmoos").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "fail_condition = UFOS_MIN_RNG = $ (UFOS_MIN_RNG)", text
        )
        self.assertNotIn('fail_condition = UFOS_MIN_RNG != ""', text)
        self.assertNotIn("fail_condition = UFOS_MIN_RNG > 0", text)
        self.assertNotIn("pass_condition =", mission_eval_block(text))

    def test_no_refresh_cases_reject_visual_only_output(self) -> None:
        for name in (
            "invalid-node-report-no-refresh-pass-shoreside.xmoos",
            "vehicle-connect-no-refresh-pass-shoreside.xmoos",
        ):
            text = (HARNESS / name).read_text(encoding="utf-8")
            self.assertIn('fail_condition = VIEW_POLYGON != ""', text, name)

    def test_history_sensitive_cases_bound_or_order_their_evidence(self) -> None:
        duration_zero = (
            HARNESS / "duration-disabled-zero-pass-shoreside.xmoos"
        ).read_text(encoding="utf-8")
        self.assertIn("KNOWN_OBSTACLE_COUNT = 1", duration_zero)
        self.assertIn("GIVEN_OBSTACLE_COUNT = 1", duration_zero)

        repeated = (
            HARNESS / "pmv-connect-repeated-repost-pass-shoreside.xmoos"
        ).read_text(encoding="utf-8")
        self.assertIn("PMV_CONNECT_COUNT = 3", repeated)
        self.assertIn("@PMV_CONNECT#PMV_CONNECT_COUNT=$[CNT]", repeated)

        sequence = (
            HARNESS / "point-size-sequence-pass-shoreside.xmoos"
        ).read_text(encoding="utf-8")
        sequence_eval = mission_eval_block(sequence)
        self.assertEqual(sequence_eval.count("lead_condition ="), 3)
        alpha_lead = 'lead_condition = UFOS_EVAL_POINT_ALPHA != ""'
        bigger_lead = 'lead_condition = UFOS_EVAL_POINT_SIZE_3 != ""'
        final_lead = "lead_condition = TEST_EVAL_READY = true"
        self.assertLess(sequence_eval.index(alpha_lead), sequence_eval.index(bigger_lead))
        self.assertLess(sequence_eval.index(bigger_lead), sequence_eval.index(final_lead))
        # The first aspect grades the observed size-3 output. Checking the
        # timer input here is racy because it may already have advanced to the
        # second stage before pMissionEval's next iterate.
        self.assertNotIn('pass_condition = UFOS_POINT_SIZE = "bigger"', sequence_eval)
        self.assertIn('pass_condition = UFOS_POINT_SIZE = "smaller"', sequence_eval)
        self.assertIn('pass_condition = UFOS_EVAL_POINT_SIZE_3 != ""', sequence_eval)
        self.assertIn('pass_condition = UFOS_EVAL_POINT_SIZE_2 != ""', sequence_eval)

        for name in (
            "reset-request-reposts-pass-shoreside.xmoos",
            "reset-post-points-no-given-pass-shoreside.xmoos",
            "reset-post-visuals-false-pass-shoreside.xmoos",
            "reset-interval-exit-pass-shoreside.xmoos",
        ):
            text = (HARNESS / name).read_text(encoding="utf-8")
            self.assertNotIn("event = var=PMV_CONNECT", text, name)
            self.assertIn("KNOWN_OBSTACLE_COUNT >= 2", text, name)

    def test_rate_and_visual_cases_have_bounded_deterministic_contracts(self) -> None:
        rate_text = (HARNESS / "rate-points-three-pass-shoreside.xmoos").read_text(
            encoding="utf-8"
        )
        self.assertIn("AppTick   = 0.2", rate_text)
        self.assertIn("TEST_EVAL_READY, val=true, time=7.0", rate_text)
        self.assertIn("TRACKED_FEATURE_ALPHA_COUNT = 3", rate_text)
        self.assertIn("VIEW_POINT_COUNT = 3", rate_text)
        self.assertIn(
            "@VIEW_POINT#VIEW_POINT_COUNT=$[CNT]", rate_text
        )

        mixed_case = (
            HARNESS / "node-report-mixed-case-vehicle-pass-shoreside.xmoos"
        ).read_text(encoding="utf-8")
        self.assertIn(
            'event = var=UFOS_EXPECT_POINT_LABEL, val="label=Alpha", time=0.5',
            mixed_case,
        )
        self.assertIn(
            "pass_condition = UFOS_EVAL_POINT == $ (UFOS_EXPECT_POINT_LABEL)",
            mixed_case,
        )
        self.assertIn("pass_condition = UFOS_EVAL_POINT == ufos_a", mixed_case)

        for name in (
            "post-points-inside-pass-shoreside.xmoos",
            "node-report-color-point-pass-shoreside.xmoos",
        ):
            text = (HARNESS / name).read_text(encoding="utf-8")
            self.assertIn(
                'pass_condition = UFOS_EVAL_POINT_ALPHA != ""', text, name
            )
            self.assertIn("pass_condition = UFOS_EVAL_POINT == ufos_a", text, name)

        expected_size_vars = {
            "point-size-bigger-pass-shoreside.xmoos": "UFOS_EVAL_POINT_SIZE_3",
            "point-size-floor-ignored-pass-shoreside.xmoos": "UFOS_EVAL_POINT_SIZE_1",
            "point-size-fraction-pass-shoreside.xmoos": "UFOS_EVAL_POINT_SIZE_2_5",
            "point-size-invalid-ignored-pass-shoreside.xmoos": "UFOS_EVAL_POINT_SIZE_2",
            "point-size-numeric-pass-shoreside.xmoos": "UFOS_EVAL_POINT_SIZE_5",
            "point-size-smaller-pass-shoreside.xmoos": "UFOS_EVAL_POINT_SIZE_1",
            "point-size-uppercase-pass-shoreside.xmoos": "UFOS_EVAL_POINT_SIZE_3",
            "point-size-zero-ignored-pass-shoreside.xmoos": "UFOS_EVAL_POINT_SIZE_2",
        }
        for path in self.overlays:
            if not path.name.startswith("point-size-"):
                continue
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("UFOS_EVAL_POINT_YELLOW", text, path.name)
            if path.name != "point-size-sequence-pass-shoreside.xmoos":
                self.assertIn(
                    f'{expected_size_vars[path.name]} != ""', text, path.name
                )

        for name in (
            "obstacle-visual-style-pass-shoreside.xmoos",
            "poly-visual-zero-sizes-pass-shoreside.xmoos",
        ):
            text = (HARNESS / name).read_text(encoding="utf-8")
            self.assertIn("draw_region        = false", text, name)
            self.assertIn(
                "pass_condition = VIEW_POLYGON = $ (UFOS_EXPECT_VIEW)",
                text,
                name,
            )


if __name__ == "__main__":
    unittest.main()
