#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# bbedit-restore-layout.sh
#
# Restore a saved BBEdit window and panel layout, scaling every captured coordinate
# from the original 2560x1440 capture display to the current main display's point space.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  28-May-2026  2:55pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

readonly DOMAIN="com.barebones.bbedit"

#*****************************************************************************************
# Locate the active preferences file. BBEdit is sandboxed, so its real preferences live
# in the app container; the loose ~/Library/Preferences copy belongs to an unsandboxed
# install. Target this file explicitly for both defaults and PlistBuddy so the two tools
# can never end up editing different copies.
#*****************************************************************************************
container_plist="${HOME}/Library/Containers/${DOMAIN}/Data/Library/Preferences/${DOMAIN}.plist"
loose_plist="${HOME}/Library/Preferences/${DOMAIN}.plist"

if [[ -f ${container_plist} ]]; then
	readonly PLIST="${container_plist}"
else
	readonly PLIST="${loose_plist}"
fi
readonly DEFAULTS_TARGET="${PLIST%.plist}"

# Source coordinates were captured on a 2560x1440 (point-space) display.
readonly BASE_WIDTH=2560
readonly BASE_HEIGHT=1440

#*****************************************************************************************
# Detect the current main display's point resolution.
#
# BBEdit stores window frames in points, not pixels, so a Retina display that reports
# 5120x2880 pixels must be read in its "looks like" point space (e.g. 2560x1440).
# Finder's desktop bounds report that point space directly as "0, 0, width, height".
#*****************************************************************************************
desktop_bounds=$(osascript -e 'tell application "Finder" to get bounds of window of desktop')
read -r _ _ current_width current_height <<<"${desktop_bounds//,/ }"

if [[ ! ${current_width} =~ ^[0-9]+$ || ! ${current_height} =~ ^[0-9]+$ ]]; then
	printf 'error: could not determine display resolution (got "%s")\n' "${desktop_bounds}" >&2
	exit 1
fi

readonly CURRENT_WIDTH="${current_width}"
readonly CURRENT_HEIGHT="${current_height}"
readonly DISPLAYS_KEY="displays([(0, 0), (${CURRENT_WIDTH}, ${CURRENT_HEIGHT})])"

#*****************************************************************************************
# scale <value> <numerator> <denominator>
#
# Scale an integer coordinate by numerator/denominator, rounded to the nearest integer.
#*****************************************************************************************
scale() {
	local value="$1" num="$2" den="$3"
	printf '%d' "$(((value * num + den / 2) / den))"
}

#*****************************************************************************************
# scale_frame <"x y w h sx sy sw sh">
#
# Scale an 8-field NSWindow frame string: horizontal fields by the width ratio and
# vertical fields by the height ratio. Emits the trailing space BBEdit writes.
#*****************************************************************************************
scale_frame() {
	local x y w h sx sy sw sh
	read -r x y w h sx sy sw sh <<<"$1"
	printf '%d %d %d %d %d %d %d %d ' \
		"$(scale "${x}" "${CURRENT_WIDTH}" "${BASE_WIDTH}")" \
		"$(scale "${y}" "${CURRENT_HEIGHT}" "${BASE_HEIGHT}")" \
		"$(scale "${w}" "${CURRENT_WIDTH}" "${BASE_WIDTH}")" \
		"$(scale "${h}" "${CURRENT_HEIGHT}" "${BASE_HEIGHT}")" \
		"$(scale "${sx}" "${CURRENT_WIDTH}" "${BASE_WIDTH}")" \
		"$(scale "${sy}" "${CURRENT_HEIGHT}" "${BASE_HEIGHT}")" \
		"$(scale "${sw}" "${CURRENT_WIDTH}" "${BASE_WIDTH}")" \
		"$(scale "${sh}" "${CURRENT_HEIGHT}" "${BASE_HEIGHT}")"
}

