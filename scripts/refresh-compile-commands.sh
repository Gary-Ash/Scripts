#!/usr/bin/env bash
#*****************************************************************************************
# refresh-compile-commands.sh
#
# This script will refresh the language server protocol support file - compile_commands.json
# files of every Xcode project in my ~/Developer directory.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
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
