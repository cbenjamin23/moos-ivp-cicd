from __future__ import annotations

import os
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def configured_moos_ivp_root() -> Path | None:
    for name in ("MOOS_IVP_SOURCE", "MOOSIVP_SOURCE_TREE_BASE"):
        raw_value = os.environ.get(name)
        if raw_value:
            return Path(raw_value).expanduser().resolve()

    cache_path = ROOT / "build" / "CMakeCache.txt"
    if cache_path.is_file():
        cache_text = cache_path.read_text(encoding="utf-8", errors="replace")
        match = re.search(
            r"^MOOSIVP_SOURCE_TREE_BASE:PATH=(.+)$",
            cache_text,
            re.MULTILINE,
        )
        if match:
            return Path(match.group(1)).expanduser().resolve()

    sibling = ROOT.parent / "moos-ivp"
    if sibling.is_dir():
        return sibling.resolve()

    return None


def function_definition(text: str, signature: str) -> str:
    start = text.find(signature)
    if start == -1:
        raise AssertionError(f"missing function definition: {signature}")

    opening_brace = text.find("{", start)
    if opening_brace == -1:
        raise AssertionError(f"missing opening brace: {signature}")

    depth = 0
    for index in range(opening_brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start : index + 1]

    raise AssertionError(f"missing closing brace: {signature}")


class PMarineViewerRefreshModeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        source_root = configured_moos_ivp_root()
        if source_root is None:
            raise unittest.SkipTest(
                "MOOS-IvP checkout not found; set MOOS_IVP_SOURCE"
            )

        cls.pmv_dir = source_root / "ivp" / "src" / "pMarineViewer"
        required = (
            cls.pmv_dir / "PMV_MOOSApp.cpp",
            cls.pmv_dir / "PMV_GUI.cpp",
            cls.pmv_dir / "PMV_Info.cpp",
        )
        missing = [str(path) for path in required if not path.is_file()]
        if missing:
            raise AssertionError(
                "invalid MOOS-IvP source root; missing " + ", ".join(missing)
            )

        cls.app_text = required[0].read_text(encoding="utf-8")
        cls.gui_text = required[1].read_text(encoding="utf-8")
        cls.info_text = required[2].read_text(encoding="utf-8")

    def test_advertised_refresh_mode_reaches_existing_gui_setter(self) -> None:
        self.assertRegex(
            self.info_text,
            r"\brefresh_mode\s*=\s*events\b",
        )

        startup = function_definition(
            self.app_text,
            "void PMV_MOOSApp::handleStartUp",
        )
        self.assertRegex(
            startup,
            r'else\s+if\s*\(\s*param\s*==\s*"refresh_mode"\s*\)\s*'
            r"handled\s*=\s*m_gui->setRadioCastAttrib\(\s*param\s*,\s*value\s*\)\s*;",
        )

    def test_existing_gui_setter_updates_both_refresh_state_consumers(self) -> None:
        setter = function_definition(
            self.gui_text,
            "bool PMV_GUI::setRadioCastAttrib",
        )
        refresh_branch = re.search(
            r'else\s+if\s*\(\s*attr\s*==\s*"refresh_mode"\s*\)\s*\{(.*?)\n\s*\}',
            setter,
            re.DOTALL,
        )

        self.assertIsNotNone(refresh_branch)
        assert refresh_branch is not None
        self.assertIn(
            "m_repo->setRefreshMode(value);",
            refresh_branch.group(1),
        )
        self.assertIn(
            "ok = m_icast_settings.setRefreshMode(value);",
            refresh_branch.group(1),
        )

    def test_request_loops_consume_the_states_updated_by_the_setter(self) -> None:
        appcast_requesting = function_definition(
            self.app_text,
            "void PMV_MOOSApp::handleAppCastRequesting",
        )
        realmcast_requesting = function_definition(
            self.app_text,
            "void PMV_MOOSApp::handleRealmCastRequesting",
        )

        self.assertIn(
            "m_appcast_repo->getRefreshMode()",
            appcast_requesting,
        )
        self.assertRegex(
            realmcast_requesting,
            r'getInfoCastSettings\(\)\.getRefreshMode\(\)\s*==\s*"paused"',
        )


if __name__ == "__main__":
    unittest.main()
