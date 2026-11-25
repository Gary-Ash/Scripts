#!/usr/bin/env bash
#*****************************************************************************************
# ocd.sh
#
# Update system software and clean macOS settings
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Sep-2026  4:42pm
# Modified :  25-Nov-2026  4:51pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

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

#*****************************************************************************************
# source in library functions
#*****************************************************************************************
source "/opt/geedbla/lib/shell/lib/get_sudo_password.sh"
source "/opt/geedbla/lib/shell/lib/claude-scrub.sh"

#*****************************************************************************************
# globals
#*****************************************************************************************
export SUDO_PASSWORD
SUDO_SHELL_PID=""
CAFFEINATE=""
SAFARI_PREFS="$HOME/Library/Containers/com.apple.Safari/Data/Library/Preferences/com.apple.Safari"

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
	defaults write "$SAFARI_PREFS" AllowJavaScriptFromAppleEvents -bool false 2>/dev/null
	wait 2>/dev/null
	unset SUDO_SHELL_PID
	unset CAFFEINATE
	unset SUDO_PASSWORD

	if [[ -n $ZSH_VERSION ]]; then
		setopt monitor
	fi
}

#*****************************************************************************************
# keep the Mac awake for the whole run, and log the update commands' output to a file
# outside $TMPDIR, which the cleanup below empties
#*****************************************************************************************
caffeinate -i -s -w $$ &>/dev/null &
CAFFEINATE=$!

error_log="$HOME/Library/Logs/ocd.log"
: >"$error_log"

#*****************************************************************************************
# kill applications
#*****************************************************************************************
killEverything() {
	osascript <<"CLOSE_SCRIPT" &>/dev/null
set backgroundsToKill to ¬
	{	"Safari", ¬
		"Moom", ¬
		"SnippetsLab", ¬
		"Slack", ¬
		"Mona", ¬
		"Pastebot", ¬
		"Alfred 6"}

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

	# AirBuddyHelper answers quit with a confirmation dialog, and launchd relaunches it
	# after a signal, so unload its launch agent
	launchctl bootout "gui/$(id -u)/codes.rambo.AirBuddy.AirBuddyHelper" &>/dev/null || true
}

