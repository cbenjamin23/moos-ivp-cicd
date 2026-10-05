#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


CPP_FAMILIES = (
    "alogcheck",
    "alogavg",
    "alogbin",
    "alogcat",
    "alogcd",
    "alogclip",
    "alogeplot",
    "alogeval",
    "aloggrep",
    "aloghelm",
    "alogiter",
    "alogload",
    "alogmhash",
    "alogpare",
    "alogpick",
    "alogrm",
    "alogscan",
    "alogsplit",
    "alogsort",
    "alogtest",
    "alogtm",
    "apputil",
    "behaviors",
    "behaviors-colregs",
    "behaviors-marine",
    "bhvutil",
    "contacts",
    "dep_behaviors",
    "encounters",
    "evalutil",
    "gen_moos_app",
    "gen_poly",
    "genutil",
    "geodaid",
    "geometry",
    "helmivp",
    "ipfview",
    "isay",
    "uhelmscope",
    "ivpbuild",
    "ivpcore",
    "ivpsolve",
    "logic",
    "logutils",
    "manifest",
    "marine_pid",
    "moosgeodesy",
    "pmissioneval",
    "pmissionhash",
    "umayfinish",
    "pnodereporter",
    "marineview",
    "mbutil",
    "nspatch",
    "nsplug",
    "obstacles",
    "opregion",
    "opregion-known-issues",
    "pechovar",
    "pickpos",
    "pluck",
    "polar",
    "prealm",
    "projfield",
    "realm",
    "survey",
    "tagrep",
    "turngeo",
    "ucommand",
    "usim_marine",
    "ufield",
    "ufldbeaconrangesensor",
    "ufldcollisiondetect",
    "uflddelve",
    "uplotviewer",
    "utimerscript",
    "zaicview",
)

PUBLIC_FAMILY_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_-]*$")


@dataclass(frozen=True)
class CaseIssue:
    name: str
    status: str
    message: str


@dataclass(frozen=True)
class TargetResult:
    target: str
    report_path: Path
    command: list[str]
    returncode: int
    tests: int
    failures: int
    errors: int
    skipped: int
    issues: list[CaseIssue]
    report_issue: str = ""

    @property
    def passed(self) -> bool:
        return (
            self.returncode == 0
            and not self.report_issue
            and self.failures == 0
            and self.errors == 0
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Select, run, and summarize CTest C++ targets."
    )
    subparsers = parser.add_subparsers(dest="command")

    select_parser = subparsers.add_parser(
        "select",
        help="Build a GitHub Actions matrix from CTest family selections.",
    )
    select_parser.add_argument(
        "--mode",
        default="all",
        choices=("none", "all", "family_run", "batch_family_run"),
        help="C++ unit test selection mode.",
    )
    select_parser.add_argument(
        "--family",
        default="",
        help="CTest family for family_run mode.",
    )
    select_parser.add_argument(
        "--families",
        default="",
        help="Comma-separated CTest families for batch_family_run mode.",
    )
    select_parser.add_argument(
        "--github-output",
        default="",
        help="Optional GITHUB_OUTPUT path for matrix output.",
    )
    select_parser.add_argument(
        "--summary-path",
        default="",
        help="Optional GitHub step summary path to append Markdown output.",
    )

    run_parser = subparsers.add_parser(
        "run",
        help="Run one or more selected CTest families and summarize JUnit results.",
    )
    run_parser.add_argument("--build-dir", required=True, help="CMake build directory.")
    run_parser.add_argument(
        "--targets",
        required=True,
        help="all or comma-separated CTest families to run.",
    )
    run_parser.add_argument(
        "--reports-dir",
        required=True,
        help="Directory where per-target JUnit XML reports are written.",
    )
    run_parser.add_argument(
        "--summary-path",
        default="",
        help="Optional GitHub step summary path to append Markdown output.",
    )

    subparsers.add_parser(
        "list",
        help="List the public CTest family selectors.",
    )
    regex_parser = subparsers.add_parser(
        "label-regex",
        help="Build an anchored CTest label regex from literal family names.",
    )
    regex_parser.add_argument("families", nargs="+")
    return parser.parse_args()


def selected_targets(raw: str) -> list[str]:
    targets = [item.strip() for item in raw.split(",") if item.strip()]
    return targets or ["all"]