#*****************************************************************************************
# scale_rect <"rect(x1,y1,x2,y2)">
#
# Scale a BBEdit rect(): fields 1 and 3 by the width ratio, fields 2 and 4 by the height
# ratio. This holds whether the rect is (left,top,right,bottom) or (x,y,width,height).
#*****************************************************************************************
scale_rect() {
	local inner x1 y1 x2 y2
	inner="${1#rect(}"
	inner="${inner%)}"
	IFS=',' read -r x1 y1 x2 y2 <<<"${inner}"
	printf 'rect(%d,%d,%d,%d)' \
		"$(scale "${x1}" "${CURRENT_WIDTH}" "${BASE_WIDTH}")" \
		"$(scale "${y1}" "${CURRENT_HEIGHT}" "${BASE_HEIGHT}")" \
		"$(scale "${x2}" "${CURRENT_WIDTH}" "${BASE_WIDTH}")" \
		"$(scale "${y2}" "${CURRENT_HEIGHT}" "${BASE_HEIGHT}")"
}

#*****************************************************************************************
# write_default_properties <window-type> <split-proportion>
#
# Rebuild the per-display DefaultProperties dictionary for a window type. The Delete is
# allowed to fail on a first run when the dictionary does not yet exist.
#*****************************************************************************************
write_default_properties() {
	local window="$1" split="$2"
	local path=":DefaultProperties:${window}:${DISPLAYS_KEY}"

	# The entry path is wrapped in literal double quotes: PlistBuddy splits each -c
	# command on whitespace, and the displays([(0, 0), ...]) key contains spaces.
	/usr/libexec/PlistBuddy -c "Delete \"${path}\"" "${PLIST}" 2>/dev/null || true
	/usr/libexec/PlistBuddy \
		-c "Add \"${path}\" dict" \
		-c "Add \"${path}:FileListVisible\" bool true" \
		-c "Add \"${path}:IsFullScreen\" bool false" \
		-c "Add \"${path}:OpenDocumentSplitProportion\" real ${split}" \
		-c "Add \"${path}:ProjectListWidthAsFraction\" real 0.2" \
		-c "Add \"${path}:EmbeddedEditorVisible\" bool true" \
		"${PLIST}"
}

#*****************************************************************************************
# Quit BBEdit before touching its preferences. A running instance rewrites its window
# state when it quits, which would clobber everything written below. Clearing the
# cfprefsd cache afterward makes the on-disk plist authoritative for the edits to come.
#*****************************************************************************************
if pgrep -x BBEdit >/dev/null 2>&1; then
	osascript -e 'tell application "BBEdit" to quit' 2>/dev/null || true
	for _ in {1..40}; do
		pgrep -x BBEdit >/dev/null 2>&1 || break
		sleep 0.25
	done
	killall BBEdit 2>/dev/null || true
fi
killall cfprefsd 2>/dev/null || true

#*****************************************************************************************
# NSWindow frame settings (panels, palettes, dialogs)
#*****************************************************************************************
while IFS='|' read -r name frame; do
	[[ -z ${name} ]] && continue
	defaults write "${DEFAULTS_TARGET}" "NSWindow Frame ${name}" -string "$(scale_frame "${frame}")"
done <<'FRAMES'
GoToLine|1100 602 359 208 0 0 2560 1410
ApplyTextTransformPanel|1050 599 460 251 0 0 2560 1410
BBPreferences|978 611 685 611 0 0 2560 1410
ProgressPanelSheet|850 1156 407 137 0 0 2560 1415
WindowPosition_v2_FunctionsPalette|1155 487 285 358 0 0 2560 1415
StartupProgressPanel|1096 657 369 114 0 0 2560 1410
GoToSymbol|1136 633 288 246 0 0 2560 1415
AboutBoxNeue|1126 502 307 432 0 0 2560 1410
RunUnixCommandSheet|1010 630 540 234 0 0 2560 1410
SoftwareUpdateDownloadProgress|1067 938 426 171 0 0 2560 1410
OpenRecentPanel|1039 944 480 300 0 0 2560 1409
BBLanguageListPanel|1003 792 636 282 0 0 2560 1410
NSNavPanelAutosaveName|675 384 1210 911 0 0 2560 1409
BBSetupEditorWindow|1963 1017 350 388 0 0 2560 1415
ConfirmCloseMulti|997 771 565 397 0 0 2560 1410
StringEntryPanel|1000 669 559 155 0 0 2560 1410
ClippingLanguageSetupPanel|2028 966 220 387 0 0 2560 1415
ProgressPanel|850 1152 407 137 0 0 2560 1410
NSColorPanel|0 59 250 316 0 0 2560 1410
SoftwareUpdatePromptWindow|857 754 641 390 0 0 2560 1410
BBCustomizeLanguageSettings|1057 724 528 418 0 0 2560 1410
MultiFileReplaceAllOptions|315 472 388 128 0 0 2560 1415
WindowPosition_v2_Find|0 395 666 332 0 0 2560 1410
WindowPosition_v2_HTMLUtilitiesPalette|1851 923 139 208 0 0 2560 1415
OpenFileByName|1040 560 480 360 0 0 2560 1410
WindowPosition_v2_ScriptsPalette|1145 986 266 160 0 0 2560 1415
NSFontPanel|2024 113 536 235 0 0 2560 1409
WindowPosition_v2_MultiFileFind|379 290 626 563 0 0 2560 1410
UniversalRunner|1085 945 389 358 0 0 2560 1410
FRAMES

