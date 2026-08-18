#!/usr/bin/env bash
set -Eeuo pipefail
#*****************************************************************************************
# sync-mac.sh
#
# This script will sync key files and system between a host and list other Macs
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :  11-Aug-2026  5:05pm
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
script_name="${0##*/}"
failure_count=0
systems_to_sync=("Garys-Mac-Studio.local" "Garys-MacBook-Pro.local")

#-----------------------------------------------------------------------------------------

finish() {
	unset sudo_password
}

# All normal output is discarded by main, so every message goes to stderr.
log() {
	printf '%s: %s\n' "${script_name}" "$*" >&2
}

fail() {
	failure_count=$((failure_count + 1))
	log "error: $*"
}

die() {
	log "fatal: $*"
	exit 1
}

# Run one sync step, reporting and counting a failure without aborting the rest of the run.
run_step() {
	local description="$1"
	shift
	"$@" || fail "${description}"
}

check_requirements() {
	local missing=()
	local cmd

	for cmd in sshpass rsync ssh base64 xattr comm find brew npm; do
		command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
	done

	[[ ${#missing[@]} -eq 0 ]] || die "required command(s) not found: ${missing[*]}"
}

target_reachable() {
	local target_system="$1"

	SSHPASS="${sudo_password}" sshpass -e ssh -o ConnectTimeout=10 "${target_system}" true 2>/dev/null
}

# openrsync reports a receiver killed by the target's privacy protections as a truncated
# stream, so translate that into something actionable.
report_output() {
	local description="$1"
	local target_system="$2"
	local output="$3"

	log "${description} failed${output:+ - ${output//$'\n'/; }}"
	case "${output}" in
		*"unexpected end of file"* | *"Operation not permitted"* | *"Permission denied"*)
			log "hint: sshd on ${target_system#*@} may need Full Disk Access - System Settings > Privacy & Security > Full Disk Access"
			;;
	esac
}

# rsync to the target, capturing its diagnostics so a failure says why
rsync_to_target() {
	local description="$1"
	local target_system="$2"
	shift 2
	local output

	if ! output="$(SSHPASS="${sudo_password}" sshpass -e rsync -az "$@" 2>&1)"; then
		report_output "${description}" "${target_system}" "${output}"
		return 1
	fi

	return 0
}

sync_directories() {
	local target_system="$1"
	local status=0
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
		if [[ ! -d ${dir} ]]; then
			log "skipping ${dir} - not a directory on this host"
			continue
		fi

		local remote_dir="${dir// /\\ }"
		if ! rsync_to_target "rsync of ${dir} to ${target_system}" "${target_system}" \
			--delete "${dir}/" "${target_system}:${remote_dir}/"; then
			status=1
			continue
		fi
		sync_custom_icons "${dir}" "${target_system}" || status=1
	done

	for file in "${files_to_sync[@]}"; do
		if [[ ! -f ${file} ]]; then
			log "skipping ${file} - not present on this host"
			continue
		fi

		local remote_file="${file// /\\ }"
		if ! rsync_to_target "rsync of ${file} to ${target_system}" "${target_system}" \
			"${file}" "${target_system}:${remote_file}"; then
			status=1
		fi
	done

	return ${status}
}

sync_custom_icons() {
	local dir="$1"
	local target_system="$2"
	local icon_name
	icon_name="$(printf 'Icon\r')"

	if [[ ! -d ${dir} ]]; then
		log "custom icon scan skipped - ${dir} is not a directory"
		return 1
	fi

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
		if ! printf '%s' "${script}" |
			SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "cd '${dir}' && bash -s"; then
			log "custom icon restore for ${dir} failed on ${target_system}"
			return 1
		fi
	fi

	return 0
}

sync_mail_archive() {
	local target_system="$1"
	local status=0
	local mail_dir=~/Library/Mail
	local remote_dir="${mail_dir// /\\ }"
	local pref_files=(
		~/Library/Preferences/com.apple.mail.plist
		~/Library/Containers/com.apple.mail/Data/Library/Preferences/com.apple.mail.plist
	)

	if [[ ! -d ${mail_dir} ]]; then
		log "mail archive skipped - ${mail_dir} is not a directory on this host"
		return 1
	fi

	if ! rsync_to_target "rsync of ${mail_dir} to ${target_system}" "${target_system}" \
		--delete "${mail_dir}/" "${target_system}:${remote_dir}/"; then
		status=1
	fi

	for file in "${pref_files[@]}"; do
		if [[ -f $file ]]; then
			local remote_file="${file// /\\ }"
			# We use rsync without --delete here as these are individual files
			if ! rsync_to_target "rsync of ${file} to ${target_system}" "${target_system}" \
				"${file}" "${target_system}:${remote_file}"; then
				status=1
			fi
		fi
	done

	return ${status}
}

sync_ruby_gems() {
	local target_system="$1"
	local host_gem_list
	local target_gem_list
	local host_gems
	local target_gems
	local gems_to_remove
	local gems_to_install
	local status=0
	local rbenv_init='export RBENV_ROOT=/opt/venv/ruby && export PATH="${RBENV_ROOT}/bin:${PATH}" && eval "$(rbenv init -)"'

	if [[ ! -d /opt/venv/ruby ]]; then
		log "ruby gem sync skipped - /opt/venv/ruby not found on this host"
		return 1
	fi
	if ! eval "${rbenv_init}"; then
		log "rbenv initialization failed on this host"
		return 1
	fi
	if ! command -v gem >/dev/null 2>&1; then
		log "gem command not found after rbenv initialization"
		return 1
	fi

	if ! host_gem_list="$(gem list | sort)"; then
		log "unable to read the gem list on this host"
		return 1
	fi
	if ! target_gem_list="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${rbenv_init} && gem list | sort'")"; then
		log "unable to read the gem list on ${target_system}"
		return 1
	fi

	# An empty host list would mark every gem on the target for removal
	if [[ -z ${host_gem_list} ]]; then
		log "host gem list is empty - refusing to sync gems to ${target_system}"
		return 1
	fi

	host_gems="$(echo "${host_gem_list}" | sed 's/ (.*//' | sort)"
	target_gems="$(echo "${target_gem_list}" | sed 's/ (.*//' | sort)"

	gems_to_remove="$(comm -23 <(echo "${target_gems}") <(echo "${host_gems}") | tr '\n' ' ')"
	gems_to_install="$(comm -23 <(echo "${host_gem_list}") <(echo "${target_gem_list}") | sed 's/ (.*//' | sort -u | tr '\n' ' ')"

	if [[ -n ${gems_to_remove} ]]; then
		if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${rbenv_init} && gem uninstall -aIx ${gems_to_remove}'"; then
			log "gem uninstall failed on ${target_system}"
			status=1
		fi
	fi
	if [[ -n ${gems_to_install} ]]; then
		if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${rbenv_init} && gem install --force ${gems_to_install}'"; then
			log "gem install failed on ${target_system}"
			status=1
		fi
	fi

	return ${status}
}

sync_pip_packages() {
	local target_system="$1"
	local host_freeze
	local target_freeze
	local host_packages
	local target_packages
	local packages_to_remove
	local packages_to_install
	local status=0
	local venv_init='source /opt/venv/python3/bin/activate'

	if [[ ! -r /opt/venv/python3/bin/activate ]]; then
		log "pip package sync skipped - /opt/venv/python3 not found on this host"
		return 1
	fi
	if ! source /opt/venv/python3/bin/activate; then
		log "unable to activate the python virtual environment on this host"
		return 1
	fi
	if ! command -v pip3 >/dev/null 2>&1; then
		log "pip3 command not found after activating the virtual environment"
		return 1
	fi

	if ! host_freeze="$(pip3 list --format=freeze | sort)"; then
		log "unable to read the pip package list on this host"
		return 1
	fi
	if ! target_freeze="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${venv_init} && pip3 list --format=freeze | sort'")"; then
		log "unable to read the pip package list on ${target_system}"
		return 1
	fi

	# An empty host list would mark every package on the target for removal
	if [[ -z ${host_freeze} ]]; then
		log "host pip package list is empty - refusing to sync packages to ${target_system}"
		return 1
	fi

	host_packages="$(echo "${host_freeze}" | cut -d= -f1 | sort)"
	target_packages="$(echo "${target_freeze}" | cut -d= -f1 | sort)"

	packages_to_remove="$(comm -23 <(echo "${target_packages}") <(echo "${host_packages}") | tr '\n' ' ')"
	packages_to_install="$(comm -23 <(echo "${host_freeze}") <(echo "${target_freeze}") | tr '\n' ' ')"

	if [[ -n ${packages_to_remove} ]]; then
		if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${venv_init} && pip3 uninstall -qy ${packages_to_remove}'"; then
			log "pip uninstall failed on ${target_system}"
			status=1
		fi
	fi
	if [[ -n ${packages_to_install} ]]; then
		if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c '${venv_init} && pip3 install -q ${packages_to_install}'"; then
			log "pip install failed on ${target_system}"
			status=1
		fi
	fi

	return ${status}
}

