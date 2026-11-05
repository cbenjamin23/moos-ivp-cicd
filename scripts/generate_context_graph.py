#!/usr/bin/env python3
"""Generate compact agent context maps for this MOOS-IvP CI/CD repo."""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JSON_PATH = REPO_ROOT / "docs" / "context" / "dependency_tree.json"
DEFAULT_MD_PATH = REPO_ROOT / "docs" / "context" / "dependency_tree.md"

sys.path.insert(0, str(REPO_ROOT))

from scripts import ci_cpp_test_targets, ci_harness_case_count, harness_targets  # noqa: E402


SHELL_ASSIGN_RE = re.compile(r'^\s*([A-Z][A-Z0-9_]*)=(.*)$')
PROCESS_RE = re.compile(r"^\s*ProcessConfig\s*=\s*([A-Za-z0-9_]+)", re.MULTILINE)
SOURCE_RE = re.compile(r'^\s*(?:source|\.)\s+["\']?([^"\'\s]+)["\']?')
COMMON_INFRA_APPS = {
    "ANTLER",
    "pAutoPoke",
    "pHostInfo",
    "pLogger",
    "pMarineViewer",
    "pMissionEval",
    "pMissionHash",
    "pShare",
    "uLoadWatch",
    "uMayFinish",
    "uProcessWatch",
    "uTimerScript",
}


def is_generated_runtime_artifact(path: Path) -> bool:
    """Return true for generated mission logs and harness case-copy trees."""
    runtime_prefixes = (".parallel_", "LOG_", "MOOSLog_", "XLOG_")
    mission_result = path.name == "results.txt" and any(
        part in {"harnesses", "missions"} for part in path.parts
    )
    return mission_result or path.name == ".LastOpenedMOOSLogDirectory" or any(
        part == ".harness_runs" or part.startswith(runtime_prefixes)
        for part in path.parts
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate docs/context dependency maps for coding-agent orientation."
    )
    parser.add_argument(
        "--json-out",
        default=str(DEFAULT_JSON_PATH),
        help="Path for the generated JSON context graph.",
    )
    parser.add_argument(
        "--md-out",
        default=str(DEFAULT_MD_PATH),
        help="Path for the generated Markdown context map.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if generated outputs differ from the files on disk.",
    )
    return parser.parse_args()


def rel(path: Path | str) -> str:
    path = Path(path)
    try:
        return path.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def strip_shell_value(raw: str) -> str:
    value = raw.strip()
    if value.startswith("("):
        return ""
    if "#" in value:
        value = value.split("#", 1)[0].rstrip()
    if (
        len(value) >= 2
        and value[0] == value[-1]
        and value[0] in {"'", '"'}
    ):
        value = value[1:-1]
    return value


def resolve_shell_path(raw: str, harness_dir: Path, variables: dict[str, str]) -> str:
    value = strip_shell_value(raw)
    replacements = {
        "$HARNESS_DIR": rel(harness_dir),
        "${HARNESS_DIR}": rel(harness_dir),
        "$REPO_DIR": ".",
        "${REPO_DIR}": ".",
        "$MISSION_DIR": variables.get("MISSION_DIR", "$MISSION_DIR"),
        "${MISSION_DIR}": variables.get("MISSION_DIR", "$MISSION_DIR"),
    }
    for key, replacement in replacements.items():
        value = value.replace(key, replacement)
    value = value.replace("./", "", 1) if value.startswith("./") else value
    return value


def parse_shell_assignments(text: str, harness_dir: Path) -> dict[str, str]:
    variables: dict[str, str] = {}
    for line in text.splitlines():
        match = SHELL_ASSIGN_RE.match(line)
        if not match:
            continue
        key, raw_value = match.groups()
        value = strip_shell_value(raw_value)
        if not value:
            continue
        if "$REPO_DIR/" in value:
            value = value.split("$REPO_DIR/", 1)[1]
        elif "${REPO_DIR}/" in value:
            value = value.split("${REPO_DIR}/", 1)[1]
        elif value.startswith("$HARNESS_DIR/") or value.startswith("${HARNESS_DIR}/"):
            value = resolve_shell_path(value, harness_dir, variables)
        variables[key] = value
    return variables


