#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  strip-comments.py
#
# Strip comments from C source code
#
#  Author   :  Gary Ash <gary.ash@icloud.com>
#  Created  :   1-Sep-2026  4:42pm
#  Modified :
#
#  Copyright © 2026 By Gary Ash All rights reserved.
# ****************************************************************************************
import os
import re
import sys
from pathlib import Path

EXTENSIONS = {
    "c",
    "cc",
    "cpp",
    "cs",
    "cxx",
    "swift",
    "m",
    "mm",
    "h",
    "hh",
    "hpp",
    "hxx",
    "pch",
}

BLANK_RUN = re.compile(r"^(\s*\r\n){2,}", re.MULTILINE)


# ****************************************************************************************
# zap the source code comments
#
# scanning is done a character at a time rather than with a regular expression so that
# comment markers inside string literals survive
# ****************************************************************************************
def zap(source):
    def at(index):
        return source[index] if 0 <= index < len(source) else ""

    index = 0
    length = len(source)

    while index < length:
        character = at(index)

        if character == '"':
            quote = character
            while index < length:
                index += 1
                character = at(index)
                if character == "\\":
                    index += 2
                    character = at(index)
                if character == quote:
                    break

        if character == "/":
            index += 1
            character = at(index)

            if character == "/":
                comment_start = index - 1
                while index < length and character != "\n":
                    index += 1
                    character = at(index)

                source = source[:comment_start] + source[index + 1 :]
                index = 0
                length = len(source)

            elif character == "*":
                nesting = 1
                comment_start = index - 1
                while index < length:
                    index += 1
                    character = at(index)
                    if character == "*":
                        index += 1
                        character = at(index)
                        if character == "/":
                            nesting -= 1
                            if nesting == 0:
                                break
                        else:
                            index -= 1
                    elif character == "/":
                        index += 1
                        character = at(index)
                        if character == "*":
                            nesting += 1
                        else:
                            index -= 1

                source = source[:comment_start] + " " + source[index + 1 :]
                index = 0
                length = len(source)

            else:
                index -= 1

        index += 1

    return source


# ****************************************************************************************
# process a source file
# ****************************************************************************************
def process_file(path):
    source = path.read_text(encoding="utf-8", errors="surrogateescape")

    source = zap(source)
    source = BLANK_RUN.sub("\n", source)

    path.write_text(source, encoding="utf-8", errors="surrogateescape")


# ****************************************************************************************
# main line
# ****************************************************************************************
def main(argv):
    work_root = Path(argv[0]) if argv else Path(".")

    for root, _dirs, files in os.walk(work_root):
        for name in files:
            path = Path(root) / name
            if path.suffix[1:] in EXTENSIONS and path.is_file():
                try:
                    process_file(path)
                except OSError as error:
                    sys.stderr.write(f"**** Unable to read {path} - {error}\n")
                    return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