sync_homebrew_packages() {
	local target_system="$1"
	local host_formulae
	local target_formulae
	local formulae_to_remove
	local host_casks
	local target_casks
	local casks_to_remove
	local status=0

	if ! host_formulae="$(brew list --formula | sort)"; then
		log "unable to read the Homebrew formula list on this host"
		return 1
	fi
	if ! target_formulae="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew list --formula | sort'")"; then
		log "unable to read the Homebrew formula list on ${target_system}"
		return 1
	fi

	# An empty host list would mark every formula on the target for removal
	if [[ -z ${host_formulae} ]]; then
		log "host Homebrew formula list is empty - refusing to sync formulae to ${target_system}"
		return 1
	fi

	formulae_to_remove="$(comm -23 <(echo "${target_formulae}") <(echo "${host_formulae}") | tr '\n' ' ')"

	if [[ -n ${formulae_to_remove} ]]; then
		if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew uninstall -q ${formulae_to_remove} >/dev/null 2>&1'"; then
			log "Homebrew formula uninstall failed on ${target_system}"
			status=1
		fi
	fi
	if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'NONINTERACTIVE=1 brew install -q $(echo "${host_formulae}" | tr '\n' ' ') >/dev/null 2>&1'"; then
		log "Homebrew formula install failed on ${target_system}"
		status=1
	fi

	if ! host_casks="$(brew list --cask | sort)"; then
		log "unable to read the Homebrew cask list on this host"
		return 1
	fi
	if ! target_casks="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew list --cask | sort'")"; then
		log "unable to read the Homebrew cask list on ${target_system}"
		return 1
	fi

	# An empty host list would mark every cask on the target for removal
	if [[ -z ${host_casks} ]]; then
		log "host Homebrew cask list is empty - refusing to sync casks to ${target_system}"
		return 1
	fi

	casks_to_remove="$(comm -23 <(echo "${target_casks}") <(echo "${host_casks}") | tr '\n' ' ')"

	if [[ -n ${casks_to_remove} ]]; then
		if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew uninstall -q --cask ${casks_to_remove} >/dev/null 2>&1'"; then
			log "Homebrew cask uninstall failed on ${target_system}"
			status=1
		fi
	fi
	if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'brew install -q --cask $(echo "${host_casks}" | tr '\n' ' ') >/dev/null 2>&1'"; then
		log "Homebrew cask install failed on ${target_system}"
		status=1
	fi

	return ${status}
}

