#!/usr/bin/env zsh
#*****************************************************************************************
# update-dots.sh
#
# This script automates the maintenance of my dot files repository
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   4-Aug-2025  4:29pm
# Modified :  25-Oct-2025 11:04pm
#
# Copyright © 2025 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# global variables
#*****************************************************************************************
preference_files=(
	"com.apple.dt.Xcode.plist"
	"com.apple.applescript.plist"
	"com.apple.Terminal.plist"
)

#****************************************************************************************
# this function will update my dot files repository on GitHub
#****************************************************************************************
updateGitHub() {
	if [[ -d "$HOME/Downloads/dotfiles/" ]]; then
		rm -rf "$HOME/Downloads/dotfiles/"
	fi

	if git clone --quiet --recurse-submodules git@github.com:Gary-Ash/dot-files.git "$HOME/Downloads/dotfiles/"; then
		cd "$HOME/Downloads/dotfiles/" || return 1
		git submodule update --recursive --remote

		read -rs "?Enter the password to decrypt the repository: " password
		transcrypt -c aes-256-cbc -p "$password"
		buildRepository
	else
		echo "Unable to update the repository"
	fi
}

#****************************************************************************************
# build GitHub repository package
#****************************************************************************************
buildRepository() {
	directories=(
		"$HOME/Downloads/dotfiles/home"
		"$HOME/Downloads/dotfiles/xcode"
		"$HOME/Downloads/dotfiles/brew"
		"$HOME/Downloads/dotfiles/preferences"
		"$HOME/Downloads/dotfiles/shortcuts"
	)

	for direct in "${directories[@]}"; do
		mkdir -p "$direct"
	done

	dot-files "$HOME/Downloads/dotfiles/home" "*"
	rsync -arz -E --exclude="UserData/IB Support" \
		--exclude="UserData/Capabilities" \
		--exclude="UserData/Portal" \
		--exclude="UserData/Previews" \
		--exclude="UserData/XcodeCloud" \
		--exclude="UserData\CodingAssistant" \
		--exclude="UserData/Provisioning Profiles" \
		--exclude="UserData/IDEEditorInteractivityHistory" \
		--exclude="UserData/rovisioning Profiles/" \
		--exclude="UserData/IDEFindNavigatorScopes.plist" \
		--exclude="/Products" \
		--exclude="/XCPGDevices" \
		--exclude="/XCTestDevices" \
		--exclude="/* DeviceSupport" \
		--exclude="/* Device Logs" \
		--exclude="/DeviceLogs" \
		--exclude="/DerivedData" \
		--exclude="/DocumentationIndex" \
		--exclude="/DocumentationCache" \
		"$HOME/Library/Developer/Xcode/" "$HOME/Downloads/dotfiles/xcode/" &>/dev/null >/dev/null

	rsync -arz -E --exclude="Index" \
		--exclude="Cache" \
		--exclude="Installed Packages" \
		--exclude="Lib" \
		--exclude="Log" \
		--exclude="Packages" \
		--exclude="Trash" \
		--exclude="Backup" \
		--exclude="Local/Backup Session.sublime_session" \
		--exclude="Local/Auto Save Session.sublime_session" \
		--exclude="Local/Session.sublime_session" \
		"$HOME/Library/Application Support/Sublime Text" "$HOME/Downloads/dotfiles" &>/dev/null >/dev/null

	rsync -arz -E --exclude="Package Control.cache" \
		--exclude="oscrypto-ca-bundle.crt" \
		--exclude="Package Control.last-run" \
		--exclude="*-ca-bundle" \
		--exclude="sublime_geedbla_environment.txt" \
		"$HOME/Library/Application Support/Sublime Text/Packages/User" "$HOME/Downloads/dotfiles/Sublime Text/Packages" &>/dev/null >/dev/null

	rsync -arz -E --exclude="*.pdf" "$HOME/Library/Application Support/BBEdit" "$HOME/Downloads/dotfiles" &>/dev/null

	rsync -arz -E --exclude="Lib" \
		--exclude="Index" \
		--exclude="Log" \
		--exclude="Cache" \
		--exclude="Installed Packages" \
		--exclude="User/oscrypto-ca-bundle.crt" \
		--exclude="Local/Session.sublime_session" \
		--delete \
		"$HOME/Library/Application Support/Sublime Merge" "$HOME/Downloads/dotfiles" &>/dev/null >/dev/null

	for preference_file in "${preference_files[@]}"; do
		rsync -arz -E "$HOME/Library/Preferences/$preference_file" "$HOME/Downloads/dotfiles/preferences" &>/dev/null >/dev/null
	done

	mkdir -p "$HOME/Downloads/package-temp" || return
	pushd "$HOME/Downloads/package-temp" || return
	brew bundle dump --force &>/dev/null >/dev/null
	gem list --no-version >gems.txt
	for p in $(pip3 list --format freeze); do
		p=${p%%=*}
		echo "$p" >>python-packages.txt
	done
	popd || return
	find "$HOME/Downloads/dotfiles" -type f -name "*.zwc" -delete

	files=($(find ~/Downloads/package-temp -type f))
	for file in "${files[@]}"; do
		name=$(basename "$file")
		name=$(echo "$HOME/Downloads/dotfiles/brew/$name")
		if [[ -f $name ]]; then
			diff -w "$name" "$file" &>/dev/null >/dev/null
			if [ $? -eq 1 ]; then
				mv -f "$file" "$name"
			fi
		else
			mv -f "$file" "$name"
		fi
	done

	cp -f /opt/geedbla/scripts/bootstrap.sh "$HOME/Downloads/dotfiles"
	rm -rf "$HOME/Downloads/package-temp"
	find "$HOME/Downloads/dotfiles" -type d -empty -not -path "./.git/*" -exec touch {}/.gitkeep \;
	exit 0
}

