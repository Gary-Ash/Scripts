#!/usr/bin/env bash
#*****************************************************************************************
# ocd.sh
#
# Update system software and clean macOS settings
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :  21-Apr-2026  2:35pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# source in library functions
#*****************************************************************************************
source "/opt/geedbla/lib/shell/lib/get_sudo_password.sh"

#*****************************************************************************************
# globals
#*****************************************************************************************
export SUDO_PASSWORD
SUDO_SHELL_PID=""
CAFFEINATE=""

#*****************************************************************************************
# set a exit trap to make sure the persistent sudo thread is always cleaned up
#*****************************************************************************************
trap finish EXIT

finish() {
	if [[ -n $ZSH_VERSION ]]; then
		setopt local_options no_monitor
	fi

	[[ -n $SUDO_SHELL_PID ]] && kill "$SUDO_SHELL_PID" 2>/dev/null
	[[ -n $CAFFEINATE ]] && kill "$CAFFEINATE" 2>/dev/null
	wait 2>/dev/null
	unset SUDO_SHELL_PID
	unset CAFFEINATE
	unset SUDO_PASSWORD

	if [[ -n $ZSH_VERSION ]]; then
		setopt monitor
	fi
}

#*****************************************************************************************
# kill applications
#*****************************************************************************************
killEverything() {
	osascript <<"CLOSE_SCRIPT" &>/dev/null
set backgroundsToKill to ¬
	{"Keyboard Maestro Engine", ¬
		"Bartender 6", ¬
		"Safari", ¬
		"Dash", ¬
		"Alfred", ¬
		"Moom", ¬
		"SnippetsLab", ¬
		"Slack", ¬
		"Mona", ¬
		"Pastebot"}

repeat with appName in backgroundsToKill
	try
		tell application (appName as text) to quit
	end try
end repeat
tell application "System Events"
	try
		set processList to the name of ¬
			every process whose visible is true as string
	on error
		set processList to {}
	end try

	set activeApp to name of first application process whose frontmost is true as string
	repeat with processName in processList
		if processName as string is not equal to activeApp then
			try
				tell application (processName as text) to quit
			end try
		end if
	end repeat
end tell
CLOSE_SCRIPT
}

#-----------------------------------------------------------------------------------------
# SCRIPT MAIN LINE
#-----------------------------------------------------------------------------------------

