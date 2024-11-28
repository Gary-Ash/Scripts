#!/usr/bin/env zsh
#*****************************************************************************************
# git-rebase-mine-to.sh
#
# This file contains the implementation of a few handy git utilities
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-May-2025  3:22pm
# Modified :
#
# Copyright © 2024 By Gary Ash All rights reserved.
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
