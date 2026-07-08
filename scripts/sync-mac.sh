#!/usr/bin/env bash
set -Eeuo pipefail
#*****************************************************************************************
# sync-mac.sh
#
# This script will sync key files and system between a host and list other Macs
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :   7-Jul-2026  9:50pm
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
	local directories_to_sync=(
		~/.claude
		~/.config
		~/Developer
		~/Documents
		/opt/bin
		/opt/geedbla
		~/Library/"Script Libraries"
		~/Library/"Application Support"/BBEdit
		~/Library/Containers/com.barebones.bbedit)

	local files_to_sync=(
		~/.claude.json
		~/Library/Preferences/com.apple.systemuiserver.plist
	)

	for dir in "${directories_to_sync[@]}"; do
		local remote_dir="${dir// /\\ }"
		SSHPASS="${sudo_password}" sshpass -e rsync -azq --delete "${dir}/" "${target_system}:${remote_dir}/"
		sync_custom_icons "${dir}" "${target_system}"
	done

	for file in "${files_to_sync[@]}"; do
		local remote_file="${file// /\\ }"
		SSHPASS="${sudo_password}" sshpass -e rsync -azq "${file}" "${target_system}:${remote_file}"
	done
}

sync_custom_icons() {
	local dir="$1"
	local target_system="$2"
	local icon_name
	icon_name="$(printf 'Icon\r')"

	# Custom folder icons live in a file named "Icon\r"; the icon image is stored
	# in that file's resource fork and the enclosing folder records the custom-icon
	# flag in its FinderInfo. openrsync cannot carry resource forks or extended
	# attributes over ssh, so overlay just those bytes onto the already-synced files:
	# stream each resource fork through the ..namedfork/rsrc path and re-apply the
	# FinderInfo of both the icon file and its folder with xattr.
	local script=""
	local icon parent rf_b64 file_fi dir_fi
	while IFS= read -r -d '' icon; do
		parent="$(dirname "${icon}")"
		rf_b64="$(base64 <"${dir}/${icon}/..namedfork/rsrc" 2>/dev/null || true)"
		file_fi="$(xattr -px com.apple.FinderInfo "${dir}/${icon}" 2>/dev/null | tr -d ' \n' || true)"
		dir_fi="$(xattr -px com.apple.FinderInfo "${dir}/${parent}" 2>/dev/null | tr -d ' \n' || true)"

		if [[ -n ${rf_b64} ]]; then
			script+="base64 -D > '${icon}/..namedfork/rsrc' <<'__RF__'"$'\n'"${rf_b64}"$'\n'"__RF__"$'\n'
		fi
		[[ -n ${file_fi} ]] && script+="xattr -wx com.apple.FinderInfo '${file_fi}' '${icon}'"$'\n'
		[[ -n ${dir_fi} ]] && script+="xattr -wx com.apple.FinderInfo '${dir_fi}' '${parent}'"$'\n'
	done < <(cd "${dir}" && find . -type f -name "${icon_name}" -print0)

	if [[ -n ${script} ]]; then
		printf '%s' "${script}" |
			SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "cd '${dir}' && bash -s"
	fi
}

sync_mail_archive() {
	local target_system="$1"
	local mail_dir=~/Library/Mail
	local remote_dir="${mail_dir// /\\ }"
	local pref_files=(
		~/Library/Preferences/com.apple.mail.plist
		~/Library/Containers/com.apple.mail/Data/Library/Preferences/com.apple.mail.plist
	)

	SSHPASS="${sudo_password}" sshpass -e rsync -azq --delete "${mail_dir}/" "${target_system}:${remote_dir}/"

	for file in "${pref_files[@]}"; do
		if [[ -f $file ]]; then
			local remote_file="${file// /\\ }"
			# We use rsync without --delete here as these are individual files
			SSHPASS="${sudo_password}" sshpass -e rsync -azq "${file}" "${target_system}:${remote_file}"
		fi
	done
}

sync_ruby_gems() {
	local target_system="$1"
	local host_gem_list
	local target_gem_list
	local host_gems
	local target_gems
	local gems_to_remove
	local gems_to_install
	local rbenv_init='export RBENV_ROOT=/opt/venv/ruby && export PATH="${RBENV_ROOT}/bin:${PATH}" && eval "$(rbenv init -)"'

	eval "${rbenv_init}"

	host_gem_list="$(gem list | sort)"
	target_gem_list="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${rbenv_init} && gem list | sort'")"

	host_gems="$(echo "${host_gem_list}" | sed 's/ (.*//' | sort)"
	target_gems="$(echo "${target_gem_list}" | sed 's/ (.*//' | sort)"

	gems_to_remove="$(comm -23 <(echo "${target_gems}") <(echo "${host_gems}") | tr '\n' ' ')"
	gems_to_install="$(comm -23 <(echo "${host_gem_list}") <(echo "${target_gem_list}") | sed 's/ (.*//' | sort -u | tr '\n' ' ')"

	if [[ -n ${gems_to_remove} ]]; then
		SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${rbenv_init} && gem uninstall -aIx ${gems_to_remove}'"
	fi
	if [[ -n ${gems_to_install} ]]; then
		SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${rbenv_init} && gem install --force ${gems_to_install}'"
	fi
}

