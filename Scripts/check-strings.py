#!/usr/bin/env python3
"""Compare every Localizations/<lang>.lproj/Localizable.strings against the English base.

Reports missing keys, keys that do not exist in English, and placeholder mismatches.
Exit status is non-zero if any language has a problem, so it can run in CI.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCALIZATIONS = ROOT / "Localizations"
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:@|lld|ld|d|f|s|%)")


def parse(path: pathlib.Path) -> dict[str, str]:
    entries = {}
    for m in re.finditer(
        r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";',
        path.read_text(),
        re.MULTILINE,
    ):
        entries[m.group(1)] = m.group(2)
    return entries


def main() -> int:
    base = parse(LOCALIZATIONS / "en.lproj" / "Localizable.strings")
    problems = 0
    for folder in sorted(LOCALIZATIONS.glob("*.lproj")):
        lang = folder.name.removesuffix(".lproj")
        if lang == "en":
            continue
        table = folder / "Localizable.strings"
        if not table.exists():
            print(f"{lang}: no Localizable.strings")
            problems += 1
            continue
        strings = parse(table)
        missing = sorted(k for k in base if k not in strings)
        extra = sorted(k for k in strings if k not in base)
        mismatched = sorted(
            k
            for k in strings
            if k in base
            and sorted(PLACEHOLDER.findall(k)) != sorted(PLACEHOLDER.findall(strings[k]))
        )
        done = len(base) - len(missing)
        print(f"{lang}: {done}/{len(base)} translated")
        for label, items in (
            ("missing", missing),
            ("not in English", extra),
            ("placeholder mismatch", mismatched),
        ):
            for k in items:
                print(f"  {label}: {k}")
        problems += len(extra) + len(mismatched)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
