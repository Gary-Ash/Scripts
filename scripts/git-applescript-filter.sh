#!/bin/bash

MODE="$1"
FILE="$2"

if [ "$MODE" = "--clean" ]; then
	# Convert compiled script → AppleScript source
	/usr/bin/osadecompile "$FILE"

elif [ "$MODE" = "--smudge" ]; then
	# Convert source → compiled script
	TMP=$(mktemp /tmp/git-ascr-XXXX.scpt)
	cat | /usr/bin/osacompile -o "$TMP"
	cat "$TMP"
	rm "$TMP"
fi
