#!/usr/bin/env zsh
#*****************************************************************************************
# sync-macs.sh
#
# This script will sync my Macs using the system that runs this script as the source.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Jan-2025 10:08pm
# Modified :
#
# Copyright © 2024-2025 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# load utilities from scripting libraries
#*****************************************************************************************
autoload get_sudo_password
autoload start_persistant_sudo
autoload stop_persistant_sudo

#*****************************************************************************************
# global variables
#*****************************************************************************************
me="$(scutil --get LocalHostName).local"
systems=("Garys-Mac-Studio.local" "Garys-MacBook-Pro.local")
password=$(get_sudo_password)

updateSyncedFolders() {
	local toSync=(
		"$HOME/.config"
		"$HOME/Desktop"
		"$HOME/Sites"
		"$HOME/Pictures"
		"$HOME/Documents"
		"$HOME/Developer"
		"$HOME/Library/Application Support/BBEdit"
		"$HOME/Library/Containers/com.barebones.bbedit/Data/Library/Preferences/com.barebones.bbedit.plist"
		"/opt/geedbla"
	)

	for pathToSync in "${toSync[@]}"; do
		targetDirectory=$(dirname "$pathToSync")
		targetDirectory="${targetDirectory// /\\ }"
		rsync --rsh="sshpass -p $password ssh -l $USER" -arzE --delete "$pathToSync" "$remote:$targetDirectory/" &>/dev/null
	done
}

