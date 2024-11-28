#!/usr/bin/env zsh
#*****************************************************************************************
# find-permission-based-API-usage.sh
#
# This script will scan swift sources in a project for usage of runtime and SDK functions
# that require permissions or excaptions
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  20-Dec-2024  9:55pm
# Modified :
#
# Copyright © 2024 By Gary Ash All rights reserved.
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
