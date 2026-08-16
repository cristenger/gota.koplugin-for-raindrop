#!/usr/bin/env python3
"""Audit Spanish gettext coverage, placeholders, and untranslated lookalikes."""

from __future__ import annotations

import ast
import re
import sys
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PO_PATH = ROOT / "l10n" / "es" / "gota.po"
PLACEHOLDER_RE = re.compile(r"(?<!%)%(?:\d+\$)?[-+0 #]*\d*(?:\.\d+)?[sdif]")

# Proper names, protocol/UI literals, Spanish cognates, and intentionally shared
# short type abbreviations. Every other source-equal translation is an error.
EQUALITY_ALLOWLIST = {
    "Gota",
    "Color: ",
    "URL: ",
    "No",
    "Audio",
    "Art.",
    "Img.",
    "Doc.",
    "Aud.",
    " (PRO)",
}


def quoted_value(source: str) -> str:
    return ast.literal_eval(source)


def parse_catalog(path: Path) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    current: dict[str, object] = {}
    active_field: str | None = None

    def finish() -> None:
        nonlocal current, active_field
        if current.get("msgid") is not None:
            entries.append(current)
        current = {}
        active_field = None

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if raw_line.startswith("#~"):
            continue
        if not raw_line:
            finish()
        elif raw_line.startswith("#,"):
            current["flags"] = raw_line[2:].strip()
        elif raw_line.startswith("msgid "):
            active_field = "msgid"
            current[active_field] = quoted_value(raw_line[6:])
        elif raw_line.startswith("msgstr "):
            active_field = "msgstr"
            current[active_field] = quoted_value(raw_line[7:])
        elif raw_line.startswith('"') and active_field:
            current[active_field] = str(current.get(active_field, "")) + quoted_value(raw_line)
    finish()
    return entries


def placeholders(value: str) -> Counter[str]:
    return Counter(PLACEHOLDER_RE.findall(value))


def main() -> int:
    errors: list[str] = []
    entries = [entry for entry in parse_catalog(PO_PATH) if entry.get("msgid")]
    for entry in entries:
        msgid = str(entry.get("msgid", ""))
        msgstr = str(entry.get("msgstr", ""))
        if "fuzzy" in str(entry.get("flags", "")):
            errors.append(f"fuzzy translation: {msgid!r}")
        if not msgstr:
            errors.append(f"missing translation: {msgid!r}")
            continue
        if placeholders(msgid) != placeholders(msgstr):
            errors.append(
                f"placeholder mismatch: {msgid!r} -> {msgstr!r} "
                f"({placeholders(msgid)} != {placeholders(msgstr)})"
            )
        if msgid == msgstr and msgid not in EQUALITY_ALLOWLIST:
            errors.append(f"source-equal translation is not allowlisted: {msgid!r}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        f"PASS translations: {len(entries)} Spanish messages; "
        f"{len(EQUALITY_ALLOWLIST)} justified source-equal entries"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
