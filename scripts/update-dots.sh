#!/usr/bin/env bash
#*****************************************************************************************
# update-dots.sh
#
# This script automates the maintenance of my dot files repository
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :  28-Feb-2026  3:11pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

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
	local basecmd
	local rawdotfiles
	local line
	local dotfiles=()

	local -r ignore_these=(
		"$HOME/.claude/backups"
		"$HOME/.claude/cache"
		"$HOME/.claude/session-env"
		"$HOME/.claude/plans"
		"$HOME/.claude/projects"
		"$HOME/.claude/tasks"
		"$HOME/.claude/todos"
		"$HOME/.claude/debug"
		"$HOME/.claude/statsig"
		"$HOME/.claude/downloads"
		"$HOME/.claude/shell-snapshots"
		"$HOME/.claude/file-history"
		"$HOME/.claude/history.jsonl"
		"$HOME/.claude/stats-cache.json"
		"$HOME/.config/z"
		"$HOME/.config/zsh/.zsh_history"
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

	basecmd="rsync -acz "
	for exclude in "${ignore_these[@]}"; do
		basecmd+="--exclude=$(basename "$exclude") "
	done

	for dotfile in "${dotfiles[@]}"; do
		if [[ -n ${dotfile:-} ]]; then
			eval "$basecmd\"$dotfile\" \"$1\""
		fi
	done

	mkdir -p "$DOTFILES_DIR/home/.config/zsh"
	touch "$DOTFILES_DIR/home/.config/zsh/.gitkeep"
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
		"$HOME/Library/Developer/Xcode/" "$DOTFILES_DIR/xcode/" &>/dev/null

	rsync -arcz -E --rsh=ssh \
		--exclude="BBEdit User Manual *.pdf" \
		--exclude="'Scripts/Diff Unsaved Changes in Kaleidoscope.sh'" \
		--delete \
		"$HOME/Library/Application Support/BBEdit" \
		"$DOTFILES_DIR/" &>/dev/null

	for preference_file in "${PREFERENCE_FILES[@]}"; do
		rsync -arz -E "$HOME/Library/Preferences/$preference_file" "$DOTFILES_DIR/preferences" &>/dev/null
	done

	local package_temp="$HOME/Downloads/package-temp"
	mkdir -p "$package_temp"
	pushd "$package_temp" >/dev/null || return

	brew bundle dump --force &>/dev/null
	gem list --no-version >gems.txt

	pip3 list --format freeze | while IFS= read -r p; do
		echo "${p%%=*}"
	done >python-packages.txt

	popd >/dev/null || return

	find "$DOTFILES_DIR" -type f -name "*.zwc" -delete

	local files
	mapfile -t files < <(find "$package_temp" -type f)

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

	jq 'del(.userID, .oauthAccount, .projects, .githubRepoPaths,
			.firstStartTime, .claudeCodeFirstTokenDate,
			.opusProMigrationTimestamp, .changelogLastFetched) |
		.hasShownOpus45Notice = {} |
		.s1mAccessCache = {} |
		.groveConfigCache = {} |
		.skillUsage = {}' "$DOTFILES_DIR/home/.claude.json" >"$DOTFILES_DIR/home/.claude.json1"

	rm -f "$DOTFILES_DIR/home/".claude.json.backup.*

	rm -f "$DOTFILES_DIR/home/.claude.json"
	mv "$DOTFILES_DIR/home/.claude.json1" "$DOTFILES_DIR/home/.claude.json"
	cp -f /opt/geedbla/scripts/bootstrap.sh "$DOTFILES_DIR"
	rm -rf "$package_temp"
	find "$DOTFILES_DIR" -type d -empty -not -path "*/.git/*" -exec touch {}/.gitkeep \;
}

#****************************************************************************************
# this function will update my dot files repository on GitHub
#****************************************************************************************
updateGitHub() {
	if [[ -d $DOTFILES_DIR ]]; then
		rm -rf "$DOTFILES_DIR"
	fi

	if git clone --quiet --recurse-submodules git@github.com:Gary-Ash/dotfiles.git "$DOTFILES_DIR"; then
		pushd "$DOTFILES_DIR" >/dev/null || return 1
		git submodule update --recursive --remote
		popd >/dev/null || return 1

		buildRepository
	else
		echo "Unable to update the repository" >&2
		return 1
	fi
}

