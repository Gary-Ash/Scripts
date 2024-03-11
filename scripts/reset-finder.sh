#!/usr/bin/env zsh
#*****************************************************************************************
# reset-finder.sh
#
# reset Finder settings
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  10-Mar-2024  1:18pm
# Modified :  10-Mar-2024  1:21pm
#
# Copyright © 2024 By Gee Dbl A All rights reserved.
#***************************************************************************************** 
reset-finder() {
  defaults delete com.apple.finder
 
  defaults write com.apple.finder NewWindowTarget -string "PfHm"
  defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}"
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  defaults write com.apple.finder ShowStatusBar -bool true
  defaults write com.apple.finder ShowRecentTags -bool false
 
  defaults write com.apple.finder _FXSortFoldersFirst -bool true
  defaults write com.apple.finder _FXSortFoldersFirstOnDesktop -bool true
  defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
  killall Finder
}