#*****************************************************************************************
# parse the command line for arguments
#*****************************************************************************************
cmd=""
if [[ $# -gt 0 ]]; then
	cmd=$(echo "$1" | tr '[:upper:]' '[:lower:]')

	if [ "$cmd" != "restart" ] && [ "$cmd" != "off" ]; then
		echo "Unknown command option -- $cmd"
		exit 1
	fi
fi
export OCD_OPTION="$cmd"

error_log="$TMPDIR/Error.txt"

killEverything
cd ~ || exit 1

#*****************************************************************************************
# brew
#*****************************************************************************************
if command -v brew &>/dev/null; then
	brew update &>"$error_log"
	brew upgrade &>"$error_log"
	brew upgrade --cask &>"$error_log"
	brew autoremove &>"$error_log"
	brew cleanup &>"$error_log"
	rm -rf "$(brew --cache)" &>/dev/null
fi

#*****************************************************************************************
# Update Github gh extensions
#*****************************************************************************************
if command -v gh &>/dev/null; then
	gh extension upgrade --all >/dev/null
fi

#*********************************************************************************
# ruby update
#*********************************************************************************
if command -v gem &>/dev/null; then
	gem update &>"$error_log"
	gem cleanup &>"$error_log"
fi

#*********************************************************************************
# python 3 update
#*********************************************************************************
if command -v pip3 &>/dev/null; then
	python3 -m pip install --upgrade pip &>"$error_log"
	pip3 freeze | cut -d = -f 1 | xargs pip3 install -U &>"$error_log"
fi

#*****************************************************************************************
# npm update
#*****************************************************************************************
if command -v npm &>/dev/null; then
	npm install -g npm@latest &>"$error_log"
fi
#*****************************************************************************************
pkill -f '.*GradleDaemon.*'
qlmanage -r &>/dev/null
killall "Crash Reporter" ReportCrash &>/dev/null

find "$HOME" -name "Icon?" -exec chflags hidden {} \; &>/dev/null
#*****************************************************************************************
# clean my git projects
#*****************************************************************************************
while IFS= read -r gitDir; do
	[[ -z $gitDir ]] && continue
	cd "$(dirname "$gitDir")" || exit 1
	git gc --aggressive --prune=now &>/dev/null
done < <(find "$HOME/Developer" "$HOME/Documents" -type d -name ".git" 2>/dev/null)

find "$HOME/Developer" -type d -name "*xcuserdatad" ! -name "garyash.xcuserdatad" -exec rm -rf {} \; &>/dev/null
find "$HOME/Documents" -type d -name "*xcuserdatad" ! -name "garyash.xcuserdatad" -exec rm -rf {} \; &>/dev/null

find "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Preferences" -name "Keyboard Maestro Macros \(*.kmsync" -delete &>/dev/null
find "$HOME/Library/Application Support/AddressBook" -name "*.abbu.tbz" -delete &>/dev/null
find "/Users/Shared/CleanMyMac_5/" -depth 1 ! -name ".licence" -exec rm -rfv {} \; &>/dev/null
find "$HOME/Sites" \( -name "Gemfile.lock" -or -name ".sass-cache" -or -name ".jekyll*" -or -name "_site" -or -name ".jekyll-metadata" \) -exec rm -rfv {} \; &>/dev/null
find "$HOME/Developer" \( -name "Gemfile.lock" -or -name ".sass-cache" -or -name ".jekyll*" -or -name "_site" -or -name ".jekyll-metadata" \) -exec rm -rfv {} \; &>/dev/null

perl /opt/geedbla/scripts/load-simulator.pl &
perl /opt/geedbla/scripts/safari-cleaner.pl &>/dev/null
#*****************************************************************************************
# setup the sudo until the script is done
#*****************************************************************************************
SUDO_PASSWORD="$(get_sudo_password)"
echo "$SUDO_PASSWORD" | sudo --validate --stdin &>/dev/null
while true; do
	sudo --non-interactive -E true
	sleep 20
done &

export SUDO_SHELL_PID=$!
caffeinate -s -b &>/dev/null &
export CAFFEINATE=$!

sudo chown -R garyash:admin /opt/geedbla/* &>/dev/null
sudo chown -R root:admin /Applications/* &>/dev/null
sudo chmod -R 775 /Applications/* &>/dev/null

sudo /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -r -domain local -domain system -domain user &>/dev/null

#****************************************************************************************
# Pause Time Machine while updating and cleaning
#****************************************************************************************
sudo tmutil stopbackup

#*****************************************************************************************
# empty trash
#*****************************************************************************************
sudo rm -rf ~/.Trash /Volumes/*/.Trashes &>/dev/null
rm -rf "$HOME/Library/Mobile Documents/com~apple~CloudDocs/.Trash"

#*****************************************************************************************
# AI Cleanup (Claude)
#*****************************************************************************************
if jq 'del(.projects, .githubRepoPaths,
		.opusProMigrationTimestamp, .changelogLastFetched) |
	.hasShownOpus45Notice = {} |
	.s1mAccessCache = {} |
	.groveConfigCache = {} |
	.skillUsage = {}' "$HOME/.claude.json" >"$HOME/.claude.json1"; then
	mv -f "$HOME/.claude.json1" "$HOME/.claude.json"
else
	rm -f "$HOME/.claude.json1"
fi
rm -f ~/.claude.json.backup.*

#*****************************************************************************************
# clean up Time Machine local backups and turn it back on
#*****************************************************************************************
snapshots=()
while IFS= read -r line; do
	if [[ $line =~ com\.apple\.TimeMachine\.([0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6})\.local ]]; then
		snapshots+=("${BASH_REMATCH[1]}")
	fi
done < <(sudo tmutil listlocalsnapshots /)

for snapshot in "${snapshots[@]}"; do
	tmutil deletelocalsnapshots "$snapshot" &>/dev/null
done

echo -n '' | pbcopy

#*****************************************************************************************
# Clean Messages
#*****************************************************************************************
DB="$HOME/Library/Messages/chat.db"

# Quit Messages
osascript -e 'tell application "Messages" to quit' 2>/dev/null
sleep 2

# Save triggers, drop them, delete data, restore triggers
sqlite3 "$DB" <<'SQL'
-- Save all trigger definitions
.mode list
.output /tmp/messages_triggers.sql
SELECT sql || ';' FROM sqlite_master WHERE type='trigger' AND sql IS NOT NULL;
.output stdout

-- Drop all triggers
DROP TRIGGER IF EXISTS update_message_date_after_update_on_message;
DROP TRIGGER IF EXISTS add_to_sync_deleted_messages;
DROP TRIGGER IF EXISTS before_deleting_chat_delete_chat_background_trigger;
DROP TRIGGER IF EXISTS after_delete_on_chat_message_join;
DROP TRIGGER IF EXISTS add_to_deleted_messages;
DROP TRIGGER IF EXISTS after_delete_on_chat_handle_join;
DROP TRIGGER IF EXISTS after_insert_on_message_attachment_join;
DROP TRIGGER IF EXISTS after_delete_on_message;
DROP TRIGGER IF EXISTS delete_associated_messages_after_delete_on_message;
DROP TRIGGER IF EXISTS verify_chat_update;
DROP TRIGGER IF EXISTS after_insert_on_chat_message_join;
DROP TRIGGER IF EXISTS add_to_sync_deleted_attachments;
DROP TRIGGER IF EXISTS after_delete_on_message_plugin;
DROP TRIGGER IF EXISTS before_delete_on_attachment;
DROP TRIGGER IF EXISTS after_delete_on_message_attachment_join;
DROP TRIGGER IF EXISTS after_delete_on_attachment;
DROP TRIGGER IF EXISTS after_delete_on_chat;
DROP TRIGGER IF EXISTS update_last_failed_message_date;
DROP TRIGGER IF EXISTS after_delete_on_chat_recoverable_message_join;
DROP TRIGGER IF EXISTS verify_chat_insert;
DROP TRIGGER IF EXISTS chat_service_on_insert_chat_message_join;
DROP TRIGGER IF EXISTS before_delete_chat_update_sync_chat_deletes;
DROP TRIGGER IF EXISTS message_index_state_propagation;
DROP TRIGGER IF EXISTS message_index_state_clear;
DROP TRIGGER IF EXISTS index_metrics_delete_propagation;
DROP TRIGGER IF EXISTS index_metrics_update_propagation;
DROP TRIGGER IF EXISTS index_metrics_insert_propagation;

-- Clear all data
DELETE FROM message_attachment_join;
DELETE FROM chat_message_join;
DELETE FROM chat_handle_join;
DELETE FROM chat_recoverable_message_join;
DELETE FROM deleted_messages;
DELETE FROM recoverable_message_part;
DELETE FROM sync_deleted_messages;
DELETE FROM sync_deleted_chats;
DELETE FROM sync_deleted_attachments;
DELETE FROM unsynced_removed_recoverable_messages;
DELETE FROM message;
DELETE FROM attachment;
DELETE FROM chat;
DELETE FROM handle;

VACUUM;
SQL

# Restore triggers
sqlite3 "$DB" </tmp/messages_triggers.sql 2>/dev/null
rm -f /tmp/messages_triggers.sql

sudo -E /usr/bin/perl <<'PERL' &>/dev/null
#!/usr/bin/env perl
#*****************************************************************************************
# libraries used
#*****************************************************************************************
use strict;
use warnings;
use Foundation;

use POSIX qw(strftime);
use utf8;
use Encode qw(decode encode);
use JSON::PP;
use XML::Simple;
use File::Find;
use File::Path qw(remove_tree);
use DateTime;

#*****************************************************************************************
# globals
#*****************************************************************************************
our $HOME = $ENV{'HOME'};

our @plistKeysToDelete = (
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
    "FXLastSearchScope",
    "NSNavPanel",
    "NSNavRecentPlaces",
    "NSNavLastRootDirectory",
    "NSNavLastCurrentDirectory",
    "LRUDocumentPaths",
    "TSAOpenedTemplates.Pages",
    "NSReplacePboard",
    "SelectedURLs",
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
    "IDEDefaultPrimaryEditorFrameSizeForPaths",
    "IDEDocViewerLastViewedURLKey",
    "IDESourceControlRecentsFavoritesRepositoriesUserDefaultsKey",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateCategory",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateCategory",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateSection",
    "last_name",
    "findRecentPlaces",
    "RecentWebSearches",
    "recentSearches",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_macOS",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_iOS",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_tvOS",
    "SGTRecentFileSearches",
    "IDEDistributionPlanSelection",
    "IDEFileTemplateChooserAssistantSelectedTemplateSection",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_tvOS",
    "IDEFileTemplateChooserAssistantSelectedTemplateName_tvOS",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_iOS",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_Multiplatform",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_macOS",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_Multiplatform",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateSection",
    "DVTTextCompletionRecentCompletions",
    "GoToFieldHistory",
    "HistoryColors",
    "recentSearchHints",
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
    "LastOpenByNameString",
    "IDEChatUserSelectedDefaultChatModelDefinitionIdentifier",
    "IDEAnalyticsMetricsNotifications.AnalyticsMetricsNotificationsController.lastRefreshAttemptDate",
    "SULastCheckedDate",
    "LastLaunchOSVersion",
    "savedLastOpen",
    "IDELastViewedSettingsPane",
    "LastTerminalStartTime",
    "IDEMostRecentPostFLEDate",
    "RecentTemplates",
);

our @itemsToDelete = (
    ["$HOME/Library/Containers/com.apple.corerecents.recentsd/Data/Library/Recents",                  									  0],
    ["$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments",                  0],
    ["$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentDocuments.sfl3",                        0],
    ["$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ProjectsItems.sfl3",                          0],
    ["$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentApplications.sfl3",                     0],
    ["$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentServers.sfl3",                          0],
    ["$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentHosts.sfl3",                            0],
    ["$HOME/Library/Application Support/zoxide/",                                                                                         1],
    ["$HOME/Library/Preferences/com.googlecode.iterm2.private.plist",                                                                     0],
    ["$HOME/Library/Preferences/com.apple.dock.extra.plist",                                                                              0],
    ["$HOME/Library/Preferences/us.zoom.ZoomClips.plist",                                                                                 0],
    ["$HOME/Library/Preferences/org.sparkle-project.Sparkle.Autoupdate.plist",                                                            0],
    ["$HOME/.proxyman-data",                                                                                                              0],
    ["$HOME/.hawtjni",                                                                                                                    0],
    ["$HOME/.claude/cache",                                                                                                               0],
    ["$HOME/.claude/data",                                                                                                                0],
    ["$HOME/.claude/backups",                                                                                                             0],
    ["$HOME/.claude/image-cache",                                                                                                         0],
    ["$HOME/.claude/session-env",                                                                                                         0],
    ["$HOME/.claude/plans",                                                                                                               0],
    ["$HOME/.claude/projects",                                                                                                            0],
    ["$HOME/.claude/tasks",                                                                                                               0],
    ["$HOME/.claude/todos",                                                                                                               0],
    ["$HOME/.claude/debug",                                                                                                               0],
    ["$HOME/.claude/statsig",                                                                                                             0],
    ["$HOME/.claude/downloads",                                                                                                           0],
    ["$HOME/.claude/telemetry",                                                                                                           0],
    ["$HOME/.claude/plugins/blocklist.json",                                                                                              0],
    ["$HOME/.claude/shell-snapshots",                                                                                                     0],
    ["$HOME/.claude/file-history",                                                                                                        0],
    ["$HOME/.claude/history.jsonl",                                                                                                       0],
    ["$HOME/.claude/stats-cache.json",                                                                                                    0],
    ["$HOME/.claude/paste-cache",                                                                                                         0],
    ["$HOME/.claude/sessions",                                                                                                            0],
    ["$HOME/.npm",                                                                                                                        0],
    ["$HOME/.konan",                                                                                                                      0],
    ["$HOME/.ssh/known_hosts.old",                                                                                                        0],
    ["$HOME/.cocoapods",                                                                                                                  0],
    ["$HOME/.swiftpm",                                                                                                                    0],
    ["$HOME/.fastlane",                                                                                                                   0],
    ["$HOME/.subversion",                                                                                                                 0],
    ["$HOME/.node_modules",                                                                                                               0],
    ["$HOME/.android/",                                                                                                                   0],
    ["$HOME/.cache/",                                                                                                                     0],
    ["$HOME/.bash_history",                                                                                                               0],
    ["$HOME/.python_history",                                                                                                             0],
    ["$HOME/.zcompcache",                                                                                                                 0],
    ["$HOME/.zsh_history",                                                                                                                0],
    ["$HOME/.bundle",                                                                                                                     0],
    ["$HOME/.gem",                                                                                                                        0],
    ["$HOME/Library/Caches/Yarn",                                                                                                         0],
    ["$HOME/.oracle_jre_usage",                                                                                                           0],
    ["$HOME/.bash_sessions",                                                                                                              0],
    ["$HOME/.gradle",                                                                                                                     0],
    ["$HOME/.recently-used",                                                                                                              0],
    ["$HOME/.cmake",                                                                                                                      0],
    ["$HOME/.solargraph",                                                                                                                 0],
    ["$HOME/.TemporaryItems",                                                                                                             0],
    ["$HOME/.thumbnails",                                                                                                                 0],
    ["$HOME/.config/zsh/.zsh_sessions",                                                                                                   0],
    ["$HOME/.config/zsh/histfile",                                                                                                        1],
    ["$HOME/.config/zsh/.zsh_history",                                                                                                    1],
    ["$HOME/.config/zsh/zcompdump-*",                                                                                                     1],
    ["$HOME/triald-*.ips",                                                                                                                1],
    ["$HOME/.config/configstore",                                                                                                         0],
    ["$HOME/Pictures/Pixelmator Pro Sidecar Files/",                                                                                      0],
    ["$HOME/Library/Application Support/BBEdit/Workspaces",                                                                               0],
    ["$HOME/Library/Containers/com.barebones.bbedit/Data/Library/BBEdit/Rescued Documents",                                               1],
    ["$HOME/Library/Containers/com.barebones.bbedit/Data/Library/BBEdit/Auto-Save Recovery",                                              0],
    ["$HOME/Library/Containers/com.barebones.bbedit/Data/Sleep State.appstate",                                                           0],
    ["$HOME/Library/Autosave Information",                                                                                                0],
    ["$HOME/Library/Caches/org.carthage.CarthageKit",                                                                                     0],
    ["$HOME/Library/Saved Application State",                                                                                             0],
    ["$HOME/Library/Application Support/Steam",                                                                                           0],
    ["$HOME/Library/Application Support/iLifeMediaBrowser",                                                                               0],
    ["$HOME/Library/Application Support/CrashReporter",                                                                                   0],
    ["$HOME/Library/Application Support/CallHistoryDB",                                                                                   0],
    ["$HOME/Library/Application Support/CallHistoryTransactions",                                                                         0],
    ["$HOME/Library/Application Support/dmd",                                                                                             0],
    ["$HOME/Library/Application Support/iMovie",                                                                                          0],
    ["$HOME/Library/Application Support/Translation",                                                                                     0],
    ["$HOME/Library/Developer/CoreSimulator/Caches",                                                                                      0],
    ["$HOME/Library/Developer/Xcode/UserData/IDEEditorInteractivityHistory",                                                              0],
    ["$HOME/Library/Developer/Xcode/DocumentationCache",                                                                                  0],
    ["$HOME/Library/Developer/Xcode/.derived-data-log*",                                                                                  0],
    ["$HOME/Library/Developer/Xcode/DocumentationIndex",                                                                                  0],
    ["$HOME/Library/Developer/Xcode/Products",                                                                                            0],
    ["$HOME/Library/Caches/Homebrew",                                                                                                     0],
    ["$HOME/Library/Caches/Homebrew/Backup",                                                                                              0],
    ["$HOME/Library/Cookies/Hocom.kapeli.dashdoc.binarycookies",                                                                          0],
    ["$HOME/Library/Cookies/org.m0k.transmission.binarycookies",                                                                          0],
    ["$HOME/Library/Caches/com.apple.dt.Xcode",                                                                                           0],
    ["$HOME/Pictures/iSkysoft VideoConverterUltimate",                                                                                    0],
    ["$HOME/Movies/iSkysoft VideoConverterUltimate",                                                                                      0],
    ["$HOME/Library/Preferences/com.apple.LaunchServices",                                                                                0],
    ["$HOME/Library/Preferences/UITextInputContextIdentifiers.plist",                                                                     0],
    ["$HOME/Library/Preferences/com.apple.EmojiCache.plist",                                                                              1],
    ["$HOME/Library/Preferences/com.apple.EmojiPreferences.plist",                                                                        1],
    ["$HOME/Movies/Motion Templates.localized",                                                                                           0],
    ["$HOME/Movies/Untitled.fcpbundle",                                                                                                   0],
    ["$HOME/Movies/iMovie Library.imovielibrary",                                                                                         0],
    ["$HOME/Movies/iMovie Theater.theater",                                                                                               0],
    ["$HOME/Music/Audio Music Apps",                                                                                                      0],
    ["$HOME/Library/Application Support/kotlin",                                                                                          0],
    ["$HOME/Library/Application Support/Mozilla",                                                                                         0],
    ["$HOME/Library/Application Support/JetBrains",                                                                                       0],
    ["$HOME/Library/Application Support/Battle.net",                                                                                      0],
    ["$HOME/Library/org.swift.swiftpm",                                                                                                   0],
    ["$HOME/Music/Logic",                                                                                                                 0],
    ["$HOME/Library/Cookies/com.apple.Safari.SearchHelper.binarycookies",                                                                 0],
    ["$HOME/Library/Application Support/iPhone Simulator",                                                                                0],
    ["$HOME/Library/Messages/Archive",                                                                                                    0],
    ["$HOME/Library/Messages/Attachments",                                                                                                0],
    ["$HOME/Library/Metadata/com.apple.IntelligentSuggestions",                                                                           1],
    ["$HOME/Library/Application Support/Xcode",                                                                                           1],
    ["$HOME/Library/Developer/Xcode/Archives",                                                                                            0],
    ["$HOME/Library/Developer/Xcode/snapshots",                                                                                           0],
    ["$HOME/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig", 																  1],
    ["$HOME/Library/Developer/Xcode/UserData/*.xcuserstate",                                                                              1],
    ["$HOME/Library/Developer/Xcode/UserData/CodingAssistant",                                                                            1],
    ["$HOME/Library/Application Support/Alfred/Caches",                                                                                   1],
    ["$HOME/Library/Application Support/Alfred/Workflow Data",                                                                            1],
    ["$HOME/Library/Application Support/Sublime Merge/Local/Backup Session.sublime_session",                                              0],
    ["$HOME/Library/Application Support/Sublime Merge/Log",                                                                               0],
    ["$HOME/Library/Application Support/Sublime Merge/Cache",                                                                             1],
    ["$HOME/Library/Application Support/Sublime Text/Backup",                                                                             0],
    ["$HOME/Library/Application Support/Sublime Text/Cache",                                                                              1],
    ["$HOME/Library/Application Support/Sublime Text/Index",                                                                              1],
    ["$HOME/Library/Application Support/Sublime Text/Log",                                                                                0],
    ["$HOME/Library/Application Support/Sublime Text/Trash",                                                                              0],
    ["$HOME/Library/Application Support/Sublime Text/Local/Backup Auto Save Session.sublime_session",                                     0],
    ["$HOME/Library/Application Support/Sublime Text/Local/Backup Session.sublime_session",                                               0],
    ["$HOME/Library/Application Support/Sublime Text/Packages/User/Package Control.cache",                                                1],
    ["$HOME/Library/Application Support/Sublime Text (Safe Mode)",                                                                        0],
    ["$HOME/Library/Caches/com.apple.Safari/Webpage Previews",                                                                            1],
    ["$HOME/Library/Caches/com.apple.Safari/Cache.*",                                                                                     1],
    ["$HOME/Library/Caches/com.apple.Safari/fsCachedData",                                                                                1],
    ["$HOME/Library/Caches/com.apple.Safari/WebKitCache",                                                                                 1],
    ["$HOME/Library/Safari/Configurations.plist.signed",                                                                                  1],
    ["$HOME/Library/Caches/com.apple.Safari/Cache.db",                                                                                    1],
    ["$HOME/Library/Safari/CloudBookmarksMigrationCoordinator",                                                                           0],
    ["$HOME/Library/Safari/Cloud*",                                                                                                       1],
    ["$HOME/Library/Safari/LastSession.plist",                                                                                            1],
    ["$HOME/Library/Safari/TopSites.plist",                                                                                               1],
    ["$HOME/Library/Safari/Downloads.plist",                                                                                              1],
    ["$HOME/Library/Safari/WebFeedSources.plist",                                                                                         1],
    ["$HOME/Library/Safari/SearchDescriptions.plist",                                                                                     1],
    ["$HOME/Library/Safari/RecentlyClosedTabs.plist",                                                                                     1],
    ["$HOME/Library/Preferences/test_network.plist",                                                                                      1],
    ["$HOME/Library/Preferences/com.apple.sharekit.recents.plist",                                                                        1],
    ["$HOME/Library/Preferences/com.trolltech.plist",                                                                                     1],
    ["$HOME/Library/Preferences/com.qtproject.plist",                                                                                     1],
    ["$HOME/Library/Application Support/Dash/Temp",                                                                                       1],
    ["$HOME/Library/Developer/Xcode/UserData/IB Support",                                                                                 0],
    ["$HOME/Library/Containers/com.koolesache.ColorSnapper2/Data/Library/Caches/com.koolesache.ColorSnapper2",                            0],
    ["$HOME/Library/Application Support/Keyboard Maestro/Keyboard Maestro Recent Applications.plist",                                     0],
    ["$HOME/Library/Application Support/Keyboard Maestro/Keyboard Maestro Clipboards.kmchunked",                                          0],
    ["$HOME/Library/Colors/NSColorPanelSwatches.plist",                                                                                   1],
    ["$HOME/Library/Preferences/embeddedBinaryValidationUtility.plist",                                                                   1],
    ["$HOME/Library/Containers/com.apple.podcasts/Data/Library/Preferences/com.apple.podcasts.plist",                                     0],
    ["$HOME/Library/Application Support/Microsoft Edge/Default/Sessions",                                                                 0],
    ["$HOME/Library/Application Support/Microsoft Edge/Default/*History*",                                                                0],
    ["$HOME/Library/Application Support/Microsoft Edge/Default/Local Storage",                                                            0],
    ["$HOME/Library/Application Support/Microsoft Edge/Default/Top Sites",                                                                0],
    ["$HOME/Library/Application Support/Microsoft Edge/Default/Top Sites-journal",                                                        0],
    ["$HOME/Library/Preferences/diagnostics_agent.plist",                                                                                 0],
    ["$HOME/Library/Preferences/sharedfilelistd.plist",                                                                                   0],
    ["$HOME/Library/Application Support/Google/Chrome/Profile 1/History",                                                                 0],
    ["$HOME/Library/Application Support/Google/Chrome/Profile 1/History-journal",                                                         0],
    ["$HOME/Library/Application Support/Google/Chrome/Profile 1/Top Sites",                                                               0],
    ["$HOME/Library/Application Support/Google/Chrome/Profile 1/Top Sites-journal",                                                       0],
    ["$HOME/Library/Application Support/Google/Chrome/Profile 1/Visited Links",                                                           0],
    ["$HOME/Library/Containers/com.apple.iBooksX/Data/Documents/BCRecentlyOpenedBooksDB",                                                 0],
    ["$HOME/Library/Containers/com.runisoft.Video-Joiner-and-Merger/Data/Library/Preferences/com.runisoft.Video-Joiner-and-Merger.plist", 0],
    ["$HOME/Library/Containers/com.bridgetech.asset-catalog/Data/Library/Application Support/saved_asset_catalog_creator",                0],
    ["$HOME/Library/Caches/com.apple.Music/SubscriptionPlayCache/",                                                                       0],
    ["$HOME/Library/Application Support/iTerm2/SavedState/lock",                                                                          0],
    ["/Library/Logs",                                                                                                                     1],
    ["/Library/Logs/DiagnosticReports",                                                                                                   1],
    ["/private/var/folders/sf/_p_7qs4n7gg_r4yrrrvmphd00000gn/C/us.zoom.ZoomAutoUpdater",                                                  0],
    ["/private/var/folders/3j/tgfs5z8x2wg2krlgnzj4jzc00000gn/C/com.koolesache.ColorSnapper2",                                             0],
    ["/private/var/folders/3j/tgfs5z8x2wg2krlgnzj4jzc00000gn/T/com.koolesache.ColorSnapper2",                                             0],
    ["/private/var/folders/3j/tgfs5z8x2wg2krlgnzj4jzc00000gn/C/com.koolesache.ColorSnapper2Helper",                                       0],
    ["/private/var/folders/3j/tgfs5z8x2wg2krlgnzj4jzc00000gn/T/com.koolesache.ColorSnapper2Helper",                                       0],
);

#*****************************************************************************************
# script main line
#*****************************************************************************************
podcastapp();
texturePacker();
BBEdit();
books();

plists();
deleteFilesAndFolders();
xcode();
sublimeText();
sublimeMerge();

#*****************************************************************************************
# Books
#*****************************************************************************************
sub books {
    my $now = DateTime->now;
    $now->set_time_zone("UTC");
    my $datestring = $now->strftime("%Y-%m-%dT%TZ");

    my $plistFile = "$HOME/Library/Containers/com.apple.iBooksX/Data/Library/Preferences/com.apple.iBooksX.plist";
    my $plist     = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);

    if ($plist) {
        $plist->setObject_forKey_($datestring, "BKRecentsLastCleared");
        $plist->writeToFile_atomically_($plistFile, "0");
    }
}

