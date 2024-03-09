#!/usr/bin/env zsh
#*****************************************************************************************
# git-rebase-mine-to.sh
#
# This file contains the implementation of a few handy git utilities
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  24-Dec-2023  1:20pm
# Modified :  26-Dec-2023 12:51pm
#
# Copyright © 2023 By Gee Dbl A All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# merge/rebase my branch onto the given branch
#*****************************************************************************************
git-rebase-mine-to() {
	if [ -n "$1" ]; then
		branchTo="$1"
		currentBranch="$(git rev-parse --abbrev-ref HEAD)"
		git checkout $branchTo
		git merge --no-ff $currentBranch
		git checkout $currentBranch
		git rebase $BranchTo
	else
		echo "Usage: merge_rebase_to [branch]"
	fi
}
