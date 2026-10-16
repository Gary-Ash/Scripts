#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# update-ai-tools.sh
#
# This script pushes my Claude Code configuration and skills to my AI-Tools repository
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  15-Oct-2026  9:55pm
# Modified :  15-Oct-2026 10:21pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# global variables
#*****************************************************************************************
readonly CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
readonly AI_TOOLS_REPO="${AI_TOOLS_REPO:-git@github.com:Gary-Ash/AI-Tools.git}"
readonly AI_TOOLS_DIR="${AI_TOOLS_DIR:-$HOME/Downloads/AI-Tools}"

readonly CONFIG_FILES=(
	"CLAUDE.md"
	"statusline.pl"
)

readonly SKILLS=(
	"applescript-skill"
	"bash-skill"
	"cpp-skill"
	"file-header-skill"
	"git-commit-skill"
	"perl-skill"
	"python3-skill"
	"tdd-skill"
)

#****************************************************************************************
# copy the configuration from ~/.claude into the repository working copy
#****************************************************************************************
buildRepository() {
	for config_file in "${CONFIG_FILES[@]}"; do
		cp -f "$CLAUDE_DIR/$config_file" "$AI_TOOLS_DIR/$config_file"
	done

	mkdir -p "$AI_TOOLS_DIR/skills"
	for skill in "${SKILLS[@]}"; do
		if [[ -d "$CLAUDE_DIR/skills/$skill" ]]; then
			rsync -ac --delete --exclude=.DS_Store "$CLAUDE_DIR/skills/$skill" "$AI_TOOLS_DIR/skills/"
		fi
	done
}

#****************************************************************************************
# make a fresh clone of my AI-Tools repository and copy the configuration into it
#****************************************************************************************
packageRepository() {
	# clone into a staging directory first — the existing working copy is only
	# removed once there is a complete replacement ready to take its place
	local -r staging="$AI_TOOLS_DIR.staging"

	rm -rf "$staging"

	if ! git clone --quiet "$AI_TOOLS_REPO" "$staging"; then
		echo "Unable to clone the repository, the existing one is untouched" >&2
		rm -rf "$staging"
		return 1
	fi

	rm -rf "$AI_TOOLS_DIR"
	mv "$staging" "$AI_TOOLS_DIR"

	buildRepository
}

#****************************************************************************************
# this function will update my AI-Tools repository on GitHub
#****************************************************************************************
updateGitHub() {
	packageRepository

	git -C "$AI_TOOLS_DIR" add -A

	if git -C "$AI_TOOLS_DIR" diff --cached --quiet; then
		echo "AI-Tools is already up to date"
		return
	fi

	# git aborts the commit itself when the message comes back empty
	if ! GIT_EDITOR="$EDITOR" git -C "$AI_TOOLS_DIR" commit --quiet; then
		echo "No commit message given, nothing was pushed" >&2
		return 1
	fi

	git -C "$AI_TOOLS_DIR" push --quiet
}

#*****************************************************************************************
# script main line
#*****************************************************************************************
if [[ $# -gt 0 ]]; then
	case $1 in
		-h | --help)
			cat <<-EOF
				=================================================
				 Update AI-Tools repo on GitHub
				=================================================
				   update-ai-tools.sh --help for this help message
				   update-ai-tools.sh --package build the GitHub update without pushing it
			EOF
			exit 0
			;;

		-p | --package)
			packageRepository
			;;

		*)
			echo "Unknown option -- $1" >&2
			exit 1
			;;
	esac
else
	updateGitHub
fi
