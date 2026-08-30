#!/usr/bin/env zsh
#*****************************************************************************************
# increment-build-number.sh
#
# This script increments macOS/iOS build number in the project Info.plist
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Sep-2026  4:42pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

if [[ ${CONFIGURATION} == "Release" || ${CONFIGURATION} == "TestFlight" ]]; then
	cd "${PROJECT_DIR}" || exit
	agvtool bump
fi
