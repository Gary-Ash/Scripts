#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob dotglob
#*****************************************************************************************
# generate-gitkeep.sh
#
# create a shell script that traverses a directory tree and put a .gitkeep file in any
# directory that does contain a file
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Sep-2026  4:42pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

TARGET="${1:-.}"

find "$TARGET" -name .git -prune -o -type d -print0 | while IFS= read -r -d '' dir; do
	has_file=0

	for item in "$dir"/*; do
		if [[ ! -d $item ]]; then
			filename="${item##*/}"

			if [[ $filename != ".gitkeep" && $filename != ".DS_Store" ]]; then
				has_file=1
				break # We found a file, no need to keep checking this folder
			fi
		fi
	done

	if [[ $has_file -eq 0 ]]; then
		touch "$dir/.gitkeep"
	fi
done