#*****************************************************************************************
# delete all YouTube history through Google My Activity in Safari - Safari's "Allow
# JavaScript from Apple Events" is on only while this runs (finish also turns it off)
#*****************************************************************************************
cleanYouTubeHistory() {
	defaults write "$SAFARI_PREFS" AllowJavaScriptFromAppleEvents -bool true
	osascript <<"YOUTUBE_SCRIPT" &>/dev/null
property historyURL : "https://myactivity.google.com/product/youtube"
property timeoutSeconds : 30

on run
	my ensureSafariRunning()
	tell application "Safari"
		if (count of windows) = 0 then
			make new document with properties {URL:historyURL}
			set historyTab to current tab of front window
		else
			set historyTab to make new tab at end of tabs of front window with properties {URL:historyURL}
			set current tab of front window to historyTab
		end if
	end tell

	try
		my cleanHistory(historyTab)
	on error errMsg number errNum
		my closeTab(historyTab)
		error errMsg number errNum
	end try
	my closeTab(historyTab)
end run

on ensureSafariRunning()
	if application "Safari" is running then return
	tell application "Safari" to launch
	repeat (timeoutSeconds * 2) times
		if application "Safari" is running then return
		delay 0.5
	end repeat
	error "Timed out waiting for Safari to start."
end ensureSafariRunning

on cleanHistory(historyTab)
	my waitFor(historyTab, "String(location.href !== 'about:blank' && document.readyState === 'complete')", "the page to load")
	if my onSignInPage(historyTab) then error "Safari is not signed in to Google."

	my waitForHistoryList(historyTab)
	if my itemCount(historyTab) = 0 then return

	my runJS(historyTab, "document.querySelector('button[jsname=PltDuc]').click()")
	my waitFor(historyTab, "String(!!document.querySelector('li[jsname=KKr5ne]')?.getClientRects().length)", "the Delete all time menu item")
	my runJS(historyTab, "document.querySelector('li[jsname=KKr5ne]').click()")
	my waitFor(historyTab, "String(!!document.querySelector('[jsname=rkUhV] button[jsname=nUV0Pd]')?.getClientRects().length)", "the confirmation dialog")
	my runJS(historyTab, "document.querySelector('[jsname=rkUhV] button[jsname=nUV0Pd]').click()")
	-- reloading while the delete request is in flight could cancel it, so wait for the dialog to go first
	my waitFor(historyTab, "String(!document.querySelector('[jsname=rkUhV] button[jsname=nUV0Pd]')?.getClientRects().length)", "the confirmation dialog to close")
	delay 2

	-- the sentinel disappears only once the reloaded page replaces this one
	my runJS(historyTab, "window.ytCleanerSentinel = true; location.reload()")
	my waitFor(historyTab, "String(!window.ytCleanerSentinel && document.readyState === 'complete')", "the page to reload")
	if my onSignInPage(historyTab) then error "Google asked to verify the account after Delete; history may not be deleted."
	my waitForHistoryList(historyTab)

	set remaining to my itemCount(historyTab)
	if remaining > 0 then error "History still shows " & remaining & " items after Delete."
end cleanHistory

on waitForHistoryList(historyTab)
	my waitFor(historyTab, "String(!!document.querySelector('button[jsname=PltDuc]'))", "the DELETE button")
	-- activity items render after the toolbar
	delay 2
end waitForHistoryList

on onSignInPage(historyTab)
	tell application "Safari" to set pageURL to URL of historyTab
	return pageURL contains "accounts.google.com"
end onSignInPage

on itemCount(historyTab)
	return (my runJS(historyTab, "String(document.querySelectorAll(\"button[aria-label^='Delete activity item']\").length)")) as integer
end itemCount

on waitFor(historyTab, condition, description)
	repeat (timeoutSeconds * 2) times
		if my runJS(historyTab, condition) is "true" then return
		delay 0.5
	end repeat
	error "Timed out waiting for " & description & "."
end waitFor

-- do JavaScript fails or returns missing value while a page is navigating; treat that as "not yet"
on runJS(historyTab, js)
	try
		tell application "Safari" to set jsResult to do JavaScript js in historyTab
		if jsResult is missing value then return ""
		return jsResult as text
	on error
		return ""
	end try
end runJS

on closeTab(historyTab)
	try
		tell application "Safari" to close historyTab
	end try
end closeTab
YOUTUBE_SCRIPT
	defaults write "$SAFARI_PREFS" AllowJavaScriptFromAppleEvents -bool false
}

#-----------------------------------------------------------------------------------------
# SCRIPT MAIN LINE
#-----------------------------------------------------------------------------------------

#*****************************************************************************************
# must run before killEverything quits Safari and safari-cleaner.py trims its cookies
#*****************************************************************************************
cleanYouTubeHistory
killEverything

#*****************************************************************************************
# clear the pasteboard
#*****************************************************************************************
echo -n '' | pbcopy

#*****************************************************************************************
# brew
#*****************************************************************************************
if command -v brew &>/dev/null; then
	brew update &>>"$error_log"
	brew upgrade &>>"$error_log"
	brew upgrade --cask &>>"$error_log"
	brew autoremove &>>"$error_log"
	brew cleanup &>>"$error_log"
	rm -rf "$(brew --cache)" &>/dev/null
fi

#*****************************************************************************************
# Update Github gh extensions
#*****************************************************************************************
if command -v gh &>/dev/null; then
	gh extension upgrade --all &>>"$error_log"
fi

#*********************************************************************************
# ruby update
#*********************************************************************************
if command -v gem &>/dev/null; then
	gem update &>>"$error_log"
	gem cleanup &>>"$error_log"
