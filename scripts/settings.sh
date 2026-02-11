#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# settings.sh
#
# Automate the some basic settings and software installation on macOS
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :  12-Feb-2026  4:00pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder AppleShowAllFiles true
defaults write com.apple.finder ShowStatusBar -bool true

defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 3
defaults write NSGlobalDomain com.apple.springing.enabled -bool true
defaults write NSGlobalDomain com.apple.springing.delay -float 0

defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain KeyRepeat -int 1
defaults write NSGlobalDomain InitialKeyRepeat -int 10
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist

defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true

defaults write com.apple.systempreferences NSQuitAlwaysKeepsWindows -bool false
defaults write com.apple.cups "Quit When Finished" -bool true

defaults write com.apple.dt.xcode AppleICUDateFormatStrings '{ 1 = "d-MMM-y"; }'
defaults write com.apple.dt.xcode AppleICUTimeFormatStrings '{ 1 = "h:mma"; }'
defaults write com.apple.dt.Xcode IDEAdditionalCounterpartSuffixes -array-add "ViewModel" "View" "Screen"

cd ~/Library/Developer/CoreSimulator/Devices || exit 1
find . -name com.apple.suggestions.plist -exec plutil -replace SuggestionsAppLibraryEnabled -bool NO {} ";"

defaults write com.apple.Safari ShowFavoritesBar -bool false
defaults write com.apple.Safari ShowSidebarInTopSites -bool false
defaults write com.apple.Safari WebKitMediaPlaybackAllowsInline -bool false
defaults write com.apple.SafariTechnologyPreview WebKitMediaPlaybackAllowsInline -bool false
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false
defaults write com.apple.SafariTechnologyPreview com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false

if [[ -f "$HOME/Documents/GeeDblA/Resources/Apple/SystemCodeSnippets.codesnippets" ]]; then
	cp -f "$HOME/Documents/GeeDblA/Resources/Apple/SystemCodeSnippets.codesnippets" "/Applications/Xcode.app/Contents/PlugIns/IDESourceEditor.framework/Versions/A/Resources/"
fi

sudo /usr/sbin/DevToolsSecurity -enable
