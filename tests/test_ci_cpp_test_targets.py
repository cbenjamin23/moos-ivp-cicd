from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

from scripts import check_cpp_tests, ci_cpp_test_targets


class CppTestTargetSummaryTests(unittest.TestCase):
    def write_report(self, text: str) -> Path:
        tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(tmpdir.cleanup)
        path = Path(tmpdir.name) / "report.xml"
        path.write_text(text, encoding="utf-8")
        return path

    def test_selected_targets_accepts_one_or_comma_list(self) -> None:
        self.assertEqual(ci_cpp_test_targets.selected_targets("geometry"), ["geometry"])
        self.assertEqual(
            ci_cpp_test_targets.selected_targets(" geometry, ivpbuild ,, mbutil "),
            ["geometry", "ivpbuild", "mbutil"],
        )

    def test_selected_targets_defaults_empty_selection_to_all(self) -> None:
        self.assertEqual(ci_cpp_test_targets.selected_targets(" , "), ["all"])

    def test_select_targets_for_mode_matches_workflow_modes(self) -> None:
        self.assertEqual(
            ci_cpp_test_targets.select_targets_for_mode("none", "", ""),
            [],
        )
        self.assertEqual(
            ci_cpp_test_targets.select_targets_for_mode("all", "", ""),
            ["all"],
        )
        self.assertEqual(
            ci_cpp_test_targets.select_targets_for_mode("family_run", "geometry", ""),
            ["geometry"],
        )
        self.assertEqual(
            ci_cpp_test_targets.select_targets_for_mode(
                "batch_family_run",
                "",
                "geometry,ivpbuild",
            ),
            ["geometry", "ivpbuild"],
        )

    def test_select_targets_for_mode_rejects_unknown_family(self) -> None:
        with self.assertRaisesRegex(ValueError, "Unknown C\\+\\+ test family"):
            ci_cpp_test_targets.select_targets_for_mode("family_run", "missing", "")
        with self.assertRaisesRegex(ValueError, "Unknown C\\+\\+ test family"):
            ci_cpp_test_targets.select_targets_for_mode(
                "family_run", "pMissionEval", ""
            )

    def test_safe_filename_replaces_regex_characters(self) -> None:
        self.assertEqual(ci_cpp_test_targets.safe_filename("^behaviors$"), "behaviors")
        self.assertEqual(ci_cpp_test_targets.safe_filename("BHV_Waypoint"), "BHV_Waypoint")

    def test_matrix_for_targets_builds_github_include_matrix(self) -> None:
        self.assertEqual(
            ci_cpp_test_targets.matrix_for_targets("geometry,ivpbuild"),
            {
                "include": [
                    {
                        "target": "geometry",
                        "artifact": "cpp-unit-test-report-geometry",
                    },
                    {
                        "target": "ivpbuild",
                        "artifact": "cpp-unit-test-report-ivpbuild",
                    },
                ]
            },
        )

    def test_matrix_for_selected_targets_allows_empty_none_matrix(self) -> None:
        self.assertEqual(
            ci_cpp_test_targets.matrix_for_selected_targets([]),
            {"include": []},
        )

    def test_all_ctest_target_runs_without_label_filter(self) -> None:
        command = ci_cpp_test_targets.ctest_command(
            Path("build"),
            "all",
            Path("reports/all.xml"),
        )

        self.assertNotIn("-L", command)

    def test_family_ctest_target_uses_an_exact_label_filter(self) -> None:
        command = ci_cpp_test_targets.ctest_command(
            Path("build"),
            "behaviors-marine",
            Path("reports/behaviors-marine.xml"),
        )

        label_index = command.index("-L")
        self.assertEqual(command[label_index + 1], r"^(behaviors\-marine)$")

    def test_exact_label_regex_escapes_every_family_as_literal_text(self) -> None:
        self.assertEqual(
            ci_cpp_test_targets.exact_label_regex(["foo.bar", "c++"]),
            r"^(foo\.bar|c\+\+)$",
        )

    def test_opregion_gate_does_not_select_known_issue_label(self) -> None:
        import re

        for family in ("opregion", "opregion-known-issues", "gen_poly"):
            self.assertEqual(
                ci_cpp_test_targets.select_targets_for_mode("family_run", family, ""),
                [family],
            )
        gate = re.compile(ci_cpp_test_targets.exact_label_regex(["opregion"]))
        self.assertIsNotNone(gate.fullmatch("opregion"))
        self.assertIsNone(gate.fullmatch("opregion-known-issues"))

    def test_known_issue_target_is_not_registered_as_a_required_contract(self) -> None:
        root = Path(__file__).resolve().parents[1] / "tests" / "cpp"
        targets = check_cpp_tests.parse_add_moos_cpp_tests(
            root / "known_issues" / "CMakeLists.txt"
        )
        self.assertTrue(targets)
        for target in targets:
            self.assertIn("opregion-known-issues", target.values("LABELS"))
            self.assertNotIn("opregion", target.values("LABELS"))
            self.assertFalse(target.values("SUITE_LABELS"))

    def test_required_opregion_components_keep_their_gate_labels(self) -> None:
        root = Path(__file__).resolve().parents[1] / "tests" / "cpp"
        for cmake in (
            "gen_poly/CMakeLists.txt",
            "bhvutil/OpRegionAOF/CMakeLists.txt",
            "behaviors_marine/CoreBehaviors/CMakeLists.txt",
            "helmivp/FactoryPopulation/CMakeLists.txt",
        ):
            targets = check_cpp_tests.parse_add_moos_cpp_tests(root / cmake)
            with self.subTest(cmake=cmake):
                self.assertTrue(any(
                    "opregion" in target.values("LABELS") or any(
                        "opregion" in entry.partition("=")[2].split(",")
                        for entry in target.values("SUITE_LABELS")
                    )
                    for target in targets
                ))

    def test_public_behavior_families_match_cmake_labels(self) -> None:
        self.assertIn("behaviors-marine", ci_cpp_test_targets.CPP_FAMILIES)
        self.assertIn("behaviors-colregs", ci_cpp_test_targets.CPP_FAMILIES)
        self.assertNotIn("behaviors_marine", ci_cpp_test_targets.CPP_FAMILIES)
        self.assertNotIn("behaviors_colregs", ci_cpp_test_targets.CPP_FAMILIES)

    def test_family_name_issues_rejects_case_only_build_target_collisions(self) -> None:
        self.assertEqual(
            ci_cpp_test_targets.family_name_issues(
                ["pnodereporter", "pNodeReporter"]
            ),
            [
                "public selectors must be lowercase and contain only letters, "
                "numbers, _, or -: pNodeReporter",
                "case-insensitive selector collision for "
                "ctest-family-pnodereporter: pNodeReporter, pnodereporter"
            ],
        )

    def test_family_name_issues_rejects_invalid_and_exact_duplicate_names(self) -> None:
        self.assertEqual(
            ci_cpp_test_targets.family_name_issues(
                ["geometry", "bad/family", "geometry"]
            ),
            [
                "public selectors must be lowercase and contain only letters, "
                "numbers, _, or -: bad/family",
                "duplicate selector: geometry",
            ],
        )

    def test_current_public_family_names_are_unambiguous(self) -> None:
        self.assertEqual(
            ci_cpp_test_targets.family_name_issues(
                list(ci_cpp_test_targets.CPP_FAMILIES)
            ),
            [],
        )
        self.assertTrue(
            all(family == family.lower() for family in ci_cpp_test_targets.CPP_FAMILIES)
        )

    def test_parse_junit_report_counts_failures_errors_and_skips(self) -> None:
        report = self.write_report(
            """<?xml version="1.0"?>
<testsuite tests="4" failures="1" errors="1" skipped="1">
  <testcase classname="suite" name="passes"/>
  <testcase classname="suite" name="fails"><failure message="bad value"/></testcase>
  <testcase classname="suite" name="errors"><error>crashed</error></testcase>
  <testcase classname="suite" name="skips"><skipped/></testcase>
</testsuite>
"""
        )

        tests, failures, errors, skipped, issues, report_issue = (
            ci_cpp_test_targets.parse_junit_report(report)
        )

        self.assertEqual((tests, failures, errors, skipped), (4, 1, 1, 1))
        self.assertEqual(report_issue, "")
        self.assertEqual([issue.name for issue in issues], ["suite.fails", "suite.errors"])
        self.assertEqual([issue.status for issue in issues], ["failure", "error"])

    def test_build_summary_includes_failing_case_table(self) -> None:
        result = ci_cpp_test_targets.TargetResult(
            target="geometry",
            report_path=Path("build/cpp-unit-test-reports/geometry.xml"),
            command=["ctest", "--test-dir", "build", "-L", "geometry"],
            returncode=8,
            tests=2,
            failures=1,
            errors=0,
            skipped=0,
            issues=[
                ci_cpp_test_targets.CaseIssue(
                    name="suite.fails",
                    status="failure",
                    message="bad value",
                )
            ],
        )

        summary = ci_cpp_test_targets.build_summary([result])

        self.assertIn("| `geometry` | `fail` | 2 | 1 | 0 | 0 |", summary)
        self.assertIn("#### Failing Cases", summary)
        self.assertIn("`suite.fails`", summary)


if __name__ == "__main__":
    unittest.main()
