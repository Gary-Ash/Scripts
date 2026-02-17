#!/usr/bin/env zsh
#*****************************************************************************************
# ci.sh
#
# This script will run iOS and/or macOS tests on GitHub check in
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  20-Feb-2026  5:21pm
# Modified :
#
# Copyright © 2026 By CompanyName All rights reserved.
#*****************************************************************************************

set -o pipefail

#*****************************************************************************************
# routine to extract a few project settings from the (main) project file
#*****************************************************************************************
getMainProjectSettings() {
	projectF=$(find . -name "$Scheme.xcodeproj")
	if [[ -n $projectF ]]; then
		projectF="$projectF/project.pbxproj"
		result=$(grep -m1 -i -e "SUPPORTED_PLATFORMS =" "$projectF")
		result=$(echo "$result" | grep -po '".*"')
		result=$(echo "$result" | sed 's/^\"\(.*\)\"$/\1/')
		echo "$result"
	else
		echo "Unable to get project settings"
		exit 1
	fi
}

#*****************************************************************************************
# routine to get the macOS build target and compare it against the macOS version of the
# Github action runner
#*****************************************************************************************
getMacVersion() {
	projectF=$(find . -name "$Scheme.xcodeproj")
	if [[ -n $projectF ]]; then
		projectF="$projectF/project.pbxproj"
		machineVersion="$(sw_vers -productVersion)"
		buildTarget=$(grep -m1 -i -e "MACOSX_DEPLOYMENT_TARGET =" "$projectF")
		buildTarget="${buildTarget#*=}"
		buildTarget="${buildTarget%;*}"
		buildTarget="${buildTarget#"${buildTarget%%[![:space:]]*}"}"

		if [[ $buildTarget < $machineVersion ]]; then
			echo "good"
		else
			echo "no good"
		fi
	fi
}

#*****************************************************************************************
# script main-line
#*****************************************************************************************
ProjectFile="$(find . -name '*.xcworkspace' -depth 1)" 2>/dev/null
if [[ -z $ProjectFile ]]; then
	ProjectFile="$(find . -name '*.xcodeproj' -depth 1)" 2>/dev/null
fi

Scheme="$(xcodebuild -list -json | jq -r '.project.schemes[0]')" 2>/dev/null
Simulator=$(xcrun xctrace list devices 2>&1 | grep -oE 'iPhone.*?[^\(]+' | head -1 | awk '{$1=$1;print}' | sed -e "s/ Simulator$//" 2>/dev/null)
Platforms=$(getMainProjectSettings)

if [[ $ProjectFile =~ .*\.xcworkspace$ ]]; then
	ProjectFlag="-workspace"
else
	ProjectFlag="-project"
fi

if [[ $Platforms =~ iphonesimulator ]]; then
	destination="platform=iOS Simulator,name=${Simulator}"
	xcodebuild build-for-testing -quiet "${ProjectFlag}" "${ProjectFile}" -scheme "${Scheme}" -destination "${destination}" | xcpretty -c
	xcodebuild test-without-building -quiet "${ProjectFlag}" "${ProjectFile}" -scheme "${Scheme}" -destination "${destination}" | xcpretty -c
fi

if [[ $Platforms =~ macosx ]]; then
	good=$(getMacVersion)
	if [[ $good == "good" ]]; then
		destination="platform=macOS"
		xcodebuild build-for-testing -quiet "${ProjectFlag}" "${ProjectFile}" -scheme "${Scheme}" -destination "${destination}" | xcpretty -c
		xcodebuild test-without-building -quiet "${ProjectFlag}" "${ProjectFile}" -scheme "${Scheme}" -destination "${destination}" | xcpretty -c
	fi
fi