def comma_list(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(",") if item.strip()]


def exact_label_regex(families: list[str]) -> str:
    """Return one anchored ERE that treats every family name literally."""
    return "^(" + "|".join(re.escape(family) for family in families) + ")$"


def family_name_issues(families: tuple[str, ...] | list[str]) -> list[str]:
    """Return selector-name problems that would make focused builds ambiguous."""
    issues: list[str] = []
    seen_exact: set[str] = set()
    by_build_key: dict[str, list[str]] = {}

    for family in families:
        if not PUBLIC_FAMILY_PATTERN.fullmatch(family):
            issues.append(
                "public selectors must be lowercase and contain only letters, "
                f"numbers, _, or -: {family}"
            )
        if family in seen_exact:
            issues.append(f"duplicate selector: {family}")
        seen_exact.add(family)
        by_build_key.setdefault(family.lower(), []).append(family)

    for build_key, names in sorted(by_build_key.items()):
        distinct_names = sorted(set(names))
        if len(distinct_names) > 1:
            issues.append(
                "case-insensitive selector collision for "
                f"ctest-family-{build_key}: {', '.join(distinct_names)}"
            )

    return issues


def select_targets_for_mode(
    mode: str,
    family: str,
    raw_families: str,
) -> list[str]:
    if mode == "none":
        return []
    if mode == "all":
        return ["all"]
    if mode == "family_run":
        if family not in CPP_FAMILIES:
            raise ValueError(
                f"Unknown C++ test family: {family}\n"
                + "Valid families: "
                + ", ".join(CPP_FAMILIES)
            )
        return [family]
    if mode == "batch_family_run":
        families = comma_list(raw_families)
        if not families:
            raise ValueError("No C++ test families were selected.")
        invalid = [item for item in families if item not in CPP_FAMILIES]
        if invalid:
            raise ValueError(
                "Unknown C++ test family/families: "
                + ", ".join(invalid)
                + "\nValid families: "
                + ", ".join(CPP_FAMILIES)
            )
        return families
    raise ValueError(f"Unknown C++ test selection mode: {mode}")


