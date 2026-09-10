#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# update-dots.sh
#
# This script automates the maintenance of my dot files repository
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Sep-2026  4:42pm
# Modified :   5-Sep-2026  7:05pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# source in library functions
#*****************************************************************************************
source "/opt/geedbla/lib/shell/lib/claude-scrub.sh"

#*****************************************************************************************
# global variables
#*****************************************************************************************
readonly PREFERENCE_FILES=(
	"com.apple.dt.Xcode.plist"
	"com.apple.applescript.plist"
	"com.apple.Terminal.plist"
)

readonly DOTFILES_DIR="$HOME/Downloads/dotfiles"

#*****************************************************************************************
# this subroutine will process the "." files in a configuration files
#*****************************************************************************************
dot-files() {
	local rawdotfiles
	local line
	local dotfiles=()

	local -r ignore_these=(
		"${CLAUDE_JUNK_PATHS[@]/#/$HOME/}"
		"$HOME/.config/z"
		"$HOME/.config/zsh/.zsh_history"
		"$HOME/.config/zsh/.zsh_sessions"
		"$HOME/.config/zsh/zcompdump*"
		"$HOME/.config/github-copilot"
		"$HOME/.config/thefuck/__pycache__"
		"$HOME/.config/iterm2"
		"$HOME/.config/.swiftpm/"
		"$HOME/.config/swiftpm/"
		"$HOME/.dropbox"
		"$HOME/.hawtjni"
		"$HOME/.gem"
		"$HOME/.npm"
		"$HOME/.android"
		"$HOME/.bundle"
		"$HOME/.bash_history"
		"$HOME/.cocoapods"
		"$HOME/.CFUserTextEncoding"
		"$HOME/.cups"
		"$HOME/.cache"
		"$HOME/.DS_Store"
		"$HOME/.Trash"
		"$HOME/.konan"
		"$HOME/.local"
		"$HOME/.swiftpm"
		"$HOME/.gradle"
		"$HOME/.proxyman"
		"$HOME/.proxyman-data"
		"$HOME/.ssh/id_ed25519"
		"$HOME/.ssh/id_ed25519.pub"
		"$HOME/.ssh/known_hosts"
		"$HOME/.ssh/agent"
		"$HOME/.config/git/allowed_signers"
	)

	rawdotfiles=$(find "$HOME" -maxdepth 1 -name ".*")
	while IFS= read -r line; do
		dotfiles+=("$line")
	done < <(echo "$rawdotfiles")

	for exclude in "${ignore_these[@]}"; do
		for i in "${!dotfiles[@]}"; do
			if [[ ${dotfiles[$i]} == "$exclude" ]]; then
				unset "dotfiles[$i]"
				break
			fi
		done
	done

	if [[ -z ${2:-} ]]; then
		printf '%s\n' "${dotfiles[@]}"
		return
	fi

	# ".DS_Store" is deliberately left unanchored so it matches at every level, the
	# rest are anchored to their real location under $HOME so that a common basename
	# such as "cache" or "data" cannot knock out an unrelated directory deeper down
	local rsync_args=(-acz --exclude=.DS_Store)
	for exclude in "${ignore_these[@]}"; do
		exclude="${exclude%/}"
		rsync_args+=("--exclude=/${exclude#"$HOME"/}")
	done

	for dotfile in "${dotfiles[@]}"; do
		if [[ -n ${dotfile:-} ]]; then
			rsync "${rsync_args[@]}" "$dotfile" "$1" || true
		fi
	done

	mkdir -p "$DOTFILES_DIR/home/.config/zsh"
	touch "$DOTFILES_DIR/home/.config/zsh/.gitkeep"
}

#****************************************************************************************
# write stdin to a manifest, but only when the generator that produced it actually
# emitted something - a failed run then leaves the previous manifest in place
#****************************************************************************************
writeManifest() {
	local -r name="$1"
	local content
	content="$(cat)"

	if [[ -n $content ]]; then
		printf '%s\n' "$content" >"$name"
	else
		echo "Unable to regenerate $name, keeping the existing one" >&2
	fi
}

