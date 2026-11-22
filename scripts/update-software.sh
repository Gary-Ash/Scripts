#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# update-software.sh
#
# This script will check for and install macOS system, App Store, Homebrew, Claude Code,
# GitHub CLI extension, Ruby gem, Python pip package, npm global package and Sparkle
# enabled application updates, then sweep up the caches and file permissions left behind
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Sep-2026  4:42pm
# Modified :  21-Nov-2026  9:32pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# source in library functions
#*****************************************************************************************
source "/opt/geedbla/lib/shell/lib/log.sh"
source "/opt/geedbla/lib/shell/lib/get_sudo_password.sh"

readonly APP_DIRS=(
	"/Applications"
	"${HOME}/Applications"
)

readonly CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"

readonly CLEANUP_PATHS=(
	"${HOME}/.npm"
	"${HOME}/.gem"
	"${HOME}/.android"
	"${HOME}/.konan"
	"${HOME}/.gradle"
	"${HOME}/.swiftpm"
	"${HOME}/.hawtjni"
	"${CACHE_HOME}/zsh/history"
)

readonly SUDO_KEEPALIVE_SECONDS=20

approve_all=false
include_system_gems=false
sudo_keepalive_pid=""
system_gem=/usr/bin/gem
system_ruby=/usr/bin/ruby
sparkle_updates=()
temp_files=()

#*****************************************************************************************
# routine run on exit to stop the sudo keep-alive loop and remove any temporary files
# left behind by an interrupted Sparkle update
#*****************************************************************************************
cleanup() {
	local exit_code="${?}"
	local temp_file

	if [[ -n ${sudo_keepalive_pid} ]]; then
		kill "${sudo_keepalive_pid}" 2>/dev/null || true
	fi
	for temp_file in "${temp_files[@]}"; do
		sudo rm -rf "${temp_file}"
	done
	exit "${exit_code}"
}

#*****************************************************************************************
# routine to run a housekeeping command, showing its output only when it fails
#
# Cleanup is best effort - a step that fails is reported and counted, but the sweep
# carries on rather than taking the whole run down with it.
#*****************************************************************************************
run_quiet() {
	local out

	if ! out=$("${@}" 2>&1); then
		log_error "${1} failed"
		[[ -n ${out} ]] && printf '%s\n' "${out}" >&2
	fi
	return 0
}

#*****************************************************************************************
# routine to prompt the user for a yes/no answer, returns success for yes - with --all
# it returns success without prompting
#*****************************************************************************************
confirm() {
	local prompt="${1}"
	local answer

	if [[ ${approve_all} == true ]]; then
		return 0
	fi

	read -r -n 1 -p "${prompt} (y/N): " answer
	printf '\n'
	[[ ${answer} == "y" ]]
}

#*****************************************************************************************
# routine to validate sudo with the password from get_sudo_password, then start a
# background loop that keeps the sudo timestamp fresh, its pid in sudo_keepalive_pid
#*****************************************************************************************
start_sudo_keepalive() {
	local sudo_password
	sudo_password="$(get_sudo_password)"
	printf '%s\n' "${sudo_password}" | sudo --validate --stdin &>/dev/null

	while true; do
		sudo --non-interactive true
		sleep "${SUDO_KEEPALIVE_SECONDS}"
	done &
	sudo_keepalive_pid=$!
}

#*****************************************************************************************
# routine to check for and optionally install macOS system and App Store updates
#*****************************************************************************************
update_system() {
	local updates

	log_color "${LOG_YELLOW}" "Checking macOS system & App Store updates..."
	updates=$(softwareupdate -l 2>&1 | grep -E "Label:|recommended" || true)

	if [[ -z ${updates} ]]; then
		log_color "${LOG_GREEN}" "No macOS system/App Store updates available."
		return
	fi

	log_color "${LOG_RED}" "System/App Store updates available:"
	log_line "${updates}"
	log_line ""
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
		log_color "${LOG_YELLOW}" "Homebrew not installed — skipping brew updates."
		return
	fi

	log_color "${LOG_YELLOW}" "Checking Homebrew updates..."
	brew update >/dev/null

	outdated=$(brew outdated || true)
	if [[ -z ${outdated} ]]; then
		log_color "${LOG_GREEN}" "No Homebrew updates available."
		return
	fi

	log_color "${LOG_RED}" "Homebrew updates available:"
	log_line "${outdated}"
	log_line ""
	if confirm "Upgrade Homebrew packages?"; then
		brew upgrade --no-ask
		brew cleanup
	fi
}