#*****************************************************************************************
# Sublime Text
#*****************************************************************************************
sub sublimeText {
    my $filename     = "$HOME/Library/Application Support/Sublime Text/Local/Session.sublime_session";
    my @keysToDelete = ("auto_complete", "file_history", "replace", "find_state", "find_in_files", "project", "buffers", "command_palette", "expanded_folders", "workspace_name", "folders", "console", "groups");

    if (-e $filename) {
        open(my $configFile, "<", $filename);
        my $json = do { local $/; <$configFile> };
        close($configFile);
        my $utf8 = encode("UTF-8", $json);

        my $config = decode_json($utf8);
        delete $config->{'workspaces'};
        delete $config->{'folder_history'};
        for my $key (@keysToDelete) {
            delete $config->{$key};
        }
        for my $key (@keysToDelete) {
            delete $config->{'settings'}->{'new_window_settings'}->{$key};
            delete $config->{'settings'}->{$key};
        }
        my $firstFlag = 1;
        my @windows   = @{ $config->{'windows'} };
        for my $window (@windows) {
            if ($firstFlag == 0) {
                undef $window;
            }
            else {
                $firstFlag = 0;
            }
        }
        for my $key (@keysToDelete) {
            delete $windows[0]->{$key};
        }

        my %newConsole = (
            "height" => 220.0,
        );

        $windows[0]->{'console'} = \%newConsole;
        $config->{'windows'}     = \@windows;
        $json                    = encode_json($config);
        open($configFile, ">:encoding(UTF-8)", $filename);
        print $configFile $json;
        close($configFile);

        my $plistFile = "$HOME/Library/Preferences/com.sublimetext.4.plist";
        my $plist     = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
        $plist->setObject_forKey_("$HOME/Developer/", "NSNavLastRootDirectory");
        $plist->writeToFile_atomically_($plistFile, "0");

    }

}

