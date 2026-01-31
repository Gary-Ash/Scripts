#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# git-rebase-mine-to.sh
#
# This file contains the implementation of a few handy git utilities
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

if [ -n "$1" ]; then
	branchTo="$1"
	currentBranch="$(git rev-parse --abbrev-ref HEAD)"
	git checkout "${branchTo}"
	git merge --no-ff "${currentBranch}"
	git checkout "${currentBranch}"
	git rebase "${branchTo}"
else
	echo "Usage: merge_rebase_to [branch]"
fi
