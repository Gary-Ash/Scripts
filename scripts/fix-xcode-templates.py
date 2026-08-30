#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  fix-xcode-templates.py
#
# This script will "fix" the internal Xcode project and file templates my searching for
# instances of the comment marker // ___FILEHEADER___ and removing double slashes.
#
# NOTE: This script must be run sudo
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

XCODE_CONTENTS = Path("/Applications/Xcode.app/Contents")
STRINGS_TEMPLATE = XCODE_CONTENTS / (
    "Developer/Library/Xcode/Templates/File Templates/MultiPlatform/Resource/"
    "Strings File.xctemplate/___FILEBASENAME___.strings"
)

# the templates are a mix of text and binaries, so they are edited as bytes
FILE_HEADER_MARKER = re.compile(rb"//\s*___FILEHEADER___")


# ****************************************************************************************
# process a source file
# ****************************************************************************************
def process_file(path):
    try:
        source = path.read_bytes()
    except OSError as error:
        sys.stderr.write(f"*** Unable to read the {path} - {error}\n")
        sys.exit(1)

    source = FILE_HEADER_MARKER.sub(b"___FILEHEADER___", source)

    try:
        path.write_bytes(source)
    except OSError as error:
        sys.stderr.write(f"*** Unable to read the {path} - {error}\n")
        sys.exit(1)


# ****************************************************************************************
# script main line
# ****************************************************************************************
for root, _dirs, files in os.walk(XCODE_CONTENTS):
    for name in files:
        candidate = Path(root) / name
        if candidate.is_file():
            process_file(candidate)

try:
    STRINGS_TEMPLATE.write_bytes(b"___FILEHEADER___")
except OSError:
    pass