#*****************************************************************************************
# Sublime Merge
#*****************************************************************************************
sub sublimeMerge {
    my $filename     = "$HOME/Library/Application Support/Sublime Merge/Local/Session.sublime_session";
    my @keysToDelete = ("recent", "select_repository", "windows", "window_positions");

    if (-e $filename) {
        open(my $configFile, "<", $filename);
        my $json = do { local $/; <$configFile> };
        close($configFile);
        my $utf8 = encode("UTF-8", $json);

        my $config = decode_json($utf8);
        for my $key (@keysToDelete) {
            delete $config->{$key};
        }
        $config->{"project_dir"} = "$HOME/Developer";
        $json = encode_json($config);
        open($configFile, ">:encoding(UTF-8)", $filename);
        print $configFile $json;
        close($configFile);

        my $plistFile = "$HOME/Library/Preferences/com.sublimemerge.plist";
        my $plist     = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
        $plist->setObject_forKey_("$HOME/Developer/", "NSNavLastRootDirectory");
        $plist->writeToFile_atomically_($plistFile, "0");
    }
}

#*****************************************************************************************
# BBEdit
#*****************************************************************************************
sub BBEdit {
    my @files = ("$HOME/Library/Containers/com.barebones.bbedit/Data/Library/Preferences/com.barebones.bbedit.plist", "$HOME/Library/Application Support/BBEdit/Setup/BBEdit Preferences Backup.plist",);

    foreach my $plistFile (@files) {
        my $plist = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
        if ($plist && $$plist) {
            my $keyNamesArray = $plist->allKeys();
            my $items         = $keyNamesArray->count;
            for (my $index = 0; $index < $items; ++$index) {
                my $key = $keyNamesArray->objectAtIndex_($index)->UTF8String();
                if (   rindex($key, "InstaprojectWindowSavedBounds", 0) != -1
                    || rindex($key, "ImageDisplayGrayLevel_", 0) != -1
                    || $key =~ /^~[0-9A-Fa-f]{40}$/)
                {
                    $plist->removeObjectForKey_($key);
                }
            }
            unlink($plistFile);
            $plist->writeToFile_atomically_($plistFile, "0");
        }
    }
}