fi

#*********************************************************************************
# python 3 update
#*********************************************************************************
if command -v pip3 &>/dev/null; then
	python3 -m pip install --upgrade pip &>>"$error_log"
	{ pip3 freeze | cut -d = -f 1 | xargs pip3 install -U; } &>>"$error_log"
	pip3 cache purge &>>"$error_log"
fi

#*****************************************************************************************
# npm update
#*****************************************************************************************
if command -v npm &>/dev/null; then
	npm install -g npm@latest &>>"$error_log"
	npm cache clean --force &>>"$error_log"
fi
#*****************************************************************************************
pkill -f '.*GradleDaemon.*'
killall "Crash Reporter" ReportCrash &>/dev/null

qlmanage -r &>/dev/null

find "$HOME" -name "Icon?" -exec chflags hidden {} \; &>/dev/null
#*****************************************************************************************
# clean my git projects and developer areas
#*****************************************************************************************
while IFS= read -r gitDir; do
	[[ -z $gitDir ]] && continue
	cd "$(dirname "$gitDir")" || exit 1
	git gc --aggressive --prune=now &>/dev/null
done < <(find "$HOME/Developer" "$HOME/Documents" -type d -name ".git" 2>/dev/null)

find "$HOME/Developer" -type d -name "*xcuserdatad" ! -name "garyash.xcuserdatad" -exec rm -rf {} \; &>/dev/null
find "$HOME/Documents" -type d -name "*xcuserdatad" ! -name "garyash.xcuserdatad" -exec rm -rf {} \; &>/dev/null
python3 /opt/geedbla/scripts/load-simulator.py &

#*****************************************************************************************
# clean Jekyll website junk
#*****************************************************************************************
find "$HOME/Sites" \( -name "Gemfile.lock" -or -name ".sass-cache" -or -name ".jekyll*" -or -name "_site" -or -name ".jekyll-metadata" \) -exec rm -rfv {} \; &>/dev/null
find "$HOME/Developer" \( -name "Gemfile.lock" -or -name ".sass-cache" -or -name ".jekyll*" -or -name "_site" -or -name ".jekyll-metadata" \) -exec rm -rfv {} \; &>/dev/null

find "$HOME/Library/Application Support/AddressBook" -name "*.abbu.tbz" -delete &>/dev/null
find "/Users/Shared/CleanMyMac_5/" -depth 1 ! -name ".licence" -exec rm -rfv {} \; &>/dev/null

#*****************************************************************************************
# clean and reset Safari
#*****************************************************************************************
python3 /opt/geedbla/scripts/safari-cleaner.py &>/dev/null

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

#*****************************************************************************************
# make sure Applications folder permission and ownership is correct
#*****************************************************************************************
sudo chown -R garyash:admin /opt/geedbla/* &>/dev/null
sudo chown -R root:admin /Applications/* &>/dev/null
sudo chmod -R 775 /Applications/* &>/dev/null

sudo /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -r -domain local -domain system -domain user &>/dev/null

#*****************************************************************************************
# empty trash
#*****************************************************************************************
sudo rm -rf ~/.Trash /Volumes/*/.Trashes &>/dev/null
rm -rf "$HOME/Library/Mobile Documents/com~apple~CloudDocs/.Trash"

#*****************************************************************************************
# sweep .DS_Store files - they record folder contents and window state
#*****************************************************************************************
find "$HOME" -type f -name ".DS_Store" -delete &>/dev/null
sudo find /Applications -type f -name ".DS_Store" -delete &>/dev/null

#*****************************************************************************************
# AI Cleanup (Claude)
#*****************************************************************************************
if jq "$(claude_scrub_filter)" "$HOME/.claude.json" >"$HOME/.claude.json1"; then
	mv -f "$HOME/.claude.json1" "$HOME/.claude.json"
else
	rm -f "$HOME/.claude.json1"
fi
rm -f ~/.claude.json.backup.*

