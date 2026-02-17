#!/usr/bin/env zsh
#*****************************************************************************************
# restore-stamped-icon.sh
#
#  This script will restore the copy of the app's original icon resources
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  20-Feb-2026  5:21pm
# Modified :
#
# Copyright © 2026 By CompanyName All rights reserved.
#*****************************************************************************************
if [[ ${CONFIGURATION} == "TestFlight" ]]; then
	appIconDir=$(find "${SRCROOT}/" -type d -name "AppIcon.appiconset" -print)
	tvOSappIconDir=$(find "${SRCROOT}" -type d -name "Brand Assets.brandassets" -print)

	if [[ -d "${TMPDIR}/${PROJECT_NAME}/AppIcon.appiconset" ]]; then
		rm -rf "${appIconDir}"
		cp -rf "${TMPDIR}/${PROJECT_NAME}/AppIcon.appiconset" "${appIconDir}"
	fi

	if [[ -d "${TMPDIR}/${PROJECT_NAME}/Brand Assets.brandassets" ]]; then
		rm -rf "${tvOSappIconDir}"
		cp -rf "${TMPDIR}/${PROJECT_NAME}/Brand Assets.brandassets" "${tvOSappIconDir}"
	fi

fi
