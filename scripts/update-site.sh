#!/usr/bin/env zsh
#*****************************************************************************************
# update-site.sh
#
# This script will update my Gee Dbl A website/blog
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Jan-2025 10:08pm
# Modified :
#
# Copyright © 2024 By Gary Ash All rights reserved.
#*****************************************************************************************

read -s "?Password: " password
echo

if [[ -n $password ]]; then
	cd ~/Sites/geedbla.com || return

	if jekyll build >/dev/null; then
		sshpass -p "$password" rsync -arz --exclude=".gitkeep" "$HOME/Sites/geedbla.com/_site/" "$USER@geedbla.com:~/geedbla.com"
		rm -rf "$HOME/Sites/geedbla.com/_site"
		rm -rf "$HOME/Sites/geedbla.com/.jekyll-cache"
		rm -rf "$HOME/Sites/geedbla.com/.jekyll-metadata"
	else
		echo "Error building the site"
	fi
fi