def parse_sourced_helpers(text: str, variables: dict[str, str]) -> list[str]:
    helpers: list[str] = []
    for line in text.splitlines():
        match = SOURCE_RE.match(line)
        if not match:
            continue
        source = match.group(1)
        if source.startswith("$") and source[1:] in variables:
            source = variables[source[1:]]
        helpers.append(source)
    return sorted(set(helpers))


def parse_process_apps(paths: list[Path]) -> list[str]:
    apps: set[str] = set()
    for path in paths:
        text = read_text(path)
        apps.update(PROCESS_RE.findall(text))
    return sorted(apps)


def load_docs_harnesses() -> dict[str, Any]:
    docs_path = REPO_ROOT / "docs" / "tools" / "build_pages.py"
    module_name = "docs_build_pages_context_graph"
    spec = importlib.util.spec_from_file_location(module_name, docs_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {docs_path}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)

    docs_by_path: dict[str, Any] = {}
    for harness in module.HARNESSES:
        docs_by_path[harness.path] = {
            "slug": harness.slug,
            "title": harness.title,
            "family_label": harness.family,
            "mission": harness.mission,
            "source": "docs/tools/build_pages.py",
            "generated_page": f"docs/harnesses/{harness.slug}.html",
        }
    return docs_by_path


def harness_node(target: dict[str, Any], docs_by_path: dict[str, Any]) -> dict[str, Any]:
    harness_dir = REPO_ROOT / str(target["path"])
    zlaunch = harness_dir / "zlaunch.sh"
    zlaunch_text = read_text(zlaunch)
    variables = parse_shell_assignments(zlaunch_text, harness_dir)
    mission_path = str(variables.get("MISSION_DIR") or docs_by_path.get(target["path"], {}).get("mission", ""))
    mission_dir = REPO_ROOT / mission_path if mission_path else None

    case_names: list[str] = []
    case_parse_error = ""
    try:
        case_names = ci_harness_case_count.derive_case_order(zlaunch)
    except ValueError as err:
        case_parse_error = str(err)

    harness_files = sorted(
        path
        for path in harness_dir.iterdir()
        if path.is_file() and path.suffix in {".xmoos", ".xbhv", ".moos", ".bhv"}
    )
    mission_files: list[Path] = []
    if mission_dir and mission_dir.is_dir():
        mission_files = sorted(
            path
            for path in mission_dir.iterdir()
            if path.is_file() and path.suffix in {".moos", ".bhv", ".sh"}
        )

    process_paths = [
        path
        for path in harness_files + mission_files
        if path.suffix in {".moos", ".xmoos"}
    ]
    all_apps = parse_process_apps(process_paths)
    focus_apps = [app for app in all_apps if app not in COMMON_INFRA_APPS]

    return {
        "key": target["key"],
        "families": target["families"],
        "path": target["path"],
        "harness": target["harness"],
        "artifact": target["artifact"],
        "perf_profile": target.get("perf_profile", ""),
        "docs": docs_by_path.get(str(target["path"]), {}),
        "zlaunch": {
            "path": rel(zlaunch),
            "helpers": parse_sourced_helpers(zlaunch_text, variables),
            "case_count": len(case_names),
            "cases": case_names,
            "case_parse_error": case_parse_error,
        },
        "mission": {
            "path": mission_path,
        },
        "patches": {
            "file_count": len(harness_files),
        },
        "process_apps": all_apps,
        "focus_process_apps": focus_apps,
    }