#****************************************************************************************
# build GitHub repository package
#****************************************************************************************
buildRepository() {
	local -r directories=(
		"$DOTFILES_DIR/home"
		"$DOTFILES_DIR/xcode"
		"$DOTFILES_DIR/brew"
		"$DOTFILES_DIR/preferences"
		"$DOTFILES_DIR/shortcuts"
	)

	for direct in "${directories[@]}"; do
		mkdir -p "$direct"
	done

	dot-files "$DOTFILES_DIR/home" "*"

	rsync -arcz -E --exclude="UserData/IB Support" \
		--exclude="UserData/Capabilities" \
		--exclude="UserData/Portal" \
		--exclude="UserData/Previews" \
		--exclude="UserData/XcodeCloud" \
		--exclude="UserData/CodingAssistant" \
		--exclude="/CodingAssistant" \
		--exclude="UserData/Provisioning Profiles" \
		--exclude="UserData/IDEEditorInteractivityHistory" \
		--exclude="UserData/IDEFindNavigatorScopes.plist" \
		--exclude="/Products" \
		--exclude="/XCPGDevices" \
		--exclude="/XCTestDevices" \
		--exclude="/* DeviceSupport" \
		--exclude="/* Device Logs" \
		--exclude="/DeviceLogs" \
		--exclude="/DerivedData" \
		--exclude="/DocumentationIndex" \
		--exclude="/DocumentationCache" \
		--exclude="/SDKToSimulatorIndexMapping.plist" \
		--exclude="/XcodeToMetalToolchainIndexMapping.plist" \
		--exclude="/.derived-data-log*" \
		"$HOME/Library/Developer/Xcode/" "$DOTFILES_DIR/xcode/" &>/dev/null || true

	rsync -arcz -E --rsh=ssh \
		--delete \
		"$HOME/Library/Script Libraries" \
		"$DOTFILES_DIR/" &>/dev/null || true

	rsync -arcz -E --rsh=ssh \
		--exclude="BBEdit User Manual *.pdf" \
		--exclude="Scripts/Diff Unsaved Changes in Kaleidoscope.sh" \
		--delete \
		"$HOME/Library/Application Support/BBEdit" \
		"$DOTFILES_DIR/" &>/dev/null || true

	for preference_file in "${PREFERENCE_FILES[@]}"; do
		rsync -arz -E "$HOME/Library/Preferences/$preference_file" "$DOTFILES_DIR/preferences" &>/dev/null || true
	done

	local package_temp="$HOME/Downloads/package-temp"
	mkdir -p "$package_temp"
	pushd "$package_temp" >/dev/null || return

	if ! brew bundle dump --force --no-npm &>/dev/null; then
		echo "Unable to regenerate the Brewfile, keeping the existing one" >&2
		rm -f Brewfile
	fi

	{ gem list --no-version || true; } | writeManifest gems.txt

	{ pip3 list --format freeze || true; } | while IFS= read -r p; do
		echo "${p%%=*}"
	done | writeManifest python-packages.txt

	# npm globals live in their own manifest rather than in the Brewfile, so the
	# dump above is told to skip them. npm itself is never listed.
	{
		npm ls -g --depth=0 --json 2>/dev/null |
			jq -r '.dependencies | keys[]' 2>/dev/null |
			grep -vx "npm" || true
	} | writeManifest npm-packages.txt

	popd >/dev/null || return

	find "$DOTFILES_DIR" -type f -name "*.zwc" -delete

	local files=()
	while IFS= read -r f; do
		files+=("$f")
	done < <(find "$package_temp" -type f)

	for file in "${files[@]}"; do
		local name
		name=$(basename "$file")
		local dest="$DOTFILES_DIR/brew/$name"

		if [[ -f $dest ]]; then
			if ! diff -w "$dest" "$file" &>/dev/null; then
				mv -f "$file" "$dest"
			fi
		else
			mv -f "$file" "$dest"
		fi
	done

	# an unscrubbed .claude.json names the machine and the account, so if the
	# scrub cannot be completed the file is dropped rather than published as is
	if jq "$(claude_scrub_filter identity)" \
		"$DOTFILES_DIR/home/.claude.json" >"$DOTFILES_DIR/home/.claude.json1"; then
		rm -f "$DOTFILES_DIR/home/".claude.json.backup.*
		rm -f "$DOTFILES_DIR/home/.claude.json"
		mv "$DOTFILES_DIR/home/.claude.json1" "$DOTFILES_DIR/home/.claude.json"
	else
		echo "Unable to scrub .claude.json, leaving it out of the repository" >&2
		rm -f "$DOTFILES_DIR/home/.claude.json1" "$DOTFILES_DIR/home/.claude.json"
	fi

	cp -f /opt/geedbla/scripts/bootstrap.sh "$DOTFILES_DIR"
	rm -rf "$package_temp"
	generate-gitkeep.sh "$DOTFILES_DIR"
}