#*****************************************************************************************
# routine to check for and optionally install a Claude Code update
#
# The Claude Code CLI folds the check and the install into a single command, so there is
# nothing to report ahead of the prompt beyond the version that is installed now.
#*****************************************************************************************
update_claude_code() {
	if ! command -v claude >/dev/null 2>&1; then
		log_color "${LOG_YELLOW}" "Claude Code not installed — skipping Claude Code updates."
		return
	fi

	log_color "${LOG_YELLOW}" "Checking Claude Code updates..."
	log_line "Installed version: $(claude --version 2>/dev/null || echo "unknown")"
	log_line ""

	if confirm "Check for and install a Claude Code update?"; then
		claude update
	fi
}

#*****************************************************************************************
# routine to check for and optionally install GitHub CLI extension updates
#*****************************************************************************************
update_gh_extensions() {
	local outdated

	if ! command -v gh >/dev/null 2>&1; then
		log_color "${LOG_YELLOW}" "GitHub CLI not installed — skipping extension updates."
		return
	fi

	if [[ -z $(gh extension list 2>/dev/null) ]]; then
		log_color "${LOG_GREEN}" "No GitHub CLI extensions installed."
		return
	fi

	log_color "${LOG_YELLOW}" "Checking GitHub CLI extension updates..."
	outdated=$(gh extension upgrade --all --dry-run 2>&1 | grep -v "already up to date" || true)

	if [[ -z ${outdated} ]]; then
		log_color "${LOG_GREEN}" "No GitHub CLI extension updates available."
		return
	fi

	log_color "${LOG_RED}" "GitHub CLI extension updates available:"
	log_line "${outdated}"
	log_line ""
	if confirm "Upgrade GitHub CLI extensions?"; then
		gh extension upgrade --all
	fi
}

#*****************************************************************************************
# routine to check for and optionally install Ruby gem updates
#*****************************************************************************************
update_ruby_gems() {
	local outdated

	if ! command -v gem >/dev/null 2>&1; then
		log_color "${LOG_YELLOW}" "Ruby gems not installed — skipping gem updates."
		return
	fi

	log_color "${LOG_YELLOW}" "Checking Ruby gem updates..."
	outdated=$(gem outdated 2>/dev/null || true)
	if [[ -z ${outdated} ]]; then
		log_color "${LOG_GREEN}" "No Ruby gem updates available."
		return
	fi

	log_color "${LOG_RED}" "Ruby gem updates available:"
	log_line "${outdated}"
	log_line ""
	if confirm "Upgrade Ruby gems?"; then
		gem update --system
		gem update
		gem cleanup
	fi
}

#*****************************************************************************************
# routine to check whether version VERSION of gem NAME runs on the system Ruby, returns
# success when the system Ruby and RubyGems satisfy the version's required Ruby and
# RubyGems versions
#*****************************************************************************************
system_gem_compatible() {
	local name="${1}"
	local version="${2}"

	curl -fsSL "https://rubygems.org/api/v2/rubygems/${name}/versions/${version}.json" |
		"${system_ruby}" -rjson -e '
			def satisfied?(requirement, version)
				return true if requirement.nil?
				Gem::Requirement.new(*requirement.split(",")).satisfied_by?(Gem::Version.new(version))
			end
			info = JSON.parse(STDIN.read)
			ruby_ok = satisfied?(info["ruby_version"], RUBY_VERSION)
			gems_ok = satisfied?(info["rubygems_version"], Gem::VERSION)
			exit(ruby_ok && gems_ok ? 0 : 1)'
}

