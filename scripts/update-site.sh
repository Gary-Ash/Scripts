#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# update-site.sh
#
# This script will update my Gee Dbl A website/blog
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

password="$(security find-internet-password -ws geedbla.com)"

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
