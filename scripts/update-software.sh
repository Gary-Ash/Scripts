#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# update-software.sh
#
# This script will check for and install macOS system, App Store, Homebrew and
# Sparkle enabled application updates
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  18-Aug-2026  6:46pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly RED=$'\033[0;31m'
readonly RESET=$'\033[0m'

readonly APP_DIRS=(
	"/Applications"
	"${HOME}/Applications"
)

sparkle_updates=()
temp_files=()

#*****************************************************************************************
# routine to remove any temporary files left behind by an interrupted Sparkle update
#*****************************************************************************************
cleanup() {
	local exit_code="${?}"
	local temp_file

	for temp_file in "${temp_files[@]}"; do
		rm -rf "${temp_file}"
	done
	exit "${exit_code}"
}

#*****************************************************************************************
# routine to prompt the user for a yes/no answer, returns success for yes
#*****************************************************************************************
confirm() {
	local prompt="${1}"
	local answer

	read -r -n 1 -p "${prompt} (y/N): " answer
	printf '\n'
	[[ "${answer}" == "y" ]]
}

#*****************************************************************************************
# routine to check for and optionally install macOS system and App Store updates
#*****************************************************************************************
update_system() {
	local updates

	printf '%s\n' "${YELLOW}Checking macOS system & App Store updates...${RESET}"
	updates=$(softwareupdate -l 2>&1 | grep -E "Label:|recommended" || true)

	if [[ -z "${updates}" ]]; then
		printf '%s\n' "${GREEN}No macOS system/App Store updates available.${RESET}"
		return
	fi

	printf '%s\n%s\n\n' "${RED}System/App Store updates available:${RESET}" "${updates}"
	if confirm "Install system/App Store updates?"; then
		sudo softwareupdate -ia --verbose
	fi
}

#*****************************************************************************************
# routine to check for and optionally install Homebrew package updates
#*****************************************************************************************
update_homebrew() {
	local outdated

	if ! command -v brew >/dev/null 2>&1; then
		printf '%s\n' "${YELLOW}Homebrew not installed — skipping brew updates.${RESET}"
		return
	fi

	printf '%s\n' "${YELLOW}Checking Homebrew updates...${RESET}"
	brew update >/dev/null

	outdated=$(brew outdated || true)
	if [[ -z "${outdated}" ]]; then
		printf '%s\n' "${GREEN}No Homebrew updates available.${RESET}"
		return
	fi

	printf '%s\n%s\n\n' "${RED}Homebrew updates available:${RESET}" "${outdated}"
	if confirm "Upgrade Homebrew packages?"; then
		brew upgrade
		brew cleanup
	fi
}

#*****************************************************************************************
# routine to collect the Sparkle enabled applications whose appcast advertises a version
# other than the one installed, each entry is app|installed|latest|feed
#*****************************************************************************************
find_sparkle_updates() {
	local dir app plist feed_url installed_version feed latest_version

	for dir in "${APP_DIRS[@]}"; do
		[[ -d "${dir}" ]] || continue

		while IFS= read -r -d '' app; do
			plist="${app}/Contents/Info.plist"

			feed_url=$(defaults read "${plist}" SUFeedURL 2>/dev/null || true)
			if [[ -z "${feed_url}" ]]; then
				continue
			fi

			installed_version=$(defaults read "${plist}" CFBundleShortVersionString 2>/dev/null || echo "0")

			feed=$(curl -sL "${feed_url}")
			if [[ -z "${feed}" ]]; then
				continue
			fi

			latest_version=$(printf '%s' "${feed}" | grep -Eo '<sparkle:shortVersionString>[^<]+' | head -n1 | sed 's/<sparkle:shortVersionString>//')
			if [[ -z "${latest_version}" ]]; then
				latest_version=$(printf '%s' "${feed}" | grep -Eo 'sparkle:version="[^"]+"' | head -n1 | sed 's/sparkle:version="//;s/"//')
			fi

			if [[ "${installed_version}" != "${latest_version}" ]]; then
				sparkle_updates+=("${app}|${installed_version}|${latest_version}|${feed_url}")
			fi
		done < <(find "${dir}" -maxdepth 2 -name "*.app" -print0)
	done
}

#*****************************************************************************************
# routine to download the appcast enclosure for a single application and replace the
# installed copy with the newly downloaded one
#*****************************************************************************************
install_sparkle_update() {
	local app="${1}"
	local feed="${2}"
	local feed_xml download_url temp_file temp_dir new_app

	printf '%s\n' "${YELLOW}Updating $(basename "${app}")...${RESET}"

	feed_xml=$(curl -sL "${feed}")
	download_url=$(printf '%s' "${feed_xml}" | grep -Eo '<enclosure url="[^"]+"' | head -n1 | sed 's/<enclosure url="//;s/"//')

	temp_file=$(mktemp "/tmp/$(basename "${app}")-update-XXXXXX.zip")
	temp_dir=$(mktemp -d)
	temp_files+=("${temp_file}" "${temp_dir}")

	curl -L "${download_url}" -o "${temp_file}"
	unzip -q "${temp_file}" -d "${temp_dir}"

	new_app=$(find "${temp_dir}" -maxdepth 2 -name "*.app" | head -n1)
	if [[ -n "${new_app}" ]]; then
		printf '%s\n' "Installing update for $(basename "${app}")..."
		rm -rf "${app}"
		mv "${new_app}" "${app}"
	fi

	rm -rf "${temp_dir}" "${temp_file}"
}

#*****************************************************************************************
# routine to report the available Sparkle updates and optionally install them
#*****************************************************************************************
update_sparkle() {
	local entry app installed latest feed

	printf '%s\n' "${YELLOW}Checking Sparkle-enabled apps...${RESET}"
	find_sparkle_updates

	if [[ "${#sparkle_updates[@]}" -eq 0 ]]; then
		printf '%s\n' "${GREEN}No Sparkle updates available.${RESET}"
		return
	fi

	printf '%s\n' "${RED}Sparkle updates available:${RESET}"
	for entry in "${sparkle_updates[@]}"; do
		IFS="|" read -r app installed latest feed <<<"${entry}"
		printf '• %s: %s → %s\n' "$(basename "${app}")" "${installed}" "${latest}"
	done
	printf '\n'

	if confirm "Download Sparkle updates?"; then
		for entry in "${sparkle_updates[@]}"; do
			IFS="|" read -r app installed latest feed <<<"${entry}"
			install_sparkle_update "${app}" "${feed}"
		done
	fi
}

#*****************************************************************************************
# script main-line
#*****************************************************************************************
main() {
	trap cleanup EXIT

	printf '%s\n' "${GREEN}=== Unified macOS Update Utility ===${RESET}"

	update_system
	update_homebrew
	update_sparkle

	printf '\n%s\n' "${GREEN}All update checks complete.${RESET}"
}

main "${@}"