sync_npm_packages() {
	local target_system="$1"
	local host_packages
	local target_packages
	local packages_to_remove
	local status=0

	if ! host_packages="$(npm list -g --depth=0 --parseable | tail -n +2 | sed 's#.*/node_modules/##' | sort)"; then
		log "unable to read the global npm package list on this host"
		return 1
	fi
	if ! target_packages="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'npm list -g --depth=0 --parseable | tail -n +2 | sed \"s#.*/node_modules/##\" | sort'")"; then
		log "unable to read the global npm package list on ${target_system}"
		return 1
	fi

	# An empty host list would mark every global package on the target for removal
	if [[ -z ${host_packages} ]]; then
		log "host npm package list is empty - refusing to sync packages to ${target_system}"
		return 1
	fi

	packages_to_remove="$(comm -23 <(echo "${target_packages}") <(echo "${host_packages}") | tr '\n' ' ')"

	if [[ -n ${packages_to_remove} ]]; then
		if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'npm uninstall -g --silent ${packages_to_remove}'"; then
			log "npm global uninstall failed on ${target_system}"
			status=1
		fi
	fi
	if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "zsh -l -c 'PUPPETEER_SKIP_DOWNLOAD=1 npm install -g --silent $(echo "${host_packages}" | tr '\n' ' ')'"; then
		log "npm global install failed on ${target_system}"
		status=1
	fi

	return ${status}
}

sync_custom_apps() {
	local target_system="$1"
	local apps_to_sync=("CleanStart.app" "XcodeGeDblA.app")
	local base_path="/Applications"
	local staging_dir="/tmp/sync_apps_staging"
	local status=0

	if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "mkdir -p ${staging_dir}"; then
		log "unable to create the staging directory ${staging_dir} on ${target_system}"
		return 1
	fi

	for app in "${apps_to_sync[@]}"; do
		local app_path="${base_path}/${app}"
		if [[ -d ${app_path} ]]; then
			if ! rsync_to_target "staging of ${app} on ${target_system}" "${target_system}" \
				--delete "${app_path}" "${target_system}:${staging_dir}/"; then
				status=1
				continue
			fi
			local output
			if ! output="$(SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" \
				"echo '${sudo_password}' | sudo -S -p '' rsync -a --delete '${staging_dir}/${app}/' '${base_path}/${app}/'" 2>&1)"; then
				report_output "install of ${app} on ${target_system}" "${target_system}" "${output}"
				status=1
			fi
		else
			log "skipping ${app} - not present locally at ${app_path}"
		fi
	done

	if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "rm -rf ${staging_dir}"; then
		log "unable to remove the staging directory ${staging_dir} on ${target_system}"
		status=1
	fi

	return ${status}
}