def build_cpp_summary() -> dict[str, Any]:
    cpp_root = REPO_ROOT / "tests" / "cpp"
    sources = sorted(cpp_root.rglob("*.cpp")) if cpp_root.is_dir() else []
    family_sources: dict[str, list[Path]] = defaultdict(list)
    for source in sources:
        try:
            family = source.relative_to(cpp_root).parts[0]
        except IndexError:
            continue
        family_sources[family].append(source)

    families: dict[str, dict[str, Any]] = {}
    for family in ci_cpp_test_targets.CPP_FAMILIES:
        family_root = cpp_root / family
        subareas: list[str] = []
        if family_root.is_dir():
            subareas = sorted(
                path.name
                for path in family_root.iterdir()
                if path.is_dir() and any(path.rglob("*.cpp"))
            )
        families[family] = {
            "path": rel(family_root),
            "source_count": len(family_sources.get(family, [])),
            "subareas": subareas,
        }

    return {
        "path": "tests/cpp",
        "source_count": len(sources),
        "known_ci_families": list(ci_cpp_test_targets.CPP_FAMILIES),
        "source_count_by_family": {
            family: data["source_count"]
            for family, data in families.items()
            if data["source_count"]
        },
        "families": families,
    }


def build_graph() -> dict[str, Any]:
    targets = harness_targets.load_targets()
    harness_targets.validate_targets(targets)
    docs_by_path = load_docs_harnesses()
    harnesses = [harness_node(target, docs_by_path) for target in targets]

    family_index: dict[str, list[str]] = defaultdict(list)
    app_index: dict[str, list[str]] = defaultdict(list)
    for node in harnesses:
        for family in node["families"]:
            family_index[str(family)].append(str(node["key"]))
        for app in node["process_apps"]:
            app_index[app].append(str(node["key"]))

    file_counts = Counter(
        path.suffix or "[none]"
        for base in ("harnesses", "missions", "scripts", "tests", "src", "docs")
        for path in (REPO_ROOT / base).rglob("*")
        if path.is_file()
        and path.suffix != ".pyc"
        and "__pycache__" not in path.parts
        and not is_generated_runtime_artifact(path)
    )

    return {
        "schema": "moos-ivp-cicd-context-graph.v1",
        "generated_by": "scripts/generate_context_graph.py",
        "repo": {
            "root": rel(REPO_ROOT),
            "harness_target_count": len(harnesses),
            "harness_zlaunch_count": len(
                [
                    path
                    for path in (REPO_ROOT / "harnesses").rglob("zlaunch.sh")
                    if not is_generated_runtime_artifact(path)
                ]
            ),
            "mission_config_count": len(
                [
                    path
                    for path in (REPO_ROOT / "missions").rglob("*")
                    if path.is_file() and path.suffix in {".moos", ".bhv", ".sh"}
                ]
            ),
            "harness_patch_count": sum(node["patches"]["file_count"] for node in harnesses),
            "file_counts_by_suffix": dict(sorted(file_counts.items())),
        },
        "sources": {
            "harness_targets": rel(harness_targets.DEFAULT_TARGETS_PATH),
            "docs_catalog": "docs/tools/build_pages.py",
            "cpp_ci_families": "scripts/ci_cpp_test_targets.py",
            "case_parser": "scripts/ci_harness_case_count.py",
            "agent_rules": "AGENTS.md",
        },
        "indices": {
            "families": {key: sorted(value) for key, value in sorted(family_index.items())},
            "process_apps": {key: sorted(value) for key, value in sorted(app_index.items())},
        },
        "harnesses": harnesses,
        "cpp_tests": build_cpp_summary(),
    }


def md_join(values: list[str]) -> str:
    if not values:
        return "-"
    return ", ".join(f"`{value}`" for value in values)


def app_hints(node: dict[str, Any], graph: dict[str, Any], limit: int = 4) -> list[str]:
    app_counts = {
        app: len(keys)
        for app, keys in graph["indices"]["process_apps"].items()
    }
    apps = [
        app
        for app in node["focus_process_apps"]
        if app_counts.get(app, 0) <= 13
    ]
    apps.sort(key=lambda item: (app_counts.get(item, 0), item.lower()))
    return apps[:limit]