#*****************************************************************************************
# Browser window saved bounds
#*****************************************************************************************
while IFS='|' read -r key rect; do
	[[ -z ${key} ]] && continue
	defaults write "${DEFAULTS_TARGET}" "BrowserWindowSavedBounds:${key}" -string "$(scale_rect "${rect}")"
done <<'BOUNDS'
0B5E72D11BDE8AAACD6EAA0FC31DE1DA5D9766BD|rect(176,850,1251,1710)
93E09034E1717A5FA465B3F59DCE4BDE4599F5E3|rect(175,850,1250,1710)
080252C98401C0183DCF88EABC4D572384B5122B|rect(175,850,1250,1710)
AD3AC096DE86F9DE8F7EF9E125C99E8B7D3E6CDD|rect(175,850,1250,1710)
F52BEE158044D6A47806B155B06C90C04E924550|rect(176,850,1251,1710)
36D79EFEA03C0B9BAD995BAABBFCDBEE380AE64E|rect(175,850,1250,1710)
LSPDiagnosticsWindow|rect(176,850,1251,1710)
(null)|rect(175,850,1250,1710)
BOUNDS

#*****************************************************************************************
# Browser split positions (a percentage, not a coordinate -- left unscaled)
#*****************************************************************************************
for key in \
	080252C98401C0183DCF88EABC4D572384B5122B \
	F52BEE158044D6A47806B155B06C90C04E924550 \
	0B5E72D11BDE8AAACD6EAA0FC31DE1DA5D9766BD \
	93E09034E1717A5FA465B3F59DCE4BDE4599F5E3 \
	LSPDiagnosticsWindow \
	AD3AC096DE86F9DE8F7EF9E125C99E8B7D3E6CDD \
	36D79EFEA03C0B9BAD995BAABBFCDBEE380AE64E; do
	defaults write "${DEFAULTS_TARGET}" "BrowserWindowSavedSplitPosition:${key}" -int 33
done

#*****************************************************************************************
# Default window positions for the current display
#*****************************************************************************************
defaults write "${DEFAULTS_TARGET}" "WindowPosition:OpenFileByName:${DISPLAYS_KEY}" -string "$(scale_rect 'rect(548,1040,880,1520)')"
defaults write "${DEFAULTS_TARGET}" "DefaultPosition:ProjectWindow:${DISPLAYS_KEY}" -string "$(scale_rect 'rect(53,739,1369,1818)')"
defaults write "${DEFAULTS_TARGET}" "DefaultPosition:TextWindow:${DISPLAYS_KEY}" -string "$(scale_rect 'rect(62,742,1381,1817)')"

#*****************************************************************************************
# Window / UI behavior
#*****************************************************************************************
defaults write "${DEFAULTS_TARGET}" "Open Editing Windows" -bool false
defaults write "${DEFAULTS_TARGET}" EditingWindowPageGuideWidth -int 120 # column count, not a coordinate

#*****************************************************************************************
# Flush the defaults writes to disk before editing the plist directly. Otherwise
# cfprefsd's cached copy of the domain can overwrite the PlistBuddy additions below.
#*****************************************************************************************
killall cfprefsd 2>/dev/null || true

write_default_properties "TextWindow" "0.0"
write_default_properties "ProjectWindow" "0.61"

#*****************************************************************************************
# Invalidate the cfprefsd cache so the next BBEdit launch reads the new layout.
#*****************************************************************************************
killall cfprefsd 2>/dev/null || true
