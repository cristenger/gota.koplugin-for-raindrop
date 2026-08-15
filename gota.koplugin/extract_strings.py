#!/usr/bin/env python3
"""Extract Gota gettext messages without overwriting existing translations."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
POT_PATH = ROOT / "l10n" / "templates" / "gota.pot"
VERSION = "2.2.0"


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise SystemExit(
            f"Missing required gettext tool: {name}. "
            "Install GNU gettext and try again."
        )
    return path


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> None:
    xgettext = require_tool("xgettext")
    msgmerge = require_tool("msgmerge")
    lua_files = sorted(path.name for path in ROOT.glob("*.lua"))
    if not lua_files:
        raise SystemExit("No Lua source files found")

    POT_PATH.parent.mkdir(parents=True, exist_ok=True)
    run([
        xgettext,
        "--language=Lua",
        "--from-code=UTF-8",
        "--keyword=_",
        "--add-comments=translators",
        "--sort-by-file",
        "--no-wrap",
        "--package-name=Gota Plugin",
        f"--package-version={VERSION}",
        "--msgid-bugs-address=https://github.com/cristenger/gota.koplugin-for-raindrop/issues",
        f"--output={POT_PATH.relative_to(ROOT)}",
        *lua_files,
    ])

    po_files = sorted((ROOT / "l10n").glob("*/gota.po"))
    for po_path in po_files:
        run([
            msgmerge,
            "--update",
            "--backup=none",
            "--no-fuzzy-matching",
            "--no-wrap",
            str(po_path.relative_to(ROOT)),
            str(POT_PATH.relative_to(ROOT)),
        ])

    print(f"Extracted messages from {len(lua_files)} Lua files")
    print(f"Updated template: {POT_PATH.relative_to(ROOT)}")
    for po_path in po_files:
        print(f"Merged translations: {po_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
