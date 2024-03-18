#!/usr/bin/env zsh
#*****************************************************************************************
# sync-macs.sh
#
# This script automates the maintenance of my dot files repository and the syncing of
# my other Mac computers on my network
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  18-Aug-2023  8:10pm
# Modified :  18-Mar-2024  1:02pm
#
# Copyright © 2023-2024 By Gee Dbl A All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# load utilities from scripting libraries
#*****************************************************************************************
autoload get_sudo_password

#*****************************************************************************************
# global variables
#*****************************************************************************************
preference_files=(
	"com.apple.dt.Xcode.plist"
	"com.googlecode.iterm2.plist"
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

	if git clone --quiet --recurse-submodules git@github.com:Gary-Ash/dotfiles.git "$HOME/Downloads/dotfiles/"; then
		cd "$HOME/Downloads/dotfiles/" || return 1

		git-crypt unlock
		buildRepository
	else
		echo "Unable to update the repository"
	fi
}

#****************************************************************************************
# Update my other systems
#****************************************************************************************
sync() {
	local me
	local log="$TMPDIR/error.log"
	local systems=("Garys-Mac-Studio.local" "Garys-MacBook-Pro.local")
	local toSync=(
		"$HOME/Desktop"
		"$HOME/Sites"
		"$HOME/Pictures"
		"$HOME/Documents"
		"$HOME/Developer"
		"/opt/geedbla"
	)

	local apps=(
		"CleanStart.app"
		"XcodeGeeDblA.app"
	)

	me="$(scutil --get LocalHostName).local"
	password=$(get_sudo_password)

	brew bundle dump --brews --casks --taps --force --file="$HOME/Downloads/bundles.txt" &>/dev/null
	for computer in "${systems[@]}"; do
		remote="$USER@$computer"
		if [ "$me" != "$computer" ]; then
			sshpass -p "$password" rsync -arz -E --rsh=ssh "$HOME/Downloads/bundles.txt" "$remote:$HOME/Downloads/bundles.txt" &>/dev/null
			sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S chmod -R 777 /Applications/*" &>/dev/null
			sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";brew bundle --force --no-lock --file=$HOME/Downloads/bundles.txt &> /dev/null" &>/dev/null
			sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";brew bundle cleanup --force --file=$HOME/Downloads/bundles.txt &> /dev/null" &>/dev/null
			sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";brew update &> /dev/null" &>/dev/null
			sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";brew upgrade &> /dev/null" &>/dev/null
			sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";brew autoremove &> /dev/null" &>/dev/null
			sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S chown -R root:wheel /Applications/*" &>/dev/null
			sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S chmod -R 755 /Applications/*" &>/dev/null
			sshpass -p "$password" ssh "$remote" "rm -f \"$HOME/Downloads/bundles.txt\" &> /dev/null" &>/dev/null
			sshpass -p "$password" ssh "$remote" "echo $password | sudo -S rm -rf \"$HOME/Pictures/Photos Library.photoslibrary\" &> /dev/null" &>/dev/null
			sshpass -p "$password" rsync -arz --rsh=ssh "$HOME/Pictures/Photos Library.photoslibrary" "$remote:$HOME/Pictures" &>/dev/null

			localGems=($(gem list --no-versions))
			remoteGems=($(sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";gem list --no-versions"))
			for localGem in ${localGems[@]}; do
				foundIt=0
				for remoteGem in ${remoteGems[@]}; do
					if [[ $localGem == "$remoteGem" ]]; then
						foundIt=1
						break
					fi
				done
				if [[ foundIt -eq 0 ]]; then
					newGems+=("$localGem")
				fi
			done

			for gemToAdd in ${newGems[@]}; do
				sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";gem install \"$gemToAdd\" &> /dev/null"
			done

			removedGems=()
			remoteGems=($(sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";gem list --no-versions"))
			for remoteGem in ${remoteGems[@]}; do
				foundIt=0
				for localGem in ${localGems[@]}; do
					if [[ $localGem == "$remoteGem" ]]; then
						foundIt=1
						break
					fi
				done
				if [[ foundIt -eq 0 ]]; then
					removedGems+=("$remoteGem")
				fi
			done

			for gemToRemove in ${removedGems[@]}; do
				sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";gem uninstall -aIx \"$gemToRemove\" &> /dev/null"
			done

			sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";python3 -m pip install --upgrade pip &> /dev/null"
			for p in $(sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";pip3 list --format=freeze"); do
				p=${p%%=*}
				if [[ $p != "pip" ]]; then
					sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";pip3 install -U \"$p\" &> /dev/null"
				fi
			done

			sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";gem update &> /dev/null"
			sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";gem cleanup &> /dev/null"

			newPip=()
			pipLocals=($(pip3 list --format freeze))
			pipRemotes=($(sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";pip3 list --format freeze"))
			for localPip in ${pipLocals[@]}; do
				foundIt=0
				localPip=${localPip%%=*}

				for remotePip in ${pipRemotes[@]}; do
					remotePip=${remotePip%%=*}
					if [[ $localPip == "$remotePip" ]]; then
						foundIt=1
						break
					fi
				done
				if [[ foundIt -eq 0 ]]; then
					newPip+=("$localPip")
				fi
			done

			for pipToAdd in ${newPip[@]}; do
				sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";pip3 install \"$pipToAdd\" &> /dev/null"
			done

			removedPips=()
			pipRemotes=($(sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";pip3 list --format freeze"))
			for remotePip in ${pipRemotes[@]}; do
				foundIt=0
				remotePip=${remotePip%%=*}

				for localPip in ${pipLocals[@]}; do
					localPip=${localPip%%=*}
					if [[ $localPip == "$remotePip" ]]; then
						foundIt=1
						break
					fi
				done
				if [[ foundIt -eq 0 ]]; then
					removedPips+=("$remotePip")
				fi
			done

			for pipToRemove in ${removedPips[@]}; do
				sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";pip3 uninstall --yes \"$pipToRemove\" &> /dev/null"
			done

			dot-files "" "sshpass"
			for preference_file in "${preference_files[@]}"; do
				sshpass -p "$password" rsync -arz --rsh=ssh "$HOME/Library/Preferences/$preference_file" "$remote:$HOME/Library/Preferences" &>/dev/null
			done

			sshpass -p "$password" rsync -arz --rsh=ssh "$HOME/Library/Containers/com.apple.mail/Data/Library/Preferences/com.apple.mail.plist" \
				"$remote:$HOME/Library/Containers/com.apple.mail/Data/Library/Preferences/com.apple.mail.plist"
			sshpass -p "$password" rsync -arz --rsh=ssh "$HOME/Library/Mail/" \
				"$remote:$HOME/Library/Mail/"

			sshpass -p "$password" rsync -arz -E \
				--exclude="UserData/Capabilities" \
				--exclude="UserData/IB Support" \
				--exclude="UserData/Portal" \
				--exclude="UserData/Previews" \
				--exclude="UserData/XcodeCloud" \
				--exclude="UserData/IDEEditorInteractivityHistory" \
				--exclude="/Products" \
				--exclude="/XCPGDevices" \
				--exclude="/XCTestDevices" \
				--exclude="/* DeviceSupport" \
				--exclude="/* Device Logs" \
				--exclude="/DeviceLogs" \
				--exclude="/DerivedData" \
				--exclude="/DocumentationIndex" \
				--exclude="/DocumentationCache" \
				"$HOME/Library/Developer/Xcode/" "$remote:$HOME/Library/Developer/Xcode/" &>/dev/null

			sshpass -p "$password" rsync -arz -E --rsh=ssh \
				--exclude="Index" \
				--exclude="Local/Session.sublime_session" \
				--exclude="Cache" \
				--exclude="User/oscrypto-ca-bundle.crt" \
				--delete \
				"$HOME/Library/Application Support/Sublime Text" \
				"$remote:$HOME/Library/Application\\ Support/" &>/dev/null

			sshpass -p "$password" rsync -arz -E --rsh=ssh \
				--exclude="Cache" \
				--exclude="User/oscrypto-ca-bundle.crt" \
				--delete \
				"$HOME/Library/Application Support/Sublime Merge" \
				"$remote:$HOME/Library/Application\\ Support/" &>/dev/null

			sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S killall Dock" &>/dev/null
			rm -f "$HOME/Downloads/bundles.txt" &>/dev/null

			sshpass -p "$password" rsync -arzE --rsh ssh "$HOME/Movies" "$remote:$HOME" &>/dev/null

			sshpass -p "$password" ssh "$remote" "rm -f $log" &>/dev/null
			sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";cd ~;rm -rf .gem .DS_Store #  &> /dev/null"
			sshpass -p "$password" ssh "$remote" "find . -name \"Icon?\" -exec chflags hidden {} \; &> /dev/null"

			for anApp in "${apps[@]}"; do
				appToInstall="/Applications/$anApp"
				sshpass -p "$password" rsync -arz -E "$appToInstall" "$remote:$HOME/Downloads"
				if [[ $? -eq 0 ]]; then
					sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S rm -rf $appToInstall" &>/dev/null
					sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S cp -rf $HOME/Downloads/$anApp /Applications" &>/dev/null
					sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S rm -rf $HOME/Downloads/$anApp" &>/dev/null
				fi
			done

			sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S chmod -R 777 /Applications/*" &>/dev/null
			for pathToSync in "${toSync[@]}"; do
				targetDirectory=$(dirname "$pathToSync")
				targetDirectory="${targetDirectory// /\\ }"
				rsync --rsh="sshpass -p $password ssh -l $USER" -arzE --delete "$pathToSync" "$remote:$targetDirectory/" &>/dev/null
			done

			sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S chown -R root:wheel /Applications/*" &>/dev/null
			sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S chmod -R 755 /Applications/*" &>/dev/null
		fi
	done

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
		--exclude="UserData/IDEEditorInteractivityHistory" \
		--exclude="/Products" \
		--exclude="/XCPGDevices" \
		--exclude="/XCTestDevices" \
		--exclude="/* DeviceSupport" \
		--exclude="/* Device Logs" \
		--exclude="/DerivedData" \
		--exclude="/DocumentationIndex" \
		--exclude="/DocumentationCache" \
		"$HOME/Library/Developer/Xcode/" "$HOME/Downloads/dotfiles/xcode/" &>/dev/null

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
		"$HOME/Library/Application Support/Sublime Text" "$HOME/Downloads/dotfiles" &>/dev/null

	rsync -arz -E --exclude="Package Control.cache" \
		--exclude="oscrypto-ca-bundle.crt" \
		--exclude="Package Control.last-run" \
		--exclude="*-ca-bundle" \
		--exclude="sublime_geedbla_environment.txt" \
		"$HOME/Library/Application Support/Sublime Text/Packages/User" "$HOME/Downloads/dotfiles/Sublime Text/Packages" &>/dev/null

	rsync -arz -E --exclude="Lib" \
		--exclude="Index" \
		--exclude="Log" \
		--exclude="Cache" \
		--exclude="Installed Packages" \
		--exclude="User/oscrypto-ca-bundle.crt" \
		--exclude="Local/Session.sublime_session" \
		--delete \
		"$HOME/Library/Application Support/Sublime Merge" "$HOME/Downloads/dotfiles" &>/dev/null

	for preference_file in "${preference_files[@]}"; do
		rsync -arz -E "$HOME/Library/Preferences/$preference_file" "$HOME/Downloads/dotfiles/preferences" &>/dev/null
	done

	mkdir -p "$HOME/Downloads/package-temp" || return
	pushd "$HOME/Downloads/package-temp" || return
	brew bundle dump --force &>/dev/null
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
			diff -w "$name" "$file" &>/dev/null
			if [ $? -eq 1 ]; then
				mv -f "$file" "$name"
			fi
		else
			mv -f "$file" "$name"
		fi
	done

	rm -rf "$HOME/Downloads/package-temp"
	perl /opt/geedbla/scripts/gitkeep-repro.pl "$HOME/Downloads/dotfiles/"
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
		"$HOME/.config/zsh/.zsh_history"
		"$HOME/.config/zsh/zcompdump*"
		"$HOME/.config/thefuck/__pycache__"
		"$HOME/.config/iterm2"
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
format-project "/opt/geedbla"

if [ $# -gt 0 ]; then
	case $1 in
		-h | --help)
			echo "================================================="
			echo "Sync may Macs abd update dot file repro on GitHub"
			echo "================================================="
			echo
			echo '   sync.sh --github "commit message" for auto commit'
			echo "   sync.sh --help for this help message"
			echo "   sync.sh --sync to my other Mac(s)"
			echo "   sync.sh --package build the GitHub update without committing it"
			echo
			exit 0
			;;

		-p | --package)
			buildRepository
			;;

		-s | --sync)
			sync
			exit 0
			;;

		--github)
			updateGitHub "$2"
			exit 0
			;;

		-*)
			echo "Unknown option -- $1"
			exit 1
			;;

		*)
			sync
			exit 0
			;;
	esac
else
	sync
fi