#*****************************************************************************************
# this subroutine will process the "." files in a configuration files
#*****************************************************************************************
dot-files() {
	local cmd
	local line
	local index
	local basecmd
	local rawdotfiles
	local ignore_these=(
		"$HOME/.config/z"
		"$HOME/.claude/projects/"
		"$HOME/.config/zsh/.zsh_history"
		"$HOME/.config/zsh/zcompdump*"
		"$HOME/.config/github-copilot"
		"$HOME/.config/thefuck/__pycache__"
		"$HOME/.config/iterm2"
		"$HOME/.config/.swiftpm"
		"$HOME/.dropbox"
		"$HOME/.hawtjni"
		"$HOME/.gem"
		"$HOME/.android"
		"$HOME/.bundle"
		"$HOME/.bash_history"
		"$HOME/.cocoapods"
		"$HOME/.CFUserTextEncoding"
		"$HOME/.cups"
		"$HOME/.cache"
		"$HOME/.DS_Store"
		"$HOME/.Trash"
		"$HOME/.konan"
		"$HOME/.local"
		"$HOME/.swiftpm"
		"$HOME/.gradle"
		"$HOME/.proxyman"
		"$HOME/.proxyman-data"
	)

	rawdotfiles=$(find "$HOME" -maxdepth 1 -name ".*")
	while IFS= read -r line; do
		dotfiles+=("$line")
	done < <(echo "${rawdotfiles}")

	for exclude in "${ignore_these[@]}"; do
		index=1
		for dotfile in "${dotfiles[@]}"; do
			if [[ $dotfile == "$exclude" ]]; then
				unset "dotfiles[$index]"
				break
			fi
			((++index))
		done
	done

	if [[ -z $2 ]]; then
		echo "${dotfiles[@]}"
		return
	else
		if [[ $2 == "sshpass" ]]; then
			basecmd="sshpass -p ${password} rsync -az "
			1="$USER@$computer:$HOME/"
		else
			basecmd="rsync -az "
		fi
	fi
	for exclude in "${ignore_these[@]}"; do
		basecmd+="--exclude=\"$(basename $exclude)\" "
	done
	for dotfile in "${dotfiles[@]}"; do
		if [[ -n $dotfile ]]; then
			cmd="$basecmd\"$dotfile\" \"$1\""
			eval "$cmd"
		fi
	done

	if [[ -z $2 ]]; then
		mkdir -p "$HOME/Downloads/dotfiles/home/.config/zsh"
		touch "$HOME/Downloads/dotfiles/home/.config/zsh/.gitkeep"
	fi
}

#*****************************************************************************************
# script main line
#*****************************************************************************************
format-project.sh "/opt/geedbla"

if [ $# -gt 0 ]; then
	case $1 in
		-h | --help)
			echo "================================================="
			echo " Update dot file repro on GitHub"
			echo "================================================="
			echo "   update-dots.sh --help for this help message"
			echo "   update-dots.sh --package build the GitHub update without committing it"
			exit 0
			;;

		-p | --package)
			buildRepository
			;;

		-*)
			echo "Unknown option -- $1"
			exit 1
			;;

		*)
			updateGitHub
			exit 0
			;;
	esac
else
	updateGitHub
fi
