#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# test-sync-custom-apps.sh
#
# Standalone harness to exercise sync-mac.sh's custom .app install path against a
# single target host, with all stdout/stderr left visible for diagnosis.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  14-Jun-2026 10:26pm
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

#-----------------------------------------------------------------------------------------

finish() {
	unset sudo_password
}

usage() {
	echo "usage: ${0##*/} <target-host>" >&2
	echo "       e.g. ${0##*/} Garys-MacBook-Pro.local" >&2
	exit 2
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
			echo ">> staging ${app} to ${target_system}:${staging_dir}/"
			if ! SSHPASS="${sudo_password}" sshpass -e rsync -azq --delete "${app_path}" "${target_system}:${staging_dir}/"; then
				echo "Failed to sync ${app} to ${target_system}" >&2
				continue
			fi
			echo ">> installing ${app} into ${base_path}/${app}/ via sudo rsync"
			if ! SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" \
				"echo '${sudo_password}' | sudo -S -p '' rsync -aq --delete '${staging_dir}/${app}/' '${base_path}/${app}/'"; then
				echo "Failed to install ${app} on ${target_system}" >&2
			else
				echo ">> ${app} installed OK"
			fi
		else
			echo ">> skipping ${app} (not present locally at ${app_path})"
		fi
	done

	SSHPASS="${sudo_password}" sshpass -e ssh "${target_system}" "rm -rf ${staging_dir}"
}

main() {
	trap finish EXIT

	[[ $# -eq 1 ]] || usage
	local target_host="$1"
	local target_system="${USER}@${target_host}"

	sudo_password="$(get_sudo_password)"

	echo "== target: ${target_system} =="
	sync_custom_apps "${target_system}"
	echo "== done =="
}

main "$@"