save_bbedit_window_placement() {
	local target_system="$1"

	# BBEdit's default window placement/size is stored per display arrangement and is
	# specific to each Mac. Back up the target's own preferences before the host's
	# BBEdit settings overwrite them, so the target's window geometry can be restored.
	if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" \
		'cp -f "$HOME/Library/Containers/com.barebones.bbedit/Data/Library/Preferences/com.barebones.bbedit.plist" /tmp/bbedit-window-placement-backup.plist 2>/dev/null || true'; then
		log "BBEdit window placement backup failed on ${target_system}"
		return 1
	fi

	return 0
}

restore_bbedit_window_placement() {
	local target_system="$1"

	# Re-apply the target Mac's own window placement (saved before the sync) on top of
	# the freshly-synced BBEdit preferences, then flush the preferences cache so BBEdit
	# reads the restored geometry on next launch. The placement is held in top-level
	# keys prefixed "DefaultPosition:" (bounds rect) and "DefaultProperties:" (window
	# state); each such key is copied back from the backup into the synced preferences.
	if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" 'bash -s' <<'REMOTE'; then
set -euo pipefail
backup="/tmp/bbedit-window-placement-backup.plist"
prefs="$HOME/Library/Containers/com.barebones.bbedit/Data/Library/Preferences/com.barebones.bbedit.plist"
[[ -f $backup && -f $prefs ]] || exit 0

keys=$(plutil -convert xml1 -o - "$backup" |
	grep -oE '<key>(DefaultPosition|DefaultProperties):[^<]*</key>' |
	sed -E 's#</?key>##g') || true

while IFS= read -r key; do
	[[ -n $key ]] || continue
	frag=$(plutil -extract "$key" xml1 -o - "$backup" 2>/dev/null) || continue
	plutil -replace "$key" -xml "$frag" "$prefs" 2>/dev/null || true
done <<<"$keys"

rm -f "$backup"
killall cfprefsd 2>/dev/null || true
REMOTE
		log "BBEdit window placement restore failed on ${target_system}"
		return 1
	fi

	return 0
}

main() {
	trap finish EXIT
	trap 'rc=$?; echo "sync-mac: aborted at line ${LINENO} (exit ${rc}): ${BASH_COMMAND}" >&2' ERR

	local current_host
	local target_system
	local synced_count=0

	check_requirements

	current_host="$(hostname)"
	if [[ -z ${current_host} ]]; then
		die "unable to determine the name of this host"
	fi

	# Without a match this host is not excluded from the list and would sync to itself
	local known_host=0
	for system in "${systems_to_sync[@]}"; do
		if [[ ${system} == "${current_host}" ]]; then
			known_host=1
		fi
	done
	[[ ${known_host} -eq 1 ]] || log "warning: this host (${current_host}) is not in the sync list"

	sudo_password="$(get_sudo_password)"
	[[ -n ${sudo_password} ]] || log "warning: the sudo password is empty - ssh and remote sudo may fail"

	exec 1>/dev/null

	for system in "${systems_to_sync[@]}"; do
		if [[ ${system} != "${current_host}" ]]; then
			target_system="${USER}@${system}"

			if ! target_reachable "${target_system}"; then
				fail "${target_system} is unreachable - skipping"
				continue
			fi
			synced_count=$((synced_count + 1))

			run_step "BBEdit window placement backup on ${system}" save_bbedit_window_placement "${target_system}"
			run_step "directory sync to ${system}" sync_directories "${target_system}"
			run_step "mail archive sync to ${system}" sync_mail_archive "${target_system}"
			run_step "ruby gem sync to ${system}" sync_ruby_gems "${target_system}"
			run_step "pip package sync to ${system}" sync_pip_packages "${target_system}"
			run_step "Homebrew package sync to ${system}" sync_homebrew_packages "${target_system}"
			run_step "npm package sync to ${system}" sync_npm_packages "${target_system}"
			run_step "custom app sync to ${system}" sync_custom_apps "${target_system}"
			run_step "BBEdit window placement restore on ${system}" restore_bbedit_window_placement "${target_system}"
		fi
	done

	[[ ${synced_count} -gt 0 ]] || log "warning: no target systems were synced"

	if [[ ${failure_count} -gt 0 ]]; then
		log "completed with ${failure_count} failure(s)"
		return 1
	fi

	return 0
}

main "$@"
