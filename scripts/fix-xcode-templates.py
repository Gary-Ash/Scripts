#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  fix-xcode-templates.py
#
# This script will "fix" the internal Xcode project and file templates by searching for
# instances of the comment marker // ___FILEHEADER___ and removing double slashes.
#
# NOTE: This script must be run sudo
#
#  Author   :  Gary Ash <gary.ash@icloud.com>
#  Created  :   1-Sep-2026  4:42pm
#  Modified :   8-Nov-2026  7:11pm
#
#  Copyright © 2026 By Gary Ash All rights reserved.
# ****************************************************************************************
import os
import re
import sys
from pathlib import Path

XCODE_CONTENTS = Path("/Applications/Xcode.app/Contents")
STRINGS_TEMPLATE = XCODE_CONTENTS / (
    "Developer/Library/Xcode/Templates/File Templates/MultiPlatform/Resource/"
    "Strings File (Legacy).xctemplate/___FILEBASENAME___.strings"
)

# the templates are a mix of text and binaries, so they are edited as bytes
FILE_HEADER_MARKER = re.compile(rb"//\s*___FILEHEADER___")


# ****************************************************************************************
# process a source file, returning False if it could not be read or written
# ****************************************************************************************
def process_file(path: Path) -> bool:
    try:
        source = path.read_bytes()
    except OSError as error:
        sys.stderr.write(f"*** Unable to read the {path} - {error}\n")
        return False

    fixed = FILE_HEADER_MARKER.sub(b"___FILEHEADER___", source)
    if fixed == source:
        return True

    try:
        path.write_bytes(fixed)
    except OSError as error:
        sys.stderr.write(f"*** Unable to write the {path} - {error}\n")
        return False
    return True


# ****************************************************************************************
# script main line
# ****************************************************************************************
if os.geteuid() != 0:
    sys.stderr.write("*** This script must be run with sudo\n")
    sys.exit(1)

if not XCODE_CONTENTS.is_dir():
    sys.stderr.write(f"*** Unable to find {XCODE_CONTENTS}\n")
    sys.exit(1)

failed = False
for root, _dirs, files in os.walk(XCODE_CONTENTS):
    # every template Xcode ships lives inside a .xctemplate directory
    if not any(part.endswith(".xctemplate") for part in Path(root).parts):
        continue
    for name in files:
        candidate = Path(root) / name
        if candidate.is_file() and not process_file(candidate):
            failed = True

try:
    STRINGS_TEMPLATE.write_bytes(b"___FILEHEADER___")
except OSError as error:
    sys.stderr.write(f"*** Unable to write the {STRINGS_TEMPLATE} - {error}\n")
    failed = True

sys.exit(1 if failed else 0)
