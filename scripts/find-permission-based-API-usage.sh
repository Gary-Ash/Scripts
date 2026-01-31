#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# find-permission-based-API-usage.sh
#
# This script will scan swift sources in a project for usage of runtime and SDK functions
# that require permissions or excaptions
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************
searchTerms=(
	"creationDate"
	"modificationDate"
	"fileModificationDate"
	"contentModificationDateKey"
	"creationDateKey"
	"getattrlist"
	"getattrlistbulk"
	"fgetattrlist"
	"stat"
	"fstat"
	"fstatat"
	"lstat"
	"getattrlistat"
	"systemUptime"
	"mach_absolute_time"
	"volumeAvailableCapacityKey"
	"volumeAvailableCapacityForImportantUsageKey"
	"volumeAvailableCapacityForOpportunisticUsageKey"
	"volumeTotalCapacityKey"
	"systemFreeSize"
	"systemSize"
	"statfs"
	"statvfs"
	"fstatfs"
	"fstatvfs"
	"getattrlist"
	"fgetattrlist"
	"getattrlistat"
	"activeInputModes"
	"UserDefaults"
)
search_dir="$1"

if [ -z "$search_dir" ]; then
	echo "Usage: $0 <search_dir>"
	exit 1
fi

for pattern in "${searchTerms[@]}"; do
	find "$search_dir" -type f \( -name "*.swift" -o -name "*.m" \) -exec grep -H -Fw "$pattern\(" {} +
done