sync_pip_packages() {
	local target_system="$1"
	local host_freeze
	local target_freeze
	local host_packages
	local target_packages
	local packages_to_remove
	local packages_to_install
	local venv_init='source /opt/venv/python3/bin/activate'

	source /opt/venv/python3/bin/activate

	host_freeze="$(pip3 list --format=freeze | sort)"
	target_freeze="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${venv_init} && pip3 list --format=freeze | sort'")"

	host_packages="$(echo "${host_freeze}" | cut -d= -f1 | sort)"
	target_packages="$(echo "${target_freeze}" | cut -d= -f1 | sort)"

	packages_to_remove="$(comm -23 <(echo "${target_packages}") <(echo "${host_packages}") | tr '\n' ' ')"
	packages_to_install="$(comm -23 <(echo "${host_freeze}") <(echo "${target_freeze}") | tr '\n' ' ')"

	if [[ -n ${packages_to_remove} ]]; then
		SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${venv_init} && pip3 uninstall -qy ${packages_to_remove}'"
	fi
	if [[ -n ${packages_to_install} ]]; then
		SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${venv_init} && pip3 install -q ${packages_to_install}'"
	fi
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

	if [[ -n ${formulae_to_remove} ]]; then
		if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew uninstall -q ${formulae_to_remove} >/dev/null 2>&1'"; then
			echo "Homebrew formula uninstall failed on ${target_system}" >&2
		fi
	fi
	if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'NONINTERACTIVE=1 brew install -q $(echo "${host_formulae}" | tr '\n' ' ') >/dev/null 2>&1'"; then
		echo "Homebrew formula install failed on ${target_system}" >&2
	fi

	host_casks="$(brew list --cask | sort)"
	target_casks="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew list --cask | sort'")"
	casks_to_remove="$(comm -23 <(echo "${target_casks}") <(echo "${host_casks}") | tr '\n' ' ')"

	if [[ -n ${casks_to_remove} ]]; then
		if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew uninstall -q --cask ${casks_to_remove} >/dev/null 2>&1'"; then
			echo "Homebrew cask uninstall failed on ${target_system}" >&2
		fi
	fi
	if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew install -q --cask $(echo "${host_casks}" | tr '\n' ' ') >/dev/null 2>&1'"; then
		echo "Homebrew cask install failed on ${target_system}" >&2
	fi
}

sync_npm_packages() {
	local target_system="$1"
	local host_packages
	local target_packages
	local packages_to_remove

	host_packages="$(npm list -g --depth=0 --parseable | tail -n +2 | sed 's#.*/node_modules/##' | sort)"
	target_packages="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'npm list -g --depth=0 --parseable | tail -n +2 | sed \"s#.*/node_modules/##\" | sort'")"
	packages_to_remove="$(comm -23 <(echo "${target_packages}") <(echo "${host_packages}") | tr '\n' ' ')"

	if [[ -n ${packages_to_remove} ]]; then
		if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'npm uninstall -g --silent ${packages_to_remove}'"; then
			echo "npm global uninstall failed on ${target_system}" >&2
		fi
	fi
	if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'PUPPETEER_SKIP_DOWNLOAD=1 npm install -g --silent $(echo "${host_packages}" | tr '\n' ' ')'"; then
		echo "npm global install failed on ${target_system}" >&2
	fi
}

sync_custom_apps() {
	local target_system="$1"
	local apps_to_sync=("CleanStart.app" "XcodeGeDblA.app")
	local base_path="/Applications"
	local staging_dir="/tmp/sync_apps_staging"

	SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "mkdir -p ${staging_dir}"

	for app in "${apps_to_sync[@]}"; do
		local app_path="${base_path}/${app}"
		if [[ -d ${app_path} ]]; then
			if ! SSHPASS="${sudo_password}" sshpass -e rsync -azq --delete "${app_path}" "${target_system}:${staging_dir}/"; then
				echo "Failed to sync ${app} to ${target_system}" >&2
				continue
			fi
			if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" \
				"echo '${sudo_password}' | sudo -S -p '' rsync -aq --delete '${staging_dir}/${app}/' '${base_path}/${app}/'"; then
				echo "Failed to install ${app} on ${target_system}" >&2
			fi
		fi
	done

	SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "rm -rf ${staging_dir}"
}

restore_bbedit_layout() {
	local target_system="$1"
	local restore_script="/opt/geedbla/scripts/bbedit-restore-layout.sh"

	if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${restore_script}'"; then
		echo "BBEdit layout restore failed on ${target_system}" >&2
	fi
}

main() {
	trap finish EXIT
	trap 'rc=$?; echo "sync-mac: aborted at line ${LINENO} (exit ${rc}): ${BASH_COMMAND}" >&2' ERR

	local current_host
	local target_system
	current_host="$(hostname)"

	sudo_password="$(get_sudo_password)"
	exec 1>/dev/null

	for system in "${systems_to_sync[@]}"; do
		if [[ ${system} != "${current_host}" ]]; then
			target_system="${USER}@${system}"
			sync_directories "${target_system}"
			sync_mail_archive "${target_system}"
			sync_ruby_gems "${target_system}"
			sync_pip_packages "${target_system}"
			sync_homebrew_packages "${target_system}"
			sync_npm_packages "${target_system}"
			sync_custom_apps "${target_system}"
		fi
	done
}

main "$@"
