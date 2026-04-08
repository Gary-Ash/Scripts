#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# finder-setup.sh
#
# Set Finder's Downloads folder to list view with specific columns
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   7-Apr-2026  4:00pm
# Modified :   7-Apr-2026  8:36pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
defaults write com.apple.finder StandardViewSettings -dict-add "ListViewSettings" '{
    "columns" = {
        "name" = { "visible" = 1; "width" = 300; };
        "size" = { "visible" = 1; "width" = 100; };
        "kind" = { "visible" = 1; "width" = 150; };
        "dateCreated" = { "visible" = 1; "width" = 150; };
        "dateModified" = { "visible" = 1; "width" = 150; };
        "label" = { "visible" = 0; "width" = 50; };
        "version" = { "visible" = 0; "width" = 50; };
        "comments" = { "visible" = 0; "width" = 50; };
        "dateLastOpened" = { "visible" = 0; "width" = 150; };
        "dateAdded" = { "visible" = 0; "width" = 150; };
    };
}'

defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
defaults write com.apple.finder "ShowStatusBar" -bool true
defaults write NSGlobalDomain "AppleShowAllExtensions" -bool true
defaults write com.apple.finder "AppleShowAllFiles" -bool true
defaults write com.apple.finder "_FXSortFoldersFirst" -bool true
defaults write NSGlobalDomain "NSTableViewDefaultSizeMode" -int 1
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"

find "$HOME" -name ".DS_Store" -type f -delete 2>/dev/null
find "/opt" -name ".DS_Store" -type f -delete 2>/dev/null
find "/usr/local" -name ".DS_Store" -type f -delete 2>/dev/null

# 5. Restart Finder to apply changes
killall Finder
sleep 2

osascript <<'APPLESCRIPT'
tell application "Finder"
    activate
    set downloadsFolder to (path to downloads folder)
    open downloadsFolder
    delay 0.5
    set targetWindow to Finder window 1
    set current view of targetWindow to list view
end tell

tell application "System Events"
    tell process "Finder"
        keystroke "j" using command down
        delay 1.0

        tell group 1 of window 1
            -- Columns to enable
            repeat with colName in {"Size", "Kind", "Date Created", "Date Modified"}
                set cb to checkbox colName
                if value of cb is 0 then click cb
            end repeat

            -- Columns to disable
            repeat with colName in {"Date Added", "Date Last Opened", "iCloud Status", ¬
                "Last Modified By", "Shared By", "Version", "Comments", "Tags"}
                set cb to checkbox colName
                if value of cb is 1 then click cb
            end repeat
        end tell

        keystroke "j" using command down
    end tell
end tell

try
	tell application "Finder"
		set desktopBounds to bounds of window of desktop
		set w to round (((item 3 of desktopBounds) - 1100) / 2) rounding as taught in school
		set h to round (((item 4 of desktopBounds) - 1000) / 2) rounding as taught in school
		set finderBounds to {w, h, 1100 + w, 1000 + h}
	end tell

	tell application "Finder"
		repeat with w in (get every Finder window)
			activate
			activate w
			tell application "System Events" to tell process "Finder"
				click menu item "Select All" of menu 1 of menu bar item "Edit" of menu bar 1
				delay 0.5
				key code 123
				key code 126

				tell application "Finder"
					try
						set (bounds of w) to finderBounds
					on error
						make new Finder window to home
						set (bounds of window w) to finderBounds
					end try
				end tell
			end tell
		end repeat
		set selection to {}
	end tell
end try

try
	tell application "System Events" to tell process "Finder"
		click menu item "Clear Menu" of menu of menu item "Recent Items" of menu of menu bar item 1 of menu bar 1
		click menu item "Clear Menu" of menu of menu item "Recent Folders" of menu of menu bar item "Go" of menu bar 1
	end tell
	tell application "Finder" to close every window
end try
APPLESCRIPT
