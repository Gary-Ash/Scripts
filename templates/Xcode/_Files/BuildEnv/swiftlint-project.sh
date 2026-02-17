#!/usr/bin/env zsh
#*****************************************************************************************
# swiftlint-project.sh
#
# This script will run SwiftLint over the current project
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  20-Feb-2026  5:21pm
# Modified :
#
# Copyright © 2026 By CompanyName All rights reserved.
#*****************************************************************************************

if [ -f "/opt/homebrew/bin/brew" ]; then
	export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
fi

if ! command -v swiftlint; then
	brew install swiftlint
fi

cd "${SRCROOT}"
swiftlint --fix --config "${PROJECT_DIR}/.swiftlint.yml" .