def safe_filename(target: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", target.strip())
    return safe.strip("._") or "all"


def matrix_for_targets(raw: str) -> dict[str, list[dict[str, str]]]:
    return matrix_for_selected_targets(selected_targets(raw))


def matrix_for_selected_targets(targets: list[str]) -> dict[str, list[dict[str, str]]]:
    return {
        "include": [
            {"target": target, "artifact": f"cpp-unit-test-report-{safe_filename(target)}"}
            for target in targets
        ]
    }


def build_selection_summary(targets: list[str]) -> str:
    lines = [
        "### Selected CTest Families",
        "",
        "| family |",
        "| --- |",
    ]
    if targets:
        for target in targets:
            lines.append(f"| `{target}` |")
    else:
        lines.append("| _none_ |")
    lines.append("")
    return "\n".join(lines)


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def case_name(case: ET.Element) -> str:
    class_name = case.attrib.get("classname", "")
    name = case.attrib.get("name", "<unnamed>")
    if class_name:
        return f"{class_name}.{name}"
    return name


def child_text(element: ET.Element) -> str:
    message = element.attrib.get("message", "").strip()
    body = (element.text or "").strip()
    if message and body:
        return f"{message}: {body}"
    return message or body


def parse_junit_report(report_path: Path) -> tuple[int, int, int, int, list[CaseIssue], str]:
    if not report_path.exists():
        return 0, 0, 0, 0, [], f"Report file was not found at `{report_path}`."

    try:
        root = ET.parse(report_path).getroot()
    except ET.ParseError as err:
        return 0, 0, 0, 0, [], f"Report file `{report_path}` was not valid XML: {err}."

    cases = list(root.iterfind(".//testcase"))
    if local_name(root.tag) == "testcase":
        cases.append(root)

    failures = 0
    errors = 0
    skipped = 0
    issues: list[CaseIssue] = []

    for case in cases:
        for child in list(case):
            status = local_name(child.tag)
            if status == "failure":
                failures += 1
                issues.append(CaseIssue(case_name(case), status, child_text(child)))
            elif status == "error":
                errors += 1
                issues.append(CaseIssue(case_name(case), status, child_text(child)))
            elif status == "skipped":
                skipped += 1

    return len(cases), failures, errors, skipped, issues, ""


def ctest_command(build_dir: Path, target: str, report_path: Path) -> list[str]:
    command = [
        "ctest",
        "--test-dir",
        str(build_dir),
        "--output-on-failure",
        "--no-tests=error",
        "--output-junit",
        str(report_path),
    ]
    if target != "all":
        command[4:4] = ["-L", exact_label_regex([target])]
    return command


def run_target(build_dir: Path, reports_dir: Path, target: str) -> TargetResult:
    report_path = reports_dir / f"{safe_filename(target)}.xml"
    command = ctest_command(build_dir, target, report_path)
    completed = subprocess.run(command, check=False)
    tests, failures, errors, skipped, issues, report_issue = parse_junit_report(report_path)
    return TargetResult(
        target=target,
        report_path=report_path,
        command=command,
        returncode=completed.returncode,
        tests=tests,
        failures=failures,
        errors=errors,
        skipped=skipped,
        issues=issues,
        report_issue=report_issue,
    )


def build_summary(results: list[TargetResult]) -> str:
    lines = [
        "### C++ Unit Tests",
        "",
        "| target | verdict | tests | failures | errors | skipped | report |",
        "| --- | --- | ---: | ---: | ---: | ---: | --- |",
    ]

    for result in results:
        verdict = "pass" if result.passed else "fail"
        lines.append(
            "| `{target}` | `{verdict}` | {tests} | {failures} | {errors} | {skipped} | `{report}` |".format(
                target=result.target,
                verdict=verdict,
                tests=result.tests,
                failures=result.failures,
                errors=result.errors,
                skipped=result.skipped,
                report=result.report_path,
            )
        )

    issues = [
        result
        for result in results
        if result.report_issue or result.returncode != 0 or result.issues
    ]
    if issues:
        lines.extend(["", "#### Failing Cases", ""])
        for result in issues:
            lines.append(f"##### `{result.target}`")
            lines.append("")
            lines.append(f"- Command: `{' '.join(result.command)}`")
            if result.returncode != 0:
                lines.append(f"- CTest exit code: `{result.returncode}`")
            if result.report_issue:
                lines.append(f"- {result.report_issue}")

            if result.issues:
                lines.extend(
                    [
                        "",
                        "| case | status | message |",
                        "| --- | --- | --- |",
                    ]
                )
                for issue in result.issues[:25]:
                    lines.append(
                        f"| `{issue.name}` | `{issue.status}` | {issue.message or '-'} |"
                    )
                if len(result.issues) > 25:
                    lines.append(
                        f"| _{len(result.issues) - 25} more_ | - | See `{result.report_path}`. |"
                    )
            lines.append("")

    lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()

    if args.command == "select":
        targets = select_targets_for_mode(
            args.mode,
            args.family,
            args.families,
        )
        matrix = matrix_for_selected_targets(targets)
        if args.github_output:
            with Path(args.github_output).open("a", encoding="utf-8") as handle:
                handle.write(f"matrix={json.dumps(matrix, separators=(',', ':'))}\n")
                handle.write(f"selected_targets={','.join(targets)}\n")
        summary = build_selection_summary(targets)
        print(summary)
        if args.summary_path:
            with Path(args.summary_path).open("a", encoding="utf-8") as handle:
                handle.write(summary)
                if not summary.endswith("\n"):
                    handle.write("\n")
        return 0

    if args.command == "list":
        print("\n".join(CPP_FAMILIES))
        return 0

    if args.command == "label-regex":
        print(exact_label_regex(args.families))
        return 0

    if args.command != "run":
        raise ValueError(f"Unknown command: {args.command}")

    build_dir = Path(args.build_dir).resolve()
    reports_dir = Path(args.reports_dir).resolve()
    reports_dir.mkdir(parents=True, exist_ok=True)

    results = [
        run_target(build_dir, reports_dir, target)
        for target in selected_targets(args.targets)
    ]
    summary = build_summary(results)
    print(summary)

    if args.summary_path:
        summary_path = Path(args.summary_path)
        with summary_path.open("a", encoding="utf-8") as handle:
            handle.write(summary)
            if not summary.endswith("\n"):
                handle.write("\n")

    return 0 if all(result.passed for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