cleanSettingsFiles() {
	perl <<'PERL'
#!/usr/bin/env perl
#*****************************************************************************************
# libraries used
#*****************************************************************************************
use strict;
use warnings;
use Foundation;
use File::Find;

our $HOME = $ENV{'HOME'};

our @plistKeysToDelete = (
    "NewBookmarksLocationUUID",                                       "RecentSearchStrings",                                            "FXRecentFolders",                                                                                                       "GoToField",                                                     "RecentApplications",                                           "RecentDocuments",
    "RecentServers",                                                  "Hosts",                                                          "ExpandedURLs",                                                                                                          "last_textureFileName",                                          "FXRecentFolders",                                              "FXLastSearchScope",
    "GoToField",                                                      "NSNavPanel",                                                     "NSNavRecentPlaces",                                                                                                     "NSNavLastRootDirectory",                                        "NSNavLastCurrentDirectory",                                    "RecentSearchStrings",
    "LRUDocumentPaths",                                               "TSAOpenedTemplates.Pages",                                       "NSReplacePboard",                                                                                                       "ExpandedURLs",                                                  "SelectedURLs",                                                 "NSReplacePboard",
    "Apple CFPasteboard find",                                        "Apple CFPasteboard replace",                                     "Apple CFPasteboard general",                                                                                            "findHistory",                                                   "replaceHistory",                                               "MGRecentURLPropertyLists",
    "OakFindPanelOptions",                                            "Folder Search Options",                                          "recentFileList",                                                                                                        "RecentDirectories",                                             "NSRecentXCProjectDocuments",                                   "last_dataFileName",
    "lastSpritesFolder",                                              "main.lastFileName",                                              "defaults.settingsAbsPath",                                                                                              "main.lastFileName",                                             "DefaultCheckOutDirectory",                                     "RecentWorkingCopies",
    "kProjectBasePath",                                               "LastOpenedScene",                                                "ABBookWindowController-MainBookWindow-personListController",                                                            "IDEFileTemplateChooserAssistantSelectedTemplateCategory",       "IDEFileTemplateChooserAssistantSelectedTemplateName",          "IDERecentEditorDocuments",
    "XCOpenWorkspaceDocuments",                                       "IDETemplateCompletionDefaultPath",                               "IDETemplateOptions",                                                                                                    "IDEDefaultPrimaryEditorFrameSizeForPaths",                      "IDEDocViewerLastViewedURLKey",                                 "IDESourceControlRecentsFavoritesRepositoriesUserDefaultsKey",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateCategory",  "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName",      "Xcode3TargetTemplateChooserAssistantSelectedTemplateCategory",                                                          "Xcode3TargetTemplateChooserAssistantSelectedTemplateName",      "Xcode3ProjectTemplateChooserAssistantSelectedTemplateSection", "recentFileList",
    "lastSpritesFolder",                                              "main.lastFileName",                                              "last_name",                                                                                                             "last_textureFileName",                                          "findRecentPlaces",                                             "RecentWebSearches",
    "recentSearches",                                                 "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_macOS", "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_iOS",                                                          "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_tvOS", "SGTRecentFileSearches",                                        "IDEFileTemplateChooserAssistantSelectedTemplateSection",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_tvOS", "IDEFileTemplateChooserAssistantSelectedTemplateName_tvOS",       "Xcode3TargetTemplateChooserAssistantSelectedTemplateSection3ProjectTemplateChooserAssistantSelectedTemplateName_macOS", "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_iOS", "Xcode3TargetTemplateChooserAssistantSelectedTemplateSection",  "DVTTextCompletionRecentCompletions",
    "GoToFieldHistory",                                               "HistoryColors",                                                  "recentSearches",                                                                                                        "recentSearchHints",                                             "IDETemplateCompletionDefaultPath",                             "SHKRecentServices",
    "FavoriteColors",                                                 "LastSetWindowSizeForDocument",                                   "recentCatalogPaths",                                                                                                    "IDELastBreakpointActionClassName",                              "RecentFindStrings",                                            "IDEFileTemplateChooserAssistantSelectedTemplateName_iOS",
    "RecentReplaceStrings",                                           "IDESwiftMigrationAssistantReviewFilesSelectedChoice",            "IDERunActionSelectedTab",                                                                                               "DVTIgnoredDevices",                                             "IBGlobalLastEditorDocumentClassName",                          "IBDocumentOutlineViewMode",
    "IDELibrary.lastSelectedLibraryExtensionIDByEditorID",            "IBGlobalLastEditorTargetRuntime",                                "CurrentAlertPreferencesSelection",                                                                                      "DVTRecentCustomColors",                                         "IDEProvisioningTeamManagerLastSelectedTeamID",                 "BKRecentsLastCleared",
    "BKPreviouslyOpenedBookIDs",                                      "RecentMoveAndCopyDestinations",                                  "DownloadsFolderListViewSettingsVersion",                                                                                "recent_viewed",                                                 "RecentsArrangeGroupViewBy",                                    "IDEAppChooserRecentApplications-My Mac",
    "RecentRegions",                                                  "IDEFileTemplateChooserAssistantSelectedTemplateName_macOS",      "lastSource",                                                                                                            "lastReplacement",                                               "lastRegex",                                                    "TSARecentOpenedDocumentTimestamps",
    "TSAOpenedTemplates.Numbers",                                     "TSAOpenedTemplates.Pages",                                       "FindDialog_SearchReplaceHistory",                                                                                       "ApplicationSleepState",                                         "ApplicationAutoSaveState",                                     "CurrentWorkspaceDocumentName",
    "FindDialog_SelectedSourceNodes",                                 "NSOSPLastRootDirectory",                                         "RecentItemsData",                                                                                                       "PropertyWindowsToReopen",                                       "LastPersistenceCleanupDateKey",                                "XCCArchiveReminderPromptDate",
    "OpenDocuments",                                                  "IDEAppStatisticsXcodeVersionMetricsHistoryStorage",              "IDE_CA_Daily_LastReport",                                                                                               "IDE_CA_Daily_UptimeHours",                                      "IDE_CA_Daily_SessionCount",                                    "PreferencesSnapshotDate",
    "ApplicationAutoSaveState",                                       "LastOpenByNameString",                                           "IDEChatUserSelectedDefaultChatModelDefinitionIdentifier",                                                               "IDEAnalyticsMetricsNotifications.AnalyticsMetricsNotificationsController.lastRefreshAttemptDate",		                          "BBEditSerialNumber:15.0",
);

#*****************************************************************************************
# process the plists in the Containers folder
#*****************************************************************************************
sub processFiles {
    if ($File::Find::name =~ /\.plist$/) {
        eval {
            my $plistData = NSMutableDictionary->dictionaryWithContentsOfFile_($File::Find::name);
            foreach my $key (@plistKeysToDelete) {
                $plistData->removeObjectForKey_($key);
            }

            my $valuesDic = $plistData->objectForKey_("values");
            if ($valuesDic && $$valuesDic) {
                my $valuesDicM = $valuesDic->mutableCopy;
                foreach my $key (@plistKeysToDelete) {
                    $valuesDicM->removeObjectForKey_($key);
                }
                $plistData->setObject_forKey_($valuesDicM, "values");
            }
            my $keyNamesArray = $plistData->allKeys();
            my $items         = $keyNamesArray->count;
            for (my $index = 0; $index < $items; ++$index) {
                my $key = $keyNamesArray->objectAtIndex_($index)->UTF8String();
                if (rindex($key, "InstaprojectWindowSavedBounds", 0) != -1
                    || rindex($key, "ImageDisplayGrayLevel_", 0) != -1)
                {
                    $plistData->removeObjectForKey_($key);
                }
            }
            unlink($File::Find::name);
            $plistData->writeToFile_atomically_($File::Find::name, "0");
        };
    }
}

#*****************************************************************************************
# process the plists in the Preferences folder
#*****************************************************************************************
sub plists {
    find(\&processFiles, "$HOME/Downloads/dotfiles");
}

#*****************************************************************************************
# script main line
#*****************************************************************************************
plists();
PERL
}

#*****************************************************************************************
# script main line
#*****************************************************************************************

format-project.sh "/opt/geedbla"

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
			exit 0
			;;
	esac
else
	updateGitHub
fi
cleanSettingsFiles