#*****************************************************************************************
# Texture Packer
#*****************************************************************************************
sub texturePacker {
    my $plistFile = "$HOME/Library/Preferences/de.code-and-web.TexturePacker.plist";
    my $plist     = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
    if ($plist && $$plist) {
        my $keyNamesArray = $plist->allKeys();
        my $items         = $keyNamesArray->count;
        for (my $index = 0; $index < $items; ++$index) {
            my $key = $keyNamesArray->objectAtIndex_($index)->UTF8String();
            if ($key =~ /[A-Za-z0-9\-\.]*Users/) {
                $plist->removeObjectForKey_($key);
            }
        }
        unlink($plistFile);
        $plist->writeToFile_atomically_($plistFile, "0");
    }
}

#*****************************************************************************************
# Podcast
#*****************************************************************************************
sub podcastapp {
    my $plistFile = "$HOME/Library/Containers/com.apple.podcasts/Data/Library/Preferences/com.apple.podcasts.plist";
    my $plist     = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
    if ($plist && $$plist) {
        my $keyNamesArray = $plist->allKeys();
        my $items         = $keyNamesArray->count;
        for (my $index = 0; $index < $items; ++$index) {
            my $key = $keyNamesArray->objectAtIndex_($index)->UTF8String();
            if ($key =~ /playState:.*/) {
                $plist->removeObjectForKey_($key);
            }
        }
        unlink($plistFile);
        $plist->writeToFile_atomically_($plistFile, "0");
    }
}

