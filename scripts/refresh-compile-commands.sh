#!/usr/bin/env zsh
#*****************************************************************************************
# refresh-compile-commands.sh
#
# This script will refresh the language server protocol support file - compile_commands.json
# files of every Xcode project in my ~/Developer directory.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  18-Aug-2023  8:10pm
# Modified :  14-Oct-2023  7:51pm
#
# Copyright © 2023 By Gee Dbl A All rights reserved.
#*****************************************************************************************
save="$PWD"
find "$HOME/Developer" -type f -name "compile_commands.json" -delete
raw=$(find "$HOME/Developer" -type d -name "*.xcodeproj" -not -path "$HOME/Developer/GeeDblA/ProjectTemplates/*.xcodeproj")

while read -r project_file; do
	cd "$(dirname "$project_file")" || exit 1
	xcodebuild -project "$project_file" 2>/dev/null | xcpretty -r json-compilation-database --output compile_commands.json &>/dev/null

	project_file="$(dirname "${project_file}")"
	rm -rf "${project_file}/build"
done < <(echo "${raw}")

cd "$save" || exit 1
