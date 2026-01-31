#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# sync-mac.sh
#
# This script will sync key files and system between a host and list other Macs
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# source in library functions
#*****************************************************************************************
source "/opt/geedbla/lib/shell/lib/get_sudo_password.sh"

#*****************************************************************************************
# global variables
#*****************************************************************************************
sudo_password=""
systems_to_sync=("Garys-Mac-Studio.local" "Garys-MacBook-Pro.local")

#-----------------------------------------------------------------------------------------

finish() {
	unset sudo_password
}

sync_directories() {
	local target_system="$1"
	local directories_to_sync=(~/.claude ~/.config ~/Developer ~/Documents /opt/geedbla ~/Library/"Application Support"/BBEdit)
	local files_to_sync=(~/.claude.json)

	for dir in "${directories_to_sync[@]}"; do
		local remote_dir="${dir// /\\ }"
		SSHPASS="${sudo_password}" sshpass -e rsync -azq --delete "${dir}/" "${target_system}:${remote_dir}/"
	done

	for file in "${files_to_sync[@]}"; do
		local remote_file="${file// /\\ }"
		SSHPASS="${sudo_password}" sshpass -e rsync -azq "${file}" "${target_system}:${remote_file}"
	done
}

sync_ruby_gems() {
	local target_system="$1"
	local host_gems
	local target_gems
	local gems_to_remove
	local rbenv_init='export RBENV_ROOT=/opt/venv/ruby && export PATH="${RBENV_ROOT}/bin:${PATH}" && eval "$(rbenv init -)"'

	host_gems="$(gem list --no-versions | sort)"
	target_gems="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${rbenv_init} && gem list --no-versions | sort'")"
	gems_to_remove="$(comm -23 <(echo "${target_gems}") <(echo "${host_gems}") | tr '\n' ' ')"

	if [[ -n "${gems_to_remove}" ]]; then
		SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${rbenv_init} && gem uninstall -aIx ${gems_to_remove}'"
	fi
	SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${rbenv_init} && gem install $(echo "${host_gems}" | tr '\n' ' ')'"
}

sync_pip_packages() {
	local target_system="$1"
	local host_packages
	local target_packages
	local packages_to_remove
	local venv_init='source /opt/venv/python3/bin/activate'

	host_packages="$(pip3 list --format=freeze | cut -d= -f1 | sort)"
	target_packages="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${venv_init} && pip3 list --format=freeze | cut -d= -f1 | sort'")"
	packages_to_remove="$(comm -23 <(echo "${target_packages}") <(echo "${host_packages}") | tr '\n' ' ')"

	if [[ -n "${packages_to_remove}" ]]; then
		SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${venv_init} && pip3 uninstall -qy ${packages_to_remove}'"
	fi
	SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${venv_init} && pip3 install -q $(pip3 list --format=freeze | tr '\n' ' ')'"
}

sync_homebrew_packages() {
	local target_system="$1"
	local host_formulae
	local target_formulae
	local formulae_to_remove
	local host_casks
	local target_casks
	local casks_to_remove

	host_formulae="$(brew list --formula | sort)"
	target_formulae="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew list --formula | sort'")"
	formulae_to_remove="$(comm -23 <(echo "${target_formulae}") <(echo "${host_formulae}") | tr '\n' ' ')"

	if [[ -n "${formulae_to_remove}" ]]; then
		SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew uninstall -q ${formulae_to_remove}'"
	fi
	SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew install -q $(echo "${host_formulae}" | tr '\n' ' ')'"

	host_casks="$(brew list --cask | sort)"
	target_casks="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew list --cask | sort'")"
	casks_to_remove="$(comm -23 <(echo "${target_casks}") <(echo "${host_casks}") | tr '\n' ' ')"

	if [[ -n "${casks_to_remove}" ]]; then
		SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew uninstall -q --cask ${casks_to_remove}'"
	fi
	SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew install -q --cask $(echo "${host_casks}" | tr '\n' ' ')'"
}

sync_npm_packages() {
	local target_system="$1"
	local host_packages
	local target_packages
	local packages_to_remove

	host_packages="$(npm list -g --depth=0 --parseable | tail -n +2 | xargs -n1 basename | sort)"
	target_packages="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'npm list -g --depth=0 --parseable | tail -n +2 | xargs -n1 basename | sort'")"
	packages_to_remove="$(comm -23 <(echo "${target_packages}") <(echo "${host_packages}") | tr '\n' ' ')"

	if [[ -n "${packages_to_remove}" ]]; then
		SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'npm uninstall -g --silent ${packages_to_remove}'"
	fi
	SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'npm install -g --silent $(echo "${host_packages}" | tr '\n' ' ')'"
}

main() {
	trap finish EXIT

	local current_host
	local target_system
	current_host="$(hostname)"

	sudo_password="$(get_sudo_password)"
	exec 1>/dev/null

	for system in "${systems_to_sync[@]}"; do
		if [[ "${system}" != "${current_host}" ]]; then
			target_system="${USER}@${system}"
			sync_directories "${target_system}"
			sync_ruby_gems "${target_system}"
			sync_pip_packages "${target_system}"
			sync_homebrew_packages "${target_system}"
			sync_npm_packages "${target_system}"
		fi
	done
}

main "$@"