#!/usr/bin/env zsh
#*****************************************************************************************
# increment-build-number.sh
#
# This script increments macOS/iOS build number in the project Info.plist
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  20-Feb-2026  5:21pm
# Modified :
#
# Copyright © 2026 By CompanyName All rights reserved.
#*****************************************************************************************

if [[ ${CONFIGURATION} == "Release" || ${CONFIGURATION} == "TestFlight" ]]; then
	cd "${PROJECT_DIR}" || exit
	agvtool bump
fi
