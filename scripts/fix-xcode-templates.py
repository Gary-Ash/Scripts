#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  fix-xcode-templates.py
#
# This script installs copies of Xcode's file templates in the user's template folder
# with the comment marker // ___FILEHEADER___ replaced by ___FILEHEADER___, so a block
# comment file header doesn't start with a stray double slash.  Xcode.app itself is
# never modified; editing its templates breaks its code signature.
#
#  Author   :  Gary Ash <gary.ash@icloud.com>
#  Created  :   1-Sep-2026  4:42pm
#  Modified :  19-Oct-2026  3:47pm
#
#  Copyright © 2026 By Gary Ash All rights reserved.
# ****************************************************************************************
import re
import shutil
import subprocess
from pathlib import Path

XCODE_CONTENTS = Path("/Applications/Xcode.app/Contents")
USER_TEMPLATES = Path.home() / "Library/Developer/Xcode/Templates"

# other kinds are generated from Xcode's editors (SiriKit, Core Data, refactoring), not
# from the New File dialog
TEXT_SUBSTITUTION_KIND = "Xcode.IDEFoundation.TextSubstitutionFileTemplateKind"

# the templates are a mix of text and binaries, so they are edited as bytes
FILE_HEADER_MARKER = re.compile(rb"//\s*___FILEHEADER___")


# ****************************************************************************************
# copy every file template that uses the marker into the user's template folder
# ****************************************************************************************
def install_templates(xcode_contents: Path, user_templates: Path) -> list[Path]:
    installed = []
    for template in sorted(xcode_contents.rglob("File Templates/**/*.xctemplate")):
        # plutil, unlike plistlib, reads the OpenStep format some templates still use
        kind = subprocess.run(
            ["plutil", "-extract", "Kind", "raw", template / "TemplateInfo.plist"],
            capture_output=True,
            text=True,
            check=False,
        ).stdout.strip()
        if kind != TEXT_SUBSTITUTION_KIND:
            continue
        if not any(
            path.is_file() and FILE_HEADER_MARKER.search(path.read_bytes())
            for path in template.rglob("*")
        ):
            continue
        relative = template.as_posix().split("/File Templates/", 1)[1]
        destination = user_templates / "File Templates" / relative
        shutil.rmtree(destination, ignore_errors=True)
        shutil.copytree(template, destination)
        for path in destination.rglob("*"):
            if path.is_file():
                path.write_bytes(
                    FILE_HEADER_MARKER.sub(b"___FILEHEADER___", path.read_bytes())
                )
        installed.append(destination)
    return installed


# ****************************************************************************************
# script main line
# ****************************************************************************************
if __name__ == "__main__":
    for installed in install_templates(XCODE_CONTENTS, USER_TEMPLATES):
        print(installed)