#*****************************************************************************************
# clean up Time Machine local backups and turn it back on
#*****************************************************************************************
if tmutil status | grep -q "Running = 1"; then
	sudo tmutil stopbackup
fi
sudo tmutil thinlocalsnapshots / 100000000000 4 &>/dev/null
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

#*****************************************************************************************
# reset the Mail, Notes, Safari, Calendar and Reminders windows to their defaults - killEverything quit them
#*****************************************************************************************
for domain in com.apple.mail com.apple.Notes com.apple.Safari com.apple.iCal com.apple.reminders; do
	defaults export "$domain" - 2>/dev/null | python3 -c '
import plistlib, re, sys
for key in plistlib.loads(sys.stdin.buffer.read()):
    if re.match(r"NSWindow Frame |NSSplitView Subview Frames |NSToolbar Configuration |NSOutlineView Items |DefaultWindowState$|ColumnConfiguration$", key):
        print(key)
' | while IFS= read -r key; do
		defaults delete "$domain" "$key" 2>/dev/null
	done
	rm -rf "$HOME/Library/Containers/$domain/Data/Library/Saved Application State/"*
done

# the Siri AI agent (com.apple.campo) hosts the Apps.app panel; once moved it reopens at the
# saved spot instead of centered, and launchd relaunches the agent after the kill
defaults delete com.apple.campo userHasMovedWindow 2>/dev/null
defaults delete com.apple.campo lastWindowPosition 2>/dev/null
killall "Siri AI" 2>/dev/null

#*****************************************************************************************
# reset the emoji & symbols picker - Messages (quit above) and the picker must be stopped
# before the deletes, because either one writes its in-memory recents back when it exits
#*****************************************************************************************
killall CharacterPalette EmojiFunctionRowIM 2>/dev/null
# the XPC file-service helper ignores SIGTERM
killall -KILL com.apple.CharacterPicker.FileService 2>/dev/null

defaults delete com.apple.EmojiPreferences 2>/dev/null
defaults delete com.apple.CharacterPicker 2>/dev/null
# StickerKit shares the recents list across apps; the picker reseeds from Messages' copy
defaults delete com.apple.MobileSMS com.apple.StickerKit.DataSourceState.UnifiedRecentImageGlyphDataSource 2>/dev/null
rm -f "$HOME/Library/Containers/com.apple.CharacterPaletteIM/Data/Library/Preferences/com.apple.CharacterPaletteIM.plist"
rm -f "$HOME/Library/Containers/com.apple.CharacterPaletteIM/Data/Library/Preferences/com.apple.EmojiCache.plist"

# cfprefsd caches prefs in memory and would write the old values back
killall -u "$USER" cfprefsd 2>/dev/null

sudo -E /usr/bin/python3 /opt/geedbla/scripts/ocd-cleanup.py "${CLAUDE_JUNK_PATHS[@]}" &>/dev/null

osascript <<END 2>/dev/null 1>&2
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
				delay 0.5
				tell window "Previous Recipients"
					click button "Remove From List"
				end tell
				delay 3
			end if
		end try
		keystroke "w" using {command down}
		delay 2
		try
			click menu item "Hide Sidebar" of menu 1 of menu bar item "View" of menu bar 1
			delay 1
		end try
		click menu item "Quit Mail" of menu 1 of menu bar item "Mail" of menu bar 1
	end tell
end try

(*****************************************************************************************
 * clean up Slack
 ****************************************************************************************)
try
	tell application "System Events"
		tell application "Slack" to activate
		tell process "Slack"
			repeat
				if (count of windows) > 0 then exit repeat
				delay 0.1
			end repeat

			delay 2.5
			tell application "Slack" to activate

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
delay 0.5

tell application "System Events" to tell process "Xcode"
	set done to false
	repeat while done = false
		try
			tell application "Xcode" to activate
			click menu item "Clear Menu" of menu of menu item "Open Recent" of menu of menu bar item "File" of menu bar 1
			set done to true
		end try
	end repeat
