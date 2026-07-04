#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# git-applescript-filter.sh
#
# This is a git filter will store compiled AppleScript and JavaScript for Automation
# (JXA) scripts as source text
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  15-Mar-2026  3:39pm
# Modified :  03-Jul-2026  7:46pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

MODE="$1"

if [ "$MODE" = "clean" ]; then
	BASE=$(mktemp /tmp/git-ascr-XXXXXXXX)
	TMP="$BASE.scpt"
	trap 'rm -f "$BASE" "$TMP"' EXIT
	cat >"$TMP"

	# osadecompile determines the language (AppleScript or JavaScript) from the
	# compiled script itself, so a single invocation handles both. If the input is
	# not a compiled script (it is already source text, e.g. a file the smudge
	# filter passed through because it could not be compiled) emit it unchanged so
	# the filter stays idempotent and git operations do not abort.
	if ! /usr/bin/osadecompile "$TMP" 2>/dev/null; then
		cat "$TMP"
	fi

elif [ "$MODE" = "smudge" ]; then
	SRCBASE=$(mktemp /tmp/git-ascr-XXXXXXXX)
	TMPBASE=$(mktemp /tmp/git-ascr-XXXXXXXX)
	SRC="$SRCBASE.txt"
	TMP="$TMPBASE.scpt"
	trap 'rm -f "$SRCBASE" "$TMPBASE" "$SRC" "$TMP"' EXIT
	cat >"$SRC"

	# Plain text compiles as AppleScript by default; fall back to JavaScript for
	# Automation (JXA) sources that fail to compile as AppleScript. If neither
	# compiles (e.g. a script library dependency is not installed on this machine)
	# emit the source text unchanged so the checkout succeeds instead of aborting
	# the whole clone. The compiled binary can be regenerated once the source is
	# valid in context.
	if /usr/bin/osacompile -o "$TMP" "$SRC" 2>/dev/null ||
		/usr/bin/osacompile -l JavaScript -o "$TMP" "$SRC" 2>/dev/null; then
		cat "$TMP"
	else
		cat "$SRC"
	fi
fi
