#!/usr/bin/env python3
# *****************************************************************************************
# rename_snippets.py
#
# rename Xcode code snippet files after their IDECodeSnippetTitle
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Nov-2026  8:31pm
# Modified :   8-Nov-2026  9:21pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
# *****************************************************************************************
import plistlib
import re
import sys
from pathlib import Path
from xml.parsers.expat import ExpatError

SNIPPET_SUFFIX = ".codesnippet"


def slug_for(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")


def report_skipped(path: Path, reason: str) -> None:
    print(f"skipped {path.name}: {reason}", file=sys.stderr)


def rename_snippets(directory: Path) -> None:
    for path in directory.glob("*" + SNIPPET_SUFFIX):
        try:
            title = plistlib.loads(path.read_bytes())["IDECodeSnippetTitle"]
        except (ValueError, ExpatError):
            report_skipped(path, "not a valid plist")
            continue
        except KeyError:
            report_skipped(path, "no IDECodeSnippetTitle")
            continue
        slug = slug_for(title)
        if not slug:
            report_skipped(path, "title has no letters or digits")
            continue
        target = path.with_name(slug + SNIPPET_SUFFIX)
        number = 2
        while target.exists() and target != path:
            target = path.with_name(f"{slug}-{number}{SNIPPET_SUFFIX}")
            number += 1
        if target == path:
            continue
        path.rename(target)
        print(f"{path.name} -> {target.name}")


def main(argv: list[str]) -> int:
    rename_snippets(Path.home() / "Library/Developer/Xcode/UserData/CodeSnippets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