#*****************************************************************************************
# process the plists in the Preferences folder
#*****************************************************************************************
sub plists {
    `killall Dock Finder recentsd`;
    foreach my $plistFile (glob "$HOME/Library/Preferences/*.plist") {
        eval {
            my $plistData = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
            foreach my $key (@plistKeysToDelete) {
                $plistData->removeObjectForKey_($key);
            }
            $plistData->writeToFile_atomically_($plistFile, "0");
        };
    }
    find(\&processFiles, "$HOME/Library/Containers/");
}

#*****************************************************************************************
# delete junk from a list of file and folders
#*****************************************************************************************
sub deleteFilesAndFolders {
    my %removeTreeOptions = (
        safe      => 1,
        verbose   => 0,
        keep_root => 1
    );

    `killall Dock Finder recentsd`;
    for my $item (0 .. $#itemsToDelete) {
        my $i                         = "\"" . $itemsToDelete[$item][0] . "\"";
        my @actualFilesAndDirectories = glob $i;
        for my $delete (@actualFilesAndDirectories) {
            if (-f $delete) {
                unlink($delete);
            }
            else {
                $removeTreeOptions{keep_root} = $itemsToDelete[$item][1];
                remove_tree($delete, \%removeTreeOptions);
            }
        }
    }
    my $temp = $ENV{'TMPDIR'};
    $removeTreeOptions{keep_root} = 1;
    remove_tree($temp, \%removeTreeOptions);
}