#****************************************************************************************
# this function will update my dot files repository on GitHub
#****************************************************************************************
updateGitHub() {
	# clone into a staging directory first — the existing repository is only
	# removed once there is a complete replacement ready to take its place
	local -r staging="$DOTFILES_DIR.staging"

	rm -rf "$staging"

	if ! git clone --quiet --recurse-submodules git@github.com:Gary-Ash/dotfiles.git "$staging"; then
		echo "Unable to clone the repository, the existing one is untouched" >&2
		rm -rf "$staging"
		return 1
	fi

	if ! (cd "$staging" && git submodule update --recursive --remote); then
		echo "Unable to update submodules, the existing repository is untouched" >&2
		rm -rf "$staging"
		return 1
	fi

	rm -rf "$DOTFILES_DIR"
	mv "$staging" "$DOTFILES_DIR"

	find "$DOTFILES_DIR" -type f -name ".gitkeep" -delete
	buildRepository
}

cleanSettingsFiles() {
	python3 <<'PYTHON'
#*****************************************************************************************
# libraries used
#*****************************************************************************************
import os
import plistlib
import re

HOME = os.environ["HOME"]

PLIST_KEYS_TO_DELETE = [
    "ChatAPIIdentifier",
    "ChatGPTModel",
    "ClaudeModel",
    "NSWindow Frame ChatGPTKeyEntryPanel",
    "ListSignupEmailAddress",
    "ListSignupUserName",
    "NewBookmarksLocationUUID",
    "RecentSearchStrings",
    "FXRecentFolders",
    "GoToField",
    "RecentApplications",
    "RecentDocuments",
    "RecentServers",
    "Hosts",
    "ExpandedURLs",
    "last_textureFileName",
    "FXRecentFolders",
    "FXLastSearchScope",
    "GoToField",
    "NSNavPanel",
    "NSNavRecentPlaces",
    "NSNavLastRootDirectory",
    "NSNavLastCurrentDirectory",
    "RecentSearchStrings",
    "LRUDocumentPaths",
    "TSAOpenedTemplates.Pages",
    "NSReplacePboard",
    "ExpandedURLs",
    "SelectedURLs",
    "NSReplacePboard",
    "Apple CFPasteboard find",
    "Apple CFPasteboard replace",
    "Apple CFPasteboard general",
    "findHistory",
    "replaceHistory",
    "MGRecentURLPropertyLists",
    "OakFindPanelOptions",
    "Folder Search Options",
    "recentFileList",
    "RecentDirectories",
    "NSRecentXCProjectDocuments",
    "last_dataFileName",
    "lastSpritesFolder",
    "main.lastFileName",
    "defaults.settingsAbsPath",
    "main.lastFileName",
    "DefaultCheckOutDirectory",
    "RecentWorkingCopies",
    "kProjectBasePath",
    "LastOpenedScene",
    "ABBookWindowController-MainBookWindow-personListController",
    "IDEFileTemplateChooserAssistantSelectedTemplateCategory",
    "IDEFileTemplateChooserAssistantSelectedTemplateName",
    "IDERecentEditorDocuments",
    "XCOpenWorkspaceDocuments",
    "IDETemplateCompletionDefaultPath",
    "IDETemplateOptions",
    "IDEDistributionPlanSelection",
    "IDEDefaultPrimaryEditorFrameSizeForPaths",
    "IDEDocViewerLastViewedURLKey",
    "IDESourceControlRecentsFavoritesRepositoriesUserDefaultsKey",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateCategory",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateCategory",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateSection",
    "recentFileList",
    "lastSpritesFolder",
    "main.lastFileName",
    "last_name",
    "last_textureFileName",
    "findRecentPlaces",
    "RecentWebSearches",
    "recentSearches",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_macOS",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_iOS",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_tvOS",
    "SGTRecentFileSearches",
    "IDEFileTemplateChooserAssistantSelectedTemplateSection",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_tvOS",
    "IDEFileTemplateChooserAssistantSelectedTemplateName_tvOS",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateSection3ProjectTemplateChooserAssistantSelectedTemplateName_macOS",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_iOS",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_Multiplatform",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_macOS",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_Multiplatform",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateSection",
    "DVTTextCompletionRecentCompletions",
    "GoToFieldHistory",
    "HistoryColors",
    "recentSearches",
    "recentSearchHints",
    "IDETemplateCompletionDefaultPath",
    "SHKRecentServices",
    "FavoriteColors",
    "LastSetWindowSizeForDocument",
    "recentCatalogPaths",
    "IDELastBreakpointActionClassName",
    "RecentFindStrings",
    "IDEFileTemplateChooserAssistantSelectedTemplateName_iOS",
    "RecentReplaceStrings",
    "IDESwiftMigrationAssistantReviewFilesSelectedChoice",
    "IDERunActionSelectedTab",
    "DVTIgnoredDevices",
    "IBGlobalLastEditorDocumentClassName",
    "IBDocumentOutlineViewMode",
    "IDELibrary.lastSelectedLibraryExtensionIDByEditorID",
    "IBGlobalLastEditorTargetRuntime",
    "CurrentAlertPreferencesSelection",
    "DVTRecentCustomColors",
    "IDEProvisioningTeamManagerLastSelectedTeamID",
    "BKRecentsLastCleared",
    "BKPreviouslyOpenedBookIDs",
    "RecentMoveAndCopyDestinations",
    "DownloadsFolderListViewSettingsVersion",
    "recent_viewed",
    "RecentsArrangeGroupViewBy",
    "IDEAppChooserRecentApplications-My Mac",
    "RecentRegions",
    "IDEFileTemplateChooserAssistantSelectedTemplateName_macOS",
    "lastSource",
    "lastReplacement",
    "lastRegex",
    "TSARecentOpenedDocumentTimestamps",
    "TSAOpenedTemplates.Numbers",
    "TSAOpenedTemplates.Pages",
    "FindDialog_SearchReplaceHistory",
    "ApplicationSleepState",
    "ApplicationAutoSaveState",
    "CurrentWorkspaceDocumentName",
    "FindDialog_SelectedSourceNodes",
    "NSOSPLastRootDirectory",
    "RecentItemsData",
    "PropertyWindowsToReopen",
    "LastPersistenceCleanupDateKey",
    "XCCArchiveReminderPromptDate",
    "OpenDocuments",
    "IDEAppStatisticsXcodeVersionMetricsHistoryStorage",
    "IDE_CA_Daily_LastReport",
    "IDE_CA_Daily_UptimeHours",
    "IDE_CA_Daily_SessionCount",
    "PreferencesSnapshotDate",
    "ApplicationAutoSaveState",
    "LastOpenByNameString",
    "IDEChatUserSelectedDefaultChatModelDefinitionIdentifier",
    "IDEAnalyticsMetricsNotifications.AnalyticsMetricsNotificationsController.lastRefreshAttemptDate",
    "BBEditSerialNumber:15.0",
    "IDELastViewedSettingsPane",
    "SULastCheckedDate",
    "LastLaunchOSVersion",
    "LastTerminalStartTime",
    "IDEMostRecentPostFLEDate",
    "DVTDeveloperAccountManagerAppleIDLists",
    "DVTDevicesWindowControllerSelectedDeviceIdentifier",
    "DVTDevicesWindowControllerSelectedSimulatorIdentifier",
    "IDEAppStoreProductSourceRateLimiter",
    "DVTDeviceVisibilityPreferences",
    "DVTSourceControlAccountDefaultsKey",
    "IDEProvisioningTeamByIdentifier",
    "IDESourceControlHostAccounts_10",
    "IDEProductsViewControllerSelectedProductIdentifier",
]

#*****************************************************************************************
# keys whose names are generated rather than fixed, matched by shape
#*****************************************************************************************
GENERATED_KEY_PREFIXES = (
    "InstaprojectWindowSavedBounds",
    "ImageDisplayGrayLevel_",
    "IDEXcodeDeviceSupportLastNotified-",
)

DIGEST_KEY = re.compile(r"^~[0-9A-Fa-f]{40}$")

#*****************************************************************************************
# private project bundle id pattern - any plist entry whose value tree references
# this pattern is stripped to prevent leaking private project identifiers
#*****************************************************************************************
PRIVATE_BUNDLE_ID = re.compile(r"com\.garyash\.")


#*****************************************************************************************
# does this value, anywhere in its tree, name a private project?
#
# the original asked Foundation for the value's description and matched against that, so
# nested dictionary keys count as well as the values, while data blobs -- which describe
# as hex -- never do
#*****************************************************************************************
def referencesPrivateBundleID(value):
    if isinstance(value, str):
        return bool(PRIVATE_BUNDLE_ID.search(value))
    if isinstance(value, dict):
        return any(
            referencesPrivateBundleID(key) or referencesPrivateBundleID(item)
            for key, item in value.items()
        )
    if isinstance(value, (list, tuple)):
        return any(referencesPrivateBundleID(item) for item in value)
    return False


def stripPrivateBundleIDs(dictionary):
    for key in [k for k, v in dictionary.items() if referencesPrivateBundleID(v)]:
        del dictionary[key]


#*****************************************************************************************
# process one plist
#*****************************************************************************************
def processFile(path):
    try:
        with open(path, "rb") as handle:
            plistData = plistlib.load(handle)
    except (OSError, ValueError, plistlib.InvalidFileException):
        return

    # anything whose root is not a dictionary is left exactly as it was found
    if not isinstance(plistData, dict):
        return

    for key in PLIST_KEYS_TO_DELETE:
        plistData.pop(key, None)

    valuesDict = plistData.get("values")
    if isinstance(valuesDict, dict):
        valuesDict = dict(valuesDict)
        for key in PLIST_KEYS_TO_DELETE:
            valuesDict.pop(key, None)
        stripPrivateBundleIDs(valuesDict)
        plistData["values"] = valuesDict

    stripPrivateBundleIDs(plistData)

    for key in list(plistData):
        if key.startswith(GENERATED_KEY_PREFIXES) or DIGEST_KEY.match(key):
            del plistData[key]

    os.unlink(path)
    with open(path, "wb") as handle:
        plistlib.dump(plistData, handle, fmt=plistlib.FMT_XML)


#*****************************************************************************************
# process the plists in the dotfiles folder
#*****************************************************************************************
def plists():
    for root, _directories, files in os.walk(f"{HOME}/Downloads/dotfiles"):
        for name in files:
            if name.endswith(".plist"):
                processFile(os.path.join(root, name))


#*****************************************************************************************
# script main line
#*****************************************************************************************
plists()
PYTHON
}

#*****************************************************************************************
# script main line
#*****************************************************************************************

format-project.sh "/opt/geedbla" || true

if [[ $# -gt 0 ]]; then
	case $1 in
		-h | --help)
			cat <<-EOF
				=================================================
				 Update dot file repro on GitHub
				=================================================
				   update-dots.sh --help for this help message
				   update-dots.sh --package build the GitHub update without committing it
			EOF
			exit 0
			;;

		-p | --package)
			buildRepository
			;;

		-*)
			echo "Unknown option -- $1" >&2
			exit 1
			;;

		*)
			updateGitHub
			;;
	esac
else
	updateGitHub
fi
cleanSettingsFiles
