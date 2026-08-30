#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  check-path.py
#
# This little utility will scan the current PATH and make a list directories that exist
# and those that don't
#
#  Author   :  Gary Ash <gary.ash@icloud.com>
#  Created  :   1-Sep-2026  4:42pm
#  Modified :
#
#  Copyright © 2026 By Gary Ash All rights reserved.
# ****************************************************************************************
import os
import sys
from pathlib import Path

path_env = os.environ.get("PATH", "")

if not path_env:
    sys.stderr.write("PATH environment variable is not set\n")
    sys.exit(1)

paths = path_env.split(":")

total = len(paths)
existing = 0
missing = 0
clean_paths = []

print("Checking PATH directories:")
print("=" * 60 + "\n")

for directory in paths:
    if Path(directory).is_dir():
        print(f"􀆅   {directory}")
        clean_paths.append(directory)
        existing += 1
    else:
        print(f"􀀲   {directory}")
        missing += 1

print("\n\nA clean PATH declaration:")
print("=" * 60 + "\n")
print('export PATH="' + ":".join(clean_paths) + '"')

print("\n" + "=" * 60)
print("Summary:")
print(f"  Total:    {total}")
print(f"  Existing: {existing}")
print(f"  Missing:  {missing}")
print("=" * 60)
