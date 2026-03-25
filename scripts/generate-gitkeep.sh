#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# generate-gitkeep.sh
#
# create a shell script that traverses a directory tree and put a .gitkeep file in any
# directory that does contain a file
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  24-Mar-2026  8:38pm
# Modified :  24-Mar-2026  8:45pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

# If an argument is provided, ensure it's a directory
if [ -n "$1" ]; then
    if [ ! -d "$1" ]; then
        echo "Error: '$1' is not a directory"
        exit 1
    fi
    ROOT="$1"
else
    ROOT="."
fi

# Traverse all directories
find "$ROOT" -type d | while read -r dir; do
    # Check whether the directory contains *any* files (not counting subdirectories)
    if ! find "$dir" -maxdepth 1 -type f | read -r _; then
        # Directory has no files — add .gitkeep
        touch "$dir/.gitkeep"
        echo "Added .gitkeep to: $dir"
    fi
done
