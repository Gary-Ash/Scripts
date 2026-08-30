#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# git-plist-filter.sh
#
# This is a git filter will store plist files as xml
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Sep-2026  4:42pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

MODE="$1"

if [ "$MODE" = "clean" ]; then
	TMP=$(mktemp /tmp/git-plist-XXXX.plist)
	cat >"$TMP"
	/usr/bin/plutil -convert xml1 -o - "$TMP"
	rm "$TMP"

elif [ "$MODE" = "smudge" ]; then
	TMP=$(mktemp /tmp/git-plist-XXXX.plist)
	cat >"$TMP"
	/usr/bin/plutil -convert binary1 -o - "$TMP"
	rm "$TMP"
fi