updateBrew() {
	brew bundle dump --brews --casks --taps --force --file="$HOME/Downloads/bundles.txt" &>/dev/null
	sshpass -p "$password" rsync -arz -E --rsh=ssh "$HOME/Downloads/bundles.txt" "$remote:$HOME/Downloads/bundles.txt" &>/dev/null
	rm -f "$HOME/Downloads/bundles.txt" &>/dev/null

	sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S chmod -R 777 /Applications/*" &>/dev/null
	sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";brew bundle --force --no-lock --file=$HOME/Downloads/bundles.txt &> /dev/null" &>/dev/null
	sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";brew bundle cleanup --force --file=$HOME/Downloads/bundles.txt &> /dev/null" &>/dev/null
	sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";brew update &> /dev/null" &>/dev/null
	sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";brew upgrade &> /dev/null" &>/dev/null
	sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";brew autoremove &> /dev/null" &>/dev/null
	sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S chown -R root:wheel /Applications/*" &>/dev/null
	sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S chmod -R 755 /Applications/*" &>/dev/null
	sshpass -p "$password" ssh "$remote" "rm -f \"$HOME/Downloads/bundles.txt\" &" &>/dev/null
}

updateRuby() {
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
}

updatePython() {
	sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";pip3 install --upgrade --break-system-package pip &> /dev/null"

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
		sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";pip3 install --break-system-packages \"$pipToAdd\" &> /dev/null"
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
		sshpass -p "$password" rsync -arz -E --rsh=ssh "$HOME/Library/Preferences/$preference_file" "$remote:$HOME/Library/Preferences" &>/dev/null
	done
}

updatePreferences() {
	local preference_files=(
		"com.apple.dt.Xcode.plist"
		"com.apple.applescript.plist"
		"com.apple.Terminal.plist"
	)

	dot-files
	for preference_file in "${preference_files[@]}"; do
		sshpass -p "$password" rsync -arz -E --rsh=ssh "$HOME/Library/Preferences/$preference_file" "$remote:$HOME/Library/Preferences" &>/dev/null
	done

	sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S killall Dock" &>/dev/null
	sshpass -p "$password" rsync -arzE --rsh ssh "$HOME/Movies" "$remote:$HOME" &>/dev/null
	sshpass -p "$password" ssh "$remote" "rm -f $log" &>/dev/null
	sshpass -p "$password" ssh "$remote" "export PATH=\"$PATH\";cd ~;rm -rf .gem .DS_Store #  &> /dev/null"
	sshpass -p "$password" ssh "$remote" "find . -name \"Icon?\" -exec chflags hidden {} \; &> /dev/null"
}

updateXcode() {
	sshpass -p "$password" rsync -arz -E \
		--exclude="UserData/Capabilities" \
		--exclude="UserData/IB Support" \
		--exclude="UserData/Portal" \
		--exclude="UserData/Previews" \
		--exclude="UserData/XcodeCloud" \
		--exclude="UserData/IDEEditorInteractivityHistory" \
		--exclude="UserData/IDEFindNavigatorScopes.plist" \
		--exclude="/Products" \
		--exclude="/XCPGDevices" \
		--exclude="/XCTestDevices" \
		--exclude="/* DeviceSupport" \
		--exclude="/* Device Logs" \
		--exclude="DeviceLogs" \
		--exclude="/DeviceLogs" \
		--exclude="/DerivedData" \
		--exclude="/DocumentationIndex" \
		--exclude="/DocumentationCache" \
		--delete \
		"$HOME/Library/Developer/Xcode/" "$remote:$HOME/Library/Developer/Xcode/" &>/dev/null
}

updateSublime() {
	if [[ -d "$HOME/Library/Application Support/Sublime Text" ]]; then
		sshpass -p "$password" rsync -arz -E --rsh=ssh \
			--exclude="Index" \
			--exclude="Cache" \
			--exclude="User/oscrypto-ca-bundle.crt" \
			--delete \
			"$HOME/Library/Application Support/Sublime Text" \
			"$remote:$HOME/Library/Application\\ Support/" &>/dev/null
	fi

	if [[ -d "$HOME/Library/Application Support/Sublime Merge" ]]; then
		sshpass -p "$password" rsync -arz -E --rsh=ssh \
			--exclude="Cache" \
			--exclude="User/oscrypto-ca-bundle.crt" \
			--delete \
			"$HOME/Library/Application Support/Sublime Merge" \
			"$remote:$HOME/Library/Application\\ Support/" &>/dev/null
	fi
}

updateApplications() {
	local apps=(
		"CleanStart.app"
		"XcodeGeeDblA.app"
	)

	sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S chmod -R 777 /Applications/*" &>/dev/null

	for anApp in "${apps[@]}"; do
		appToInstall="/Applications/$anApp"
		sshpass -p "$password" rsync -arz -E "$appToInstall" "$remote:$HOME/Downloads"
		if [[ $? -eq 0 ]]; then
			sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S rm -rf $appToInstall" &>/dev/null
			sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S cp -rf $HOME/Downloads/$anApp /Applications" &>/dev/null
			sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S rm -rf $HOME/Downloads/$anApp" &>/dev/null
		fi
	done


	sshpass -p "$password" ssh -t "$remote" "echo $password | sudo -S chown -R root:wheel /Applications/*" &>/dev/null
}

updatePhotos() {
	sshpass -p "$password" ssh "$remote" "echo $password | sudo -S rm -rf \"$HOME/Pictures/Photos Library.photoslibrary\" #&> /dev/null" #&> /dev/null
	sshpass -p "$password" rsync -arz -E --rsh=ssh "$HOME/Pictures/Photos Library.photoslibrary" "$remote:$HOME/Pictures"                #&> /dev/null
}

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

	basecmd="sshpass -p ${password} rsync -az "
	1="$remote:$HOME/"

	for exclude in "${ignore_these[@]}"; do
		basecmd+="--exclude=\"$(basename $exclude)\" "
	done
	for dotfile in "${dotfiles[@]}"; do
		if [[ -n $dotfile ]]; then
			cmd="$basecmd\"$dotfile\" \"$1\""
			eval "$cmd"
		fi
	done
}

#*****************************************************************************************
# script main line
#*****************************************************************************************
for computer in "${systems[@]}"; do
	if [ "$me" != "$computer" ]; then
		remote="$USER@$computer"

		updateSyncedFolders
		updateBrew
		updateRuby
		updatePython
		updatePreferences
		updateXcode
		updateSublime
		updateApplications
		#updatePhotos
	fi
done

exit 0
