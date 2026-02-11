#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# format-project.sh
#
# Run formatters on the source files in the project tree
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :  12-Feb-2026  4:00pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

if [ -z "$1" ]; then
	directory="."
else
	directory="$1"
fi

if command -v uncrustify &>/dev/null; then
	find -E "$directory" -type f -regex ".*\.(m|mm|pch)" -print0 | xargs -0 -S4096 uncrustify -l OC+ --replace --no-backup -c "$HOME/.config/.uncrustify" 2>/dev/null || true
	find -E "$directory" -type f -regex '.*\.(h|hh|hpp|hxx|c|cc|cpp|cxx|cs|jav|java)' -print0 | xargs -0 -S4096 uncrustify --replace --no-backup -c "$HOME/.config/.uncrustify" 2>/dev/null || true
fi

if command -v swiftformat &>/dev/null; then
	find "$directory" -type f -name "*.swift" -print0 | xargs -0 -S4096 swiftformat --config "$HOME/.config/.swiftformat" 2>/dev/null || true
fi

if command -v black &>/dev/null; then
	black --quiet --config "$HOME/.config/black" "$directory"
fi

if command -v shfmt &>/dev/null; then
	shfmt -s -ci -i 0 -w -ln bash "$directory" &>/dev/null || true
fi

if command -v perltidy &>/dev/null; then
	find -E "$directory" -type f -regex ".*\.(pl|pm)" -print0 | xargs -0 -S4096 perltidy -b -bext='/' --profile="$HOME/.config/.perltidyrc" 2>/dev/null || true
fi
