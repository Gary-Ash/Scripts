#!/usr/bin/env zsh
#*****************************************************************************************
# update-site.sh
#
# This script will update my Gee Dbl A website/blog
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   2-Mar-2024  7:50pm
# Modified :   5-Mar-2024  8:41pm
#
# Copyright © 2024 By Gee Dbl A All rights reserved.
#*****************************************************************************************

read -s "?Paaaword: " password
echo

if [[ -n $password ]]; then
	cd ~/Sites/geedbla || return

	if jekyll build >/dev/null; then
		sshpass -p "$password" rsync -arz --exclude=".gitkeep" "$HOME/Sites/geedbla/_site/" "$USER@geedbla.com:~/geedbla.com"
		rm -rf "$HOME/Sites/geedbla/_site"
		rm -rf "$HOME/Sites/geedbla/.jekyll-cache"
		rm -rf "$HOME/Sites/geedbla/.jekyll-metadata"
	else
		echo "Error building the site"
	fi
fi
