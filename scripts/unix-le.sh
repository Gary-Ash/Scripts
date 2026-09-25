#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# unix-le.sh
#
# convert the line endings of every text file in a directory tree to Unix line feeds
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  24-Sep-2026  8:20pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

TARGET="${1:-.}"

find "$TARGET" -type f -print0 | while IFS= read -r -d '' file; do
	# Only process files that appear to be text
	if file --brief --mime-type "$file" | grep -q '^text/'; then
		printf 'Converting: %s\n' "$file"
		perl -pi -e 's/\r\n/\n/g; s/\r/\n/g' "$file"
	fi
done