def render_markdown(graph: dict[str, Any]) -> str:
    repo = graph["repo"]
    mission_index: dict[str, list[str]] = defaultdict(list)
    for node in graph["harnesses"]:
        mission = node["mission"]["path"]
        if mission:
            mission_index[mission].append(str(node["key"]))

    lines = [
        "# Generated Repo Traversal Map",
        "",
        "<!-- Generated by scripts/generate_context_graph.py; do not edit by hand. -->",
        "",
        "This is a compact traversal surface for the MOOS-IvP CI/CD test workspace.",
        "It is meant to answer: given a target, family, mission stem, or app, which",
        "repo files should be opened next?",
        "",
        "## Summary",
        "",
        f"- Harness targets: `{repo['harness_target_count']}`",
        f"- Harness launchers: `{repo['harness_zlaunch_count']}` under `harnesses/**/zlaunch.sh`",
        f"- Harness patch/config files: `{repo['harness_patch_count']}` under configured targets",
        f"- Mission launch/config files: `{repo['mission_config_count']}` under `missions/`",
        f"- C++ test sources: `{graph['cpp_tests']['source_count']}`",
        "",
        "## Repo Layers",
        "",
        "- `harnesses/`: patch-driven MOOS harness matrices; open target `zlaunch.sh` first.",
        "- `missions/`: reusable MOOS mission stems consumed by harnesses.",
        "- `tests/cpp/`: GoogleTest/CTest library-level tests.",
        "- `config/`: harness target registry metadata.",
        "- `scripts/`: target selection, validation, cleanup, and generated-map tooling.",
        "- `docs/`: generated/static harness catalog and visual assets.",
        "- `src/`: legacy/example MOOS app code still built by the repo.",
        "",
        "## Inputs",
        "",
        f"- Harness target registry: `{graph['sources']['harness_targets']}`",
        f"- Harness docs catalog: `{graph['sources']['docs_catalog']}`",
        f"- C++ CI families: `{graph['sources']['cpp_ci_families']}`",
        f"- Harness case parser: `{graph['sources']['case_parser']}`",
        f"- Agent rules: `{graph['sources']['agent_rules']}`",
        "",
        "## Traversal Edges",
        "",
        "- Harness work: target key -> harness `zlaunch.sh` -> mission stem -> case",
        "  patch files.",
        "- Mission work: mission stem -> configured harness targets that reuse it ->",
            "  case patches. Open `zlaunch.sh` for exact case-to-patch mapping.",
        "- CI/docs work: `config/harness_targets.json` -> workflow choices ->",
        "  docs catalog slug -> generated harness page.",
        "- Docs page edits: edit `docs/tools/build_pages.py`; treat",
        "  `docs/harnesses/<slug>.html` as generated output.",
        "- C++ work: CTest family in `scripts/ci_cpp_test_targets.py` ->",
        "  matching labels under `tests/cpp/` -> focused",
        "  `./tests/cpp/ctests.sh --<family>` run.",
        "",
        "## Detailed Lookup",
        "",
        "Use the JSON only for targeted queries; do not paste it wholesale into a",
        "context window. The JSON is an index; detailed patch wiring remains in",
        "each harness `zlaunch.sh`.",
        "",
        "```bash",
        "jq '.harnesses[] | select(.key == \"ufld_obstacle_sim_h01\")' docs/context/dependency_tree.json",
        "jq '.indices.process_apps.uFldObstacleSim' docs/context/dependency_tree.json",
        "jq '.harnesses[] | select(.mission.path == \"missions/colregs_missions/colregs_unit\") | .key' docs/context/dependency_tree.json",
        "jq '.harnesses[] | select(.key == \"psearchgrid_h01\") | .docs' docs/context/dependency_tree.json",
        "jq '.cpp_tests.families.mbutil' docs/context/dependency_tree.json",
        "```",
        "",
        "## Implementation Routes",
        "",
        "- App-level unit harness exemplar: `cmgr_h01`",
        "  (`harnesses/cmgr_harnesses/H01-cmgr_unit/zlaunch.sh`).",
        "- Single-app shoreside unit exemplar: `ufld_obstacle_sim_h01`",
        "  (`harnesses/ufld_obstacle_sim_harnesses/H01-ufld_obstacle_sim_unit/zlaunch.sh`).",
        "- Shared app-unit stem exemplar: `missions/ufield_app_missions/ufield_app_unit`",
        "  with the `ufld_*_h01` targets listed under Shared Mission Stems.",
        "- Moving/integration exemplar: `obmgr_h02`",
        "  (`harnesses/obmgr_harnesses/H02-obmgr_motion/zlaunch.sh`).",
        "",
        "## Validation Routes",
        "",
        "- Target registry: `python3 scripts/list_harness_targets.py validate`.",
        "- One harness case count: `python3 scripts/ci_harness_case_count.py <harness>/zlaunch.sh`.",
        "- Generated traversal map: `python3 scripts/generate_context_graph.py --check`.",
        "- Full static repo invariants: `python3 scripts/check_repo_invariants.py`.",
        "",
        "## Target Routes",
        "",
        "| Key | Family | Open First | Mission Stem | Cases | Low-Fanout Apps | Docs Slug |",
        "| --- | --- | --- | --- | ---: | --- | --- |",
    ]

    for node in graph["harnesses"]:
        apps = app_hints(node, graph)
        docs = node["docs"].get("slug", "")
        lines.append(
            "| "
            + " | ".join(
                [
                    f"`{node['key']}`",
                    md_join([str(item) for item in node["families"]]),
                    f"`{node['zlaunch']['path']}`",
                    f"`{node['mission']['path']}`" if node["mission"]["path"] else "",
                    str(node["zlaunch"]["case_count"]),
                    md_join(apps),
                    f"`{docs}`" if docs else "",
                ]
            )
            + " |"
        )

    lines.extend(
        [
            "",
            "## Shared Mission Stems",
            "",
            "These stems have multiple configured harness targets. A stem edit should",
            "start by checking every listed target.",
            "",
        ]
    )
    for mission, keys in sorted(mission_index.items(), key=lambda item: (-len(item[1]), item[0])):
        if len(keys) <= 1:
            continue
        lines.append(f"- `{mission}`: {md_join(sorted(keys))}")

    lines.extend(
        [
            "",
            "## Low-Fanout App Index",
            "",
            "Only apps appearing in 13 or fewer targets are shown here. Broad",
            "infrastructure apps are intentionally omitted from this Markdown view;",
            "the full `ProcessConfig` map is in `docs/context/dependency_tree.json`.",
            "",
        ]
    )
    for app, keys in graph["indices"]["process_apps"].items():
        if app in COMMON_INFRA_APPS or len(keys) > 13:
            continue
        lines.append(f"- `{app}`: {md_join(keys)}")

    lines.extend(
        [
            "",
            "## C++ Traversal",
            "",
            "- Family names are defined in `scripts/ci_cpp_test_targets.py`.",
            "- Source roots follow `tests/cpp/<family>` when that directory exists.",
            "- Detailed family source counts are in `docs/context/dependency_tree.json`.",
        ]
    )

    lines.append("")
    return "\n".join(lines)


def write_or_check(path: Path, content: str, check: bool) -> bool:
    if check:
        if not path.is_file():
            print(f"Missing generated file: {path}", file=sys.stderr)
            return False
        current = path.read_text(encoding="utf-8")
        if current != content:
            print(f"Generated file is out of date: {path}", file=sys.stderr)
            return False
        return True

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return True


def main() -> int:
    args = parse_args()
    graph = build_graph()
    json_content = json.dumps(graph, indent=2, sort_keys=True) + "\n"
    md_content = render_markdown(graph)

    ok_json = write_or_check(Path(args.json_out), json_content, args.check)
    ok_md = write_or_check(Path(args.md_out), md_content, args.check)
    if args.check and not (ok_json and ok_md):
        return 1

    if not args.check:
        print(f"Wrote {args.json_out}")
        print(f"Wrote {args.md_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