#*****************************************************************************************
# routine to check for and optionally install system Ruby gem updates
#
# The macOS system Ruby keeps its gems in a root-owned directory, so the update and the
# cleanup run under sudo. Only gems whose latest version the system Ruby can run are
# listed and updated.
#*****************************************************************************************
update_system_gems() {
	local outdated line name latest compatible_lines=""
	local names=()

	if [[ ! -x ${system_gem} ]]; then
		log_color "${LOG_YELLOW}" "System Ruby gems not installed — skipping system gem updates."
		return
	fi

	log_color "${LOG_YELLOW}" "Checking system Ruby gem updates..."
	outdated=$("${system_gem}" outdated 2>/dev/null || true)
	if [[ -z ${outdated} ]]; then
		log_color "${LOG_GREEN}" "No system Ruby gem updates available."
		return
	fi

	while IFS= read -r line; do
		name="${line%% *}"
		latest="${line##*< }"
		latest="${latest%)}"
		if system_gem_compatible "${name}" "${latest}"; then
			names+=("${name}")
			compatible_lines+="${line}"$'\n'
		fi
	done <<<"${outdated}"
	if [[ ${#names[@]} -eq 0 ]]; then
		log_color "${LOG_GREEN}" "No compatible system Ruby gem updates available."
		return
	fi

	log_color "${LOG_RED}" "System Ruby gem updates available:"
	log_line "${compatible_lines%$'\n'}"
	log_line ""
	if confirm "Upgrade system Ruby gems?"; then
		sudo "${system_gem}" update "${names[@]}"
		sudo "${system_gem}" cleanup
	fi
}

#*****************************************************************************************
# routine to check for and optionally install Python package updates
#*****************************************************************************************
update_pip_packages() {
	local outdated line
	local names=()

	if ! command -v pip3 >/dev/null 2>&1; then
		log_color "${LOG_YELLOW}" "Python pip not installed — skipping Python package updates."
		return
	fi

	log_color "${LOG_YELLOW}" "Checking Python package updates..."
	outdated=$(pip3 list --outdated --format=freeze 2>/dev/null || true)
	if [[ -z ${outdated} ]]; then
		log_color "${LOG_GREEN}" "No Python package updates available."
		return
	fi

	log_color "${LOG_RED}" "Python package updates available:"
	log_line "${outdated}"
	log_line ""
	if confirm "Upgrade Python packages?"; then
		while IFS= read -r line; do
			names+=("${line%%==*}")
		done <<<"${outdated}"
		pip3 install --upgrade "${names[@]}"
	fi
}

#*****************************************************************************************
# routine to check for and optionally install npm global package updates
#*****************************************************************************************
update_npm_globals() {
	local outdated

	if ! command -v npm >/dev/null 2>&1; then
		log_color "${LOG_YELLOW}" "npm not installed — skipping npm global package updates."
		return
	fi

	log_color "${LOG_YELLOW}" "Checking npm global package updates..."
	outdated=$(npm outdated -g 2>/dev/null || true)
	if [[ -z ${outdated} ]]; then
		log_color "${LOG_GREEN}" "No npm global package updates available."
		return
	fi

	log_color "${LOG_RED}" "npm global package updates available:"
	log_line "${outdated}"
	log_line ""
	if confirm "Upgrade npm global packages?"; then
		npm update -g --dangerously-allow-all-scripts
	fi
}

#*****************************************************************************************
# routine to collect the Sparkle enabled applications whose appcast advertises a version
# other than the one installed, each entry is app|installed|latest|feed
#*****************************************************************************************
find_sparkle_updates() {
	local dir app plist feed_url installed_version feed latest_version

	for dir in "${APP_DIRS[@]}"; do
		[[ -d ${dir} ]] || continue

		while IFS= read -r -d '' app; do
			plist="${app}/Contents/Info.plist"

			feed_url=$(defaults read "${plist}" SUFeedURL 2>/dev/null || true)
			if [[ -z ${feed_url} ]]; then
				continue
			fi

			installed_version=$(defaults read "${plist}" CFBundleVersion 2>/dev/null || echo "0")

			feed=$(curl -sL "${feed_url}" || true)
			if [[ -z ${feed} ]]; then
				continue
			fi

			latest_version=$(printf '%s' "${feed}" | grep -Eo 'sparkle:version="[^"]+"' | head -n1 | sed 's/sparkle:version="//;s/"//' || true)
			if [[ -z ${latest_version} ]]; then
				latest_version=$(printf '%s' "${feed}" | grep -Eo '<sparkle:version>[^<]+' | head -n1 | sed 's/<sparkle:version>//' || true)
			fi

			if [[ -n ${latest_version} && ${installed_version} != "${latest_version}" ]]; then
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
	local feed_xml download_url temp_file temp_dir new_app backup

	log_color "${LOG_YELLOW}" "Updating $(basename "${app}")..."

	feed_xml=$(curl -sL "${feed}" || true)
	download_url=$(printf '%s' "${feed_xml}" | grep -Eo '<enclosure url="[^"]+"' | head -n1 | sed 's/<enclosure url="//;s/"//' || true)
	if [[ -z ${download_url} ]]; then
		LOG_STREAM=2 log_color "${LOG_RED}" "Could not find a download URL for $(basename "${app}") — skipping."
		return
	fi

	temp_file=$(mktemp "/tmp/$(basename "${app}")-update-XXXXXX.zip")
	temp_dir=$(mktemp -d)
	temp_files+=("${temp_file}" "${temp_dir}")

	curl -L "${download_url}" -o "${temp_file}"
	unzip -q "${temp_file}" -d "${temp_dir}"

	new_app=$(find "${temp_dir}" -maxdepth 2 -name "*.app" | head -n1 || true)
	if [[ -n ${new_app} ]]; then
		printf '%s\n' "Installing update for $(basename "${app}")..."
		backup="${app}.old-$$"

		mv "${app}" "${backup}"
		if mv "${new_app}" "${app}"; then
			rm -rf "${backup}"
		else
			LOG_STREAM=2 log_color "${LOG_RED}" "Install failed for $(basename "${app}") — restoring the previous version."
			mv "${backup}" "${app}"
		fi
	fi

	rm -rf "${temp_dir}" "${temp_file}"
}

#*****************************************************************************************
# routine to report the available Sparkle updates and optionally install them
#*****************************************************************************************
update_sparkle() {
	local entry app installed latest feed

	log_color "${LOG_YELLOW}" "Checking Sparkle-enabled apps..."
	find_sparkle_updates

	if [[ ${#sparkle_updates[@]} -eq 0 ]]; then
		log_color "${LOG_GREEN}" "No Sparkle updates available."
		return
	fi

	log_color "${LOG_RED}" "Sparkle updates available:"
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
# routine to sweep up after the updates - the package manager caches, the build tool
# state directories, the stray sync files and the ownership and quarantine flags that
# drift on /Applications
#*****************************************************************************************
update_cleanup() {
	local path dropbox_data

	log_color "${LOG_YELLOW}" "Cleaning up..."

	dropbox_data="${HOME}/Library/CloudStorage/Dropbox/Data"
	if [[ -d ${dropbox_data} ]]; then
		find "${dropbox_data}" -name "Keyboard Maestro Macros (*.kmsync" -delete 2>/dev/null || true
	fi
	pkill -f '.*GradleDaemon.*' >/dev/null 2>&1 || true

	for path in "${CLEANUP_PATHS[@]}"; do
		run_quiet rm -rf "${path}"
	done

	if command -v brew >/dev/null 2>&1; then
		export HOMEBREW_NO_ENV_HINTS=1
		export HOMEBREW_NO_INSTALL_CLEANUP=1
		export HOMEBREW_COLOR=0

		run_quiet brew autoremove --quiet
		run_quiet brew cleanup --quiet --scrub
		run_quiet rm -rf "$(brew --cache)"

		sudo xattr -cr /Applications/* >/dev/null 2>&1 || true
		sudo chown -R root:admin /Applications/* >/dev/null 2>&1 || true
		sudo chmod -R 775 /Applications/* >/dev/null 2>&1 || true
		sudo chown -R "${USER}:admin" /opt/geedbla/* >/dev/null 2>&1 || true
	fi

	# the guard keeps a stray or unset XDG_CACHE_HOME from turning this into rm -rf on
	# something that matters
	if [[ -n ${CACHE_HOME} && ${CACHE_HOME} != "/" && ${CACHE_HOME} != "${HOME}" ]]; then
		run_quiet rm -rf "${CACHE_HOME}"
		run_quiet mkdir -p "${CACHE_HOME}/zsh"
	fi

	log_color "${LOG_GREEN}" "Cleanup complete."
}

#*****************************************************************************************
# script main-line
#*****************************************************************************************
main() {
	while [[ $# -gt 0 ]]; do
		case $1 in
			--all)
				approve_all=true
				;;

			--system)
				include_system_gems=true
				;;

			*)
				echo "Unknown option -- $1" >&2
				exit 1
				;;
		esac
		shift
	done

	trap cleanup EXIT
	start_sudo_keepalive

	log_color "${LOG_GREEN}" "=== Unified macOS Update Utility ==="

	update_system
	update_homebrew
	update_claude_code
	update_gh_extensions
	update_ruby_gems
	if [[ ${include_system_gems} == true ]]; then
		update_system_gems
	fi
	update_pip_packages
	update_npm_globals
	update_sparkle
	update_cleanup

	log_line ""
	log_color "${LOG_GREEN}" "All update checks complete."
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	main "${@}"
fi
