#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# git-applescript-filter.sh
#
# This is a git filter will store Applescript files as text
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  15-Mar-2026  3:39pm
# Modified :  15-Mar-2026  6:47pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

MODE="$1"

if [ "$MODE" = "clean" ]; then
	TMP=$(mktemp /tmp/git-ascr-XXXXXXXX)
	mv "$TMP" "$TMP.scpt"
	TMP="$TMP.scpt"
	cat >"$TMP"
	/usr/bin/osadecompile "$TMP" 2>/dev/null || /usr/bin/osadecompile -l JavaScript "$TMP"
	rm "$TMP"

elif [ "$MODE" = "smudge" ]; then
	SRC=$(mktemp /tmp/git-ascr-XXXXXXXX)
	TMP=$(mktemp /tmp/git-ascr-XXXXXXXX)
	mv "$SRC" "$SRC.txt"
	SRC="$SRC.txt"
	mv "$TMP" "$TMP.scpt"
	TMP="$TMP.scpt"
	cat >"$SRC"
	/usr/bin/osacompile -o "$TMP" "$SRC" 2>/dev/null || /usr/bin/osacompile -l JavaScript -o "$TMP" "$SRC"
	cat "$TMP"
	rm "$SRC" "$TMP"
fi