#*****************************************************************************************
# Xcode settings
#*****************************************************************************************
sub xcode {
    my $plistFile = "$HOME/Library/Preferences/com.apple.dt.Xcode.plist";
    my $plist     = NSMutableDictionary->dictionaryWithContentsOfFile_($plistFile);
    if ($plist) {
        my $options         = NSMutableDictionary->dictionary();
        my %templateOptions = (
            "languageChoice"         => "Swift",
            "bundleIdentifierPrefix" => "com.geedbla",
            "ORGANIZATIONNAME"       => "Gee Dbl A",
        );
        foreach my $key (keys %templateOptions) {
            $options->setObject_forKey_($templateOptions{$key}, $key);
        }
        $plist->setObject_forKey_($options,           "IDETemplateOptions");
        $plist->setObject_forKey_("$HOME/Developer/", "NSNavLastRootDirectory");
        $plist->writeToFile_atomically_($plistFile, "0");
    }
}

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

            $plistData->writeToFile_atomically_($File::Find::name, "0");
        };
    }
}
PERL

osascript <<END
try
	tell application "Keyboard Maestro Engine" to quit
end try

(*****************************************************************************************
 * clean  Mail
 ****************************************************************************************)
try
	tell application "Mail" to launch
	repeat while application "Mail" is not running
		delay 1
	end repeat
	delay 2
	tell application "System Events" to tell process "Mail"
		repeat
			try
				activate
				set frontmost to true
				click checkbox 1 of group 1 of window 1
				exit repeat
			end try
		end repeat
		click menu item "Erase Junk Mail" of menu 1 of menu bar item "Mailbox" of menu bar 1
		delay 1
		click button "Erase" of sheet 1 of window 1
		delay 1
		click menu item "In All Accounts…" of menu 1 of menu item "Erase Deleted Items" of menu 1 of menu bar item "Mailbox" of menu bar 1
		delay 1

		click button "Erase" of sheet 1 of window 1
		delay 1
		click menu item "Previous Recipients" of menu 1 of menu bar item "Window" of menu bar 1
		delay 1

		try
			if number of rows in table 1 of scroll area 1 of window 1 > 0 then
				delay 0.5
				keystroke tab
				delay 0.3
				keystroke "a" using {command down}
				delay 0.3
				keystroke tab
				delay 3
				keystroke space
			end if
		end try
		keystroke "w" using {command down}
		delay 2
		click menu item "Quit Mail" of menu 1 of menu bar item "Mail" of menu bar 1
	end tell
end try

(*****************************************************************************************
 * clean up Slack
 ****************************************************************************************)
try
	tell application "Slack" to activate
	delay 0.5

	tell application "System Events"
		tell process "Slack"

			repeat with i from 1 to 9
				keystroke (i as string) using command down
				delay 0.5

				key code 53 using shift down

				delay 0.3
			end repeat

			keystroke "1" using command down
			delay 0.2
			tell application "Slack" to quit

		end tell
	end tell
end try

(*****************************************************************************************
 * clean Xcode
 ****************************************************************************************)
tell application "Xcode" to activate
tell application "System Events" to tell process "Xcode"
	set done to false
	repeat while done = false
		try
			click menu item "Clear Menu" of menu of menu item "Open Recent" of menu of menu bar item "File" of menu bar 1
			set done to true
		end try
	end repeat
end tell

repeat while application "Xcode" is running
	delay 1
	tell application "Xcode" to quit
end repeat
END

osascript <<END2 2>/dev/null 1>&2
(*****************************************************************************************
 * clean up Pastebot
 ****************************************************************************************)
try
	tell application "Pastebot" to quit
	delay 0.1
	tell application "Pastebot" to launch

	tell application "System Events" to tell process "Pastebot"
		set frontmost to true
		try
			delay 0.1
			tell application "Pastebot" to activate
			click menu item "Clear Clipboard" of menu 1 of menu bar item "Edit" of menu bar 1
			delay 0.2
			keystroke tab
			delay 0.1
			keystroke return
		end try
		delay 0.4
		tell application "Pastebot" to activate
		click menu item "Close Window" of menu 1 of menu bar item "File" of menu bar 1
	end tell
end try

(*****************************************************************************************
 * clean up Finder windows
 ****************************************************************************************)
try
	tell application "Finder"
		activate
		repeat with w in (get every Finder window)
			activate w
			tell application "System Events" to tell process "Finder"
				keystroke "a" using {command down}
				delay 0.5
				key code 123
				keystroke "a" using {command down, option down}
				delay 0.5
			end tell
		end repeat

		set desktopBounds to bounds of window of desktop
		set w to round (((item 3 of desktopBounds) - 1100) / 2) rounding as taught in school
		set h to round (((item 4 of desktopBounds) - 1000) / 2) rounding as taught in school
		set finderBounds to {w, h, 1100 + w, 1000 + h}

		try
			set (bounds of window 1) to finderBounds
		on error
			make new Finder window to home
		end try
		set (bounds of window 1) to finderBounds
		close every window

		tell application "System Events" to tell process "Finder"
			click menu item "Clear Menu" of menu of menu item "Recent Items" of menu of menu bar item 1 of menu bar 1
			click menu item "Clear Menu" of menu of menu item "Recent Folders" of menu of menu bar item "Go" of menu bar 1
		end tell
	end tell
end try

(*****************************************************************************************
 * clean up DerivedData
 ****************************************************************************************)
set p to (system attribute "HOME" as string) & "/Library/Developer/Xcode/DerivedData"
try
	tell application "Finder" to delete ((POSIX file p) as alias)
	tell application "Finder" to empty trash
end try
tell application "System Events"
	set activeApp to name of first application process whose frontmost is true as string
	do shell script "Killall " & quoted form of activeApp
end tell
END2

