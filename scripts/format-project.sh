#!/usr/bin/env zsh
#*****************************************************************************************
# format-project.sh
#
# Run formaters  on the source files in the project tree
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  23-Jun-2025  9:40pm
# Modified :
#
# Copyright © 2024-2025 By Gary Ash All rights reserved.
#*****************************************************************************************
if [ -z "$@" ]; then
	directory="."
else
	directory="$@"
fi

if command -v uncrustify &>/dev/null; then
	find -E "$directory" -type f -regex ".*\.(m|mm|pch)" -print0 | xargs -0 uncrustify -l OC+ --replace --no-backup -c "$HOME/.config/.uncrustify"
	find -E "$directory" -type f -regex '.*\.(h|hh|hpp|hxx|c|cc|cpp|cxx|cs|jav|java)' -print0 | xargs -0 uncrustify --replace --no-backup -c "$HOME/.config/.uncrustify"
fi

if command -v swiftformat &>/dev/null; then
	find "$directory" -type f -name "*.swift" -print0 | xargs -0 swiftformat --config /Users/garyash/.config/.swiftformat
fi

if command -v black &>/dev/null; then
	black --quiet --config "$HOME/.config/black" "$directory"
fi

if command -v shfmt &>/dev/null; then
	shfmt -f -s -ci -i 0 -w -ln bash "$directory" &>/dev/null
fi

if command -v perltidy &>/dev/null; then
	find -E "$directory" -type f -regex ".*\.(pl|pm)" -print0 | xargs -0 perltidy -b -bext='/' --profile="$HOME/.config/.perltidyrc"
fi