end tell

repeat while application "Xcode" is running
	delay 1
	tell application "Xcode" to quit
end repeat

(*****************************************************************************************
 * clean up Pastebot
 ****************************************************************************************)
try
	tell application "Pastebot" to activate
	delay 0.5
	tell application "System Events" to tell process "Pastebot"
		set frontmost to true
		try
			tell application "Pastebot" to activate
			click menu item "Clear Clipboard" of menu 1 of menu bar item "Edit" of menu bar 1
			delay 0.2
			try
				click button "Clear" of sheet 1 of window 1
			on error
				try
					click button "Clear" of window 1
				end try
			end try
			tell application "Pastebot" to quit
		end try
	end tell
end try

(*****************************************************************************************
 * clean up Finder windows
 ****************************************************************************************)
try
	tell application "Finder"
		-- Calculate centered window bounds
		set desktopBounds to bounds of window of desktop

		set windowX to round (((item 3 of desktopBounds) - 1100) / 2) rounding as taught in school
		set windowY to round (((item 4 of desktopBounds) - 1000) / 2) rounding as taught in school

		set finderBounds to {windowX, windowY, windowX + 1100, windowY + 1000}

		-- Snapshot window list before changing z-order
		set windowList to every Finder window

		repeat with aWindow in windowList
			activate

			-- Bring window to the front
			set index of aWindow to 1

			tell application "System Events"
				tell process "Finder"
					-- Select everything
					click menu item "Select All" of menu 1 of menu bar item "Edit" of menu bar 1

					delay 0.2

					-- Collapse all selected folders in list view
					key code 123 -- Left Arrow
				end tell
			end tell

			-- Resize and reposition window
			try
				set bounds of aWindow to finderBounds
			on error
				make new Finder window to home
				set bounds of front Finder window to finderBounds
			end try
		end repeat
	end tell

	-- Deselect All (⌥⌘A)
	tell application "Finder" to activate

	tell application "System Events"
		keystroke "a" using {command down, option down}
	end tell

	delay 0.1

end try

try
	tell application "System Events"
		tell process "Finder"
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
END

#*****************************************************************************************
# reset the iWork template chooser Recents - the list lives in iCloud key-value storage,
# so set the app's one-shot reset flag; it clears when the template chooser next opens
#*****************************************************************************************
for app in Pages Numbers Keynote; do
	defaults write "com.apple.$app" TSAOpenedTemplatesReset -bool YES
done

#*****************************************************************************************
# Notification Center clean up
#*****************************************************************************************
killall NotificationCenter 2>/dev/null
killall ControlCenter 2>/dev/null
killall usernoted 2>/dev/null
defaults delete com.apple.ncprefs 2>/dev/null
sudo find /private/var/folders -name com.apple.notificationcenter -exec rm -rf {} + &>/dev/null

#*****************************************************************************************
# clear the icon cache
#*****************************************************************************************
sudo find /private/var/folders/ \( -name com.apple.dock.iconcache -or -name com.apple.iconservices \) -exec rm -rfv {} \; &>/dev/null
sudo touch /Applications/* &>/dev/null

find "$HOME/Library/Application Support/com.stclairsoft.DefaultFolderX5/Default Set" ! -name "DefaultFolders.plist" -delete &>/dev/null

rm -rf "$HOME/Movies/Motion Templates" &>/dev/null
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

mkdir -p "$HOME/Library/Developer/Xcode/UserData/xcdebugger"
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
                     command = "/opt/geedbla/scripts/wtf-autolayout.py"
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
zoxide add ~/Developer/GeeDblA /opt/geedbla /opt/geedbla/scripts /opt/geedbla/lib

if [[ $OCD_OPTION == "" ]]; then
	finish
	python3 /opt/geedbla/scripts/startup-banner.py --dark
	osascript <<"END2" &>/dev/null
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