#*****************************************************************************************
# clear the icon cache
#*****************************************************************************************
sudo find /private/var/folders/ \( -name com.apple.dock.iconcache -or -name com.apple.iconservices \) -exec rm -rfv {} \; &>/dev/null
sudo touch /Applications/* &>/dev/null

find "$HOME/Library/Application Support/com.stclairsoft.DefaultFolderX5/Default Set" ! -name "DefaultFolders.plist" -delete &>/dev/null

rm -rf "$HOME/Movies/Motion Templates" &>/dev/null
rm -f "$error_log"
sudo find /private/ -type d -name "org.llvm*" -exec rm -rf {} \; &>/dev/null
sudo find /private/ -type d -name "com.apple.dt.Xcode" -exec rm -rf {} \; &>/dev/null

#*****************************************************************************************
# keep permissions in the /Applications folder good
#*****************************************************************************************
sudo chmod -R 775 /Applications/* &>/dev/null
sudo chown -R root:admin /Applications/* &>/dev/null
sudo xattr -cr /Applications/* &>/dev/null

CACHE="$(getconf DARWIN_USER_CACHE_DIR)"
sudo rm -rf "${CACHE}com.apple.DeveloperTools" &>/dev/null
sudo rm -rf "${CACHE}org.llvm.clang.$(whoami)/ModuleCache" &>/dev/null
sudo rm -rf "${CACHE}org.llvm.clang/ModuleCache" &>/dev/null
sudo find "$HOME/Library/Caches" -type d -name "com.apple.dt.*" -exec rm -rf {} \; &>/dev/null

DTMP=$(getconf DARWIN_USER_TEMP_DIR)
sudo find "$DTMP" -name "*.swift" -exec rm -rfv {} \; &>/dev/null
sudo find "$DTMP" -name "ibtool*" -exec rm -rfv {} \; &>/dev/null
sudo find "$DTMP" -name "*IBTOOLD*" -exec rm -rfv {} \; &>/dev/null
sudo find "$DTMP" -name "sources-*" -exec rm -rfv {} \; &>/dev/null
sudo find "$DTMP" -name "com.apple.test.*" -exec rm -rfv {} \; &>/dev/null

rm -rf "${DTMP}xcrun_db" &>/dev/null
/Applications/Xcode.app/Contents/Developer/usr/bin/simctl --set previews delete all &>/dev/null

printf "\ec\e[3J"
dscacheutil -flushcache &>/dev/null
sudo /usr/libexec/xpchelper --rebuild-cache &>/dev/null
sudo update_dyld_shared_cache -force &>/dev/null
sudo purge &>/dev/null

killall "Crash Reporter" ReportCrash &>/dev/null

find "$HOME/Library/Developer" -type d -name "[A-Za-z0-9]* Device Logs" -exec rm -rfv {} \; &>/dev/null
while IFS= read -r envelope; do
	sqlite3 "$envelope" vacuum
done < <(find "$HOME/Library/Mail" -name "Envelope Index" 2>/dev/null)
sudo diskutil resetUserPermissions / "$(id -u)" &>/dev/null
#*****************************************************************************************
#  refresh Safari icons
#*****************************************************************************************
safari-restore-icons.sh &>/dev/null

#*****************************************************************************************
# clean the font cache
#*****************************************************************************************
if [[ $OCD_OPTION == "restart" ]] || [[ $OCD_OPTION == "off" ]]; then
	sudo atsutil databases -remove &>/dev/null
	atsutil server -shutdown &>/dev/null
	atsutil server -ping &>/dev/null
fi

cat <<"XCODE_BREAKPOINTS" >"$HOME/Library/Developer/Xcode/UserData/xcdebugger/Breakpoints_v2.xcbkptlist"
<?xml version="1.0" encoding="UTF-8"?>
<Bucket
   uuid = "UserGlobalBreakpointBucket"
   type = "2"
   version = "2.0">
   <Breakpoints>
      <BreakpointProxy
         BreakpointExtensionID = "Xcode.Breakpoint.SymbolicBreakpoint">
         <BreakpointContent
            uuid = "E29DF884-B98D-4E34-B697-EB011F81DBA2"
            shouldBeEnabled = "No"
            nameForDebugger = "AutolayoutBreakpoint"
            ignoreCount = "0"
            continueAfterRunningActions = "Yes"
            symbolName = "UIViewAlertForUnsatisfiableConstraints"
            moduleName = "">
            <Actions>
               <BreakpointActionProxy
                  ActionExtensionID = "Xcode.BreakpointAction.ShellCommand">
                  <ActionContent
                     command = "/opt/bin/geedbla/wtf-autolayout.py"
                     arguments = "@(NSString *)[(id)$arg2 description]@"
                     waitUntilDone = "NO">
                  </ActionContent>
               </BreakpointActionProxy>
            </Actions>
            <Locations>
            </Locations>
         </BreakpointContent>
      </BreakpointProxy>
      <BreakpointProxy
         BreakpointExtensionID = "Xcode.Breakpoint.SwiftErrorBreakpoint">
         <BreakpointContent
            uuid = "D00820A6-4EEF-469A-AAA1-32E5314B9C3A"
            shouldBeEnabled = "No"
            ignoreCount = "0"
            continueAfterRunningActions = "No">
         </BreakpointContent>
      </BreakpointProxy>
   </Breakpoints>
</Bucket>
XCODE_BREAKPOINTS

[[ -n ${HISTFILE:-} ]] && rm -f "$HISTFILE" &>/dev/null
[[ -n ${XDG_CACHE_HOME:-} ]] && mkdir -p "$XDG_CACHE_HOME/zsh"
history -c 2>/dev/null

if [[ $OCD_OPTION == "" ]]; then
	finish
	perl /opt/geedbla/scripts/startup-banner.pl --dark
	osascript <<"END2" &>/dev/null
try
    tell application "Keyboard Maestro Engine" to launch
    try
		repeat while application "Keyboard Maestro Engine"  is not running
			delay 0.01
		end repeat
	end try
    tell application "Keyboard Maestro Engine" to activate
	tell application "System Events" to tell process "Keyboard Maestro"
			click menu item "Close" of menu 1 of menu bar item "File" of menu bar 1
	end tell
end try

set volume output volume 40 with output muted --100%
set volume without output muted

(*****************************************************************************************
 * clean up desktop selection
 ****************************************************************************************)
tell application "System Events"
    tell application "Spotlight" to activate
    click group 1 of scroll area 1 of application process "Finder"
end tell
END2
else
	#*****************************************************************************************
	# Prepare for shutdown or restart
	#*****************************************************************************************
	nohup osascript <<"SHUTDOWN" >/dev/null 2>&1 &
tell application "System Events"
	set terminals to {"ghostty", "Terminal"}
	repeat with processName in terminals
		try
			do shell script "killall " & quoted form of processName
			delay 0.2
		end try
	end repeat
	if (system attribute "OCD_OPTION" as string) is equal to "off" then
		tell application "System Events" to shut down
	else
		tell application "System Events" to restart
	end if
end tell
SHUTDOWN
	disown
	exit 0

fi
