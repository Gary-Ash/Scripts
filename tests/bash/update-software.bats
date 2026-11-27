#!/usr/bin/env bats
#*****************************************************************************************
# update-software.bats
#
# Tests for update-software.sh, run against stub package manager commands placed first on
# PATH so nothing on the real machine is updated
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  17-Nov-2026  4:40pm
# Modified :  21-Nov-2026  9:28pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/update-software.sh"

setup() {
	# shellcheck source=/dev/null
	source "$SCRIPT"
	mkdir -p "$BATS_TEST_TMPDIR/bin"
	PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

teardown() {
	# stops a sudo keep-alive loop a test started
	if [[ -n ${sudo_keepalive_pid:-} ]]; then
		kill "$sudo_keepalive_pid" 2>/dev/null || true
	fi
}

# replaces the sourced get_sudo_password with one that answers s3cret, for a test that calls it
# in-process; each call also appends a line to $BATS_TEST_TMPDIR/get_sudo_password.calls, so a
# test can check it was never asked
stub_sudo_password() {
	get_sudo_password() {
		echo called >>"$BATS_TEST_TMPDIR/get_sudo_password.calls"
		echo s3cret
	}
}

# writes a sudo stub that logs each call's arguments to $BATS_TEST_TMPDIR/sudo.log and,
# for a --stdin call, appends what it reads to $BATS_TEST_TMPDIR/sudo.stdin
stub_logging_sudo() {
	local log stdin_log
	printf -v log '%q' "$BATS_TEST_TMPDIR/sudo.log"
	printf -v stdin_log '%q' "$BATS_TEST_TMPDIR/sudo.stdin"
	cat >"$BATS_TEST_TMPDIR/bin/sudo" <<-EOF
		#!/usr/bin/env bash
		printf '%s\n' "\$*" >>$log
		if [[ " \$* " == *" --stdin "* ]]; then
			cat >>$stdin_log
		fi
	EOF
	chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
	: >"$BATS_TEST_TMPDIR/sudo.log"
	: >"$BATS_TEST_TMPDIR/sudo.stdin"
}

# writes a sudo stub that logs each call's arguments to $BATS_TEST_TMPDIR/sudo.log and then
# runs the command it was given
stub_exec_sudo() {
	local log
	printf -v log '%q' "$BATS_TEST_TMPDIR/sudo.log"
	cat >"$BATS_TEST_TMPDIR/bin/sudo" <<-EOF
		#!/usr/bin/env bash
		printf '%s\n' "\$*" >>$log
		exec "\$@"
	EOF
	chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
	: >"$BATS_TEST_TMPDIR/sudo.log"
}

# writes a stub for command $1 that logs each call's arguments to
# $BATS_TEST_TMPDIR/$1.log and answers subcommand $2 with $3, exiting with status $4
# (default 0)
stub_command() {
	local command=$1 subcommand answer log status=${4:-0}
	printf -v subcommand '%q' "$2"
	printf -v answer '%q' "$3"
	printf -v log '%q' "$BATS_TEST_TMPDIR/$command.log"
	cat >"$BATS_TEST_TMPDIR/bin/$command" <<-EOF
		#!/usr/bin/env bash
		printf '%s\n' "\$*" >>$log
		if [[ "\$1" == $subcommand ]]; then
			printf '%s' $answer
			exit $status
		fi
	EOF
	chmod +x "$BATS_TEST_TMPDIR/bin/$command"
}

# writes a curl stub that, for each NAME VERSION JSON triple in $@, answers a request for
# https://rubygems.org/api/v2/rubygems/NAME/versions/VERSION.json with JSON, and fails any
# other request
stub_curl_versions() {
	local stub="$BATS_TEST_TMPDIR/bin/curl" url json
	cat >"$stub" <<-'EOF'
		#!/usr/bin/env bash
		for arg in "$@"; do
		case "$arg" in
	EOF
	while (($# >= 3)); do
		printf -v url '%q' "https://rubygems.org/api/v2/rubygems/$1/versions/$2.json"
		printf -v json '%q' "$3"
		printf '\t\t%s) printf "%%s\\n" %s; exit 0 ;;\n' "$url" "$json" >>"$stub"
		shift 3
	done
	printf '\tesac\ndone\nexit 22\n' >>"$stub"
	chmod +x "$stub"
}

# runs command $@ with only the test's stubs on PATH, and HOME pointing at the test's own
# space so the cleanup paths do too
run_with_test_env() {
	HOME="$BATS_TEST_TMPDIR" XDG_CACHE_HOME="$BATS_TEST_TMPDIR/.cache" PATH="$BATS_TEST_TMPDIR/bin" \
		run "$@"
}

# runs command $@ as run_with_test_env does, with a no-op sudo added to the stubs
run_isolated() {
	ln -s /usr/bin/true "$BATS_TEST_TMPDIR/bin/sudo"

	run_with_test_env "$@"
}

# runs the whole script with arguments $@ in the isolated environment
run_script() {
	run_isolated "$BASH" "$SCRIPT" "$@"
}

@test "outdated gems are updated and then cleaned up when confirmed" {
	stub_command gem outdated $'rubocop (1.92.2 < 1.92.3)\n'

	run update_ruby_gems <<<"y"

	[ "$status" -eq 0 ]
	[ "$(grep -x -e update -e cleanup "$BATS_TEST_TMPDIR/gem.log")" = $'update\ncleanup' ]
}

@test "gem update --system runs before gem update when confirmed" {
	stub_command gem outdated $'rubocop (1.92.2 < 1.92.3)\n'

	run update_ruby_gems <<<"y"

	[ "$status" -eq 0 ]
	[ "$(grep -x -e "update --system" -e update -e cleanup "$BATS_TEST_TMPDIR/gem.log")" = $'update --system\nupdate\ncleanup' ]
}

@test "no gem update runs when gem outdated reports nothing" {
	stub_command gem outdated ""

	run update_ruby_gems <<<"y"

	[ "$status" -eq 0 ]
	[ "$(grep -c -x -e update -e cleanup "$BATS_TEST_TMPDIR/gem.log")" -eq 0 ]
}

@test "gem updates are skipped when gem is not installed" {
	PATH="$BATS_TEST_TMPDIR/bin" run update_ruby_gems <<<"y"

	[ "$status" -eq 0 ]
	[ "$output" = "Ruby gems not installed — skipping gem updates." ]
}

@test "outdated system gems are updated and then cleaned up under sudo when confirmed" {
	stub_command gem outdated $'rexml (3.2.6 < 3.4.4)\n'
	stub_curl_versions rexml 3.4.4 '{"ruby_version":">= 2.5.0","rubygems_version":">= 0"}'
	system_gem="$BATS_TEST_TMPDIR/bin/gem"
	stub_exec_sudo

	run update_system_gems <<<"y"

	[ "$status" -eq 0 ]
	[ "$(grep -F -x -e "$system_gem update rexml" -e "$system_gem cleanup" "$BATS_TEST_TMPDIR/sudo.log")" = "$BATS_TEST_TMPDIR/bin/gem update rexml
$BATS_TEST_TMPDIR/bin/gem cleanup" ]
}

@test "no system gem update runs when the system gem outdated reports nothing" {
	stub_command gem outdated ""
	system_gem="$BATS_TEST_TMPDIR/bin/gem"
	stub_exec_sudo

	run update_system_gems <<<"y"

	[ "$status" -eq 0 ]
	[ "$(grep -c -x -e update -e cleanup "$BATS_TEST_TMPDIR/gem.log")" -eq 0 ]
	[ "$(grep -c -F -x -e "$system_gem update" -e "$system_gem cleanup" "$BATS_TEST_TMPDIR/sudo.log")" -eq 0 ]
}

@test "system gem updates are skipped when the system gem is not installed" {
	system_gem="$BATS_TEST_TMPDIR/bin/gem"

	run update_system_gems <<<"y"

	[ "$status" -eq 0 ]
	[ "$output" = "System Ruby gems not installed — skipping system gem updates." ]
}

@test "with --all outdated system gems are updated without an answer on stdin" {
	stub_command gem outdated $'rexml (3.2.6 < 3.4.4)\n'
	stub_curl_versions rexml 3.4.4 '{"ruby_version":">= 2.5.0","rubygems_version":">= 0"}'
	system_gem="$BATS_TEST_TMPDIR/bin/gem"
	stub_exec_sudo
	# shellcheck disable=SC2034
	approve_all=true

	run update_system_gems </dev/null

	[ "$status" -eq 0 ]
	[ "$(grep -F -x -e "$system_gem update rexml" -e "$system_gem cleanup" "$BATS_TEST_TMPDIR/sudo.log")" = "$BATS_TEST_TMPDIR/bin/gem update rexml
$BATS_TEST_TMPDIR/bin/gem cleanup" ]
}

@test "only the outdated system gems compatible with the system Ruby are updated when confirmed" {
	stub_command gem outdated $'rexml (3.2.6 < 3.4.4)\nnokogiri (1.13.8 < 1.19.7)\n'
	stub_curl_versions \
		rexml 3.4.4 '{"ruby_version":">= 2.5.0","rubygems_version":">= 0"}' \
		nokogiri 1.19.7 '{"ruby_version":">= 3.2","rubygems_version":">= 0"}'
	system_gem="$BATS_TEST_TMPDIR/bin/gem"
	stub_exec_sudo

	run update_system_gems <<<"y"

	[ "$status" -eq 0 ]
	[ "$(grep -F -e "$system_gem update" -e "$system_gem cleanup" "$BATS_TEST_TMPDIR/sudo.log")" = "$BATS_TEST_TMPDIR/bin/gem update rexml
$BATS_TEST_TMPDIR/bin/gem cleanup" ]
}

@test "when no outdated system gem is compatible, no system gem update runs and none is listed" {
	stub_command gem outdated $'nokogiri (1.13.8 < 1.19.7)\n'
	stub_curl_versions nokogiri 1.19.7 '{"ruby_version":">= 3.2","rubygems_version":">= 0"}'
	system_gem="$BATS_TEST_TMPDIR/bin/gem"
	stub_exec_sudo

	run update_system_gems <<<"y"

	[ "$status" -eq 0 ]
	[ "$(grep -c -F -e "$system_gem update" -e "$system_gem cleanup" "$BATS_TEST_TMPDIR/sudo.log")" -eq 0 ]
	[ "$output" = "Checking system Ruby gem updates...
No compatible system Ruby gem updates available." ]
}

@test "system_gem_compatible succeeds when the system Ruby satisfies the version's required Ruby version" {
	stub_curl_versions rexml 3.4.4 '{"number":"3.4.4","platform":"ruby","ruby_version":">= 2.5.0","rubygems_version":">= 0"}'

	run system_gem_compatible rexml 3.4.4

	[ "$status" -eq 0 ]
}

@test "system_gem_compatible fails when the version requires a newer Ruby than the system Ruby" {
	stub_curl_versions nokogiri 1.19.7 '{"number":"1.19.7","platform":"ruby","ruby_version":">= 3.2","rubygems_version":">= 0"}'

	run system_gem_compatible nokogiri 1.19.7

	[ "$status" -ne 0 ]
}

@test "system_gem_compatible fails when the version requires a newer RubyGems than the system's" {
	stub_curl_versions rexml 2.7.0 '{"number":"2.7.0","platform":"ruby","ruby_version":">= 2.5.0","rubygems_version":">= 3.3.22"}'

	run system_gem_compatible rexml 2.7.0

	[ "$status" -ne 0 ]
}

@test "system_gem_compatible treats a version with no ruby_version requirement as compatible" {
	stub_curl_versions rake 1.0.0 '{"number":"1.0.0","platform":"ruby","ruby_version":null,"rubygems_version":">= 0"}'

	run system_gem_compatible rake 1.0.0

	[ "$status" -eq 0 ]
}

@test "start_sudo_keepalive validates sudo by feeding the get_sudo_password password to sudo --validate --stdin" {
	stub_sudo_password
	stub_logging_sudo

	# called directly so the loop's pid stays visible to teardown; fd 3 is closed so the
	# loop cannot keep bats waiting
	start_sudo_keepalive 3>&-

	grep -x -e "--validate --stdin" "$BATS_TEST_TMPDIR/sudo.log"
	[ "$(cat "$BATS_TEST_TMPDIR/sudo.stdin")" = "s3cret" ]
}

@test "start_sudo_keepalive starts a background loop that refreshes the timestamp with sudo --non-interactive true" {
	stub_sudo_password
	stub_logging_sudo

	# called directly so the loop's pid stays visible to teardown; fd 3 is closed so the
	# loop cannot keep bats waiting
	start_sudo_keepalive 3>&-
	# the loop's first refresh runs at once, but in the background, so wait up to 5 seconds
	for _ in {1..50}; do
		grep -q -x -e "--non-interactive true" "$BATS_TEST_TMPDIR/sudo.log" && break
		sleep 0.1
	done

	grep -x -e "--non-interactive true" "$BATS_TEST_TMPDIR/sudo.log"
}

@test "cleanup stops the keep-alive loop" {
	stub_sudo_password
	stub_logging_sudo
	# a stand-in for the loop, started from a command substitution so it is not this
	# shell's child: once killed it is reaped at once instead of lingering as a zombie
	# that kill -0 still finds
	sudo_keepalive_pid=$(
		sleep 30 >/dev/null 2>&1 3>&- &
		echo $!
	)

	run cleanup
	# the stand-in may take a moment to be reaped, so wait up to 5 seconds
	for _ in {1..50}; do
		kill -0 "$sudo_keepalive_pid" 2>/dev/null || break
		sleep 0.1
	done

	run kill -0 "$sudo_keepalive_pid"
	[ "$status" -ne 0 ]
}

@test "cleanup removes the Sparkle temp files under sudo without asking for the password again" {
	stub_sudo_password
	stub_exec_sudo
	mkdir "$BATS_TEST_TMPDIR/sparkle.XXXX"
	touch "$BATS_TEST_TMPDIR/sparkle.XXXX/App.dmg"
	# shellcheck disable=SC2034
	temp_files=("$BATS_TEST_TMPDIR/sparkle.XXXX/App.dmg" "$BATS_TEST_TMPDIR/sparkle.XXXX")

	run cleanup

	[ ! -e "$BATS_TEST_TMPDIR/get_sudo_password.calls" ]
	[ "$(cat "$BATS_TEST_TMPDIR/sudo.log")" = "rm -rf $BATS_TEST_TMPDIR/sparkle.XXXX/App.dmg
rm -rf $BATS_TEST_TMPDIR/sparkle.XXXX" ]
	[ ! -e "$BATS_TEST_TMPDIR/sparkle.XXXX" ]
}

@test "update_cleanup repairs /Applications under sudo without asking for the password again" {
	# the sudo stub only logs, so nothing in /Applications is changed; PATH holds only the
	# stubs and bash, so rm, mkdir, find, and pkill are not found and nothing is removed;
	# HOME and XDG_CACHE_HOME point at the test's own space before the script is sourced,
	# so the cleanup paths it computes do too
	ln -s "$BASH" "$BATS_TEST_TMPDIR/bin/bash"
	stub_logging_sudo
	stub_command brew --cache "$BATS_TEST_TMPDIR/brew-cache"

	# shellcheck disable=SC2016 # $1 and $2 expand in the inner bash
	run_with_test_env bash -c 'source "$1"
			calls="$2/get_sudo_password.calls"
			get_sudo_password() {
				echo called >>"$calls"
				echo s3cret
			}
			update_cleanup' _ "$SCRIPT" "$BATS_TEST_TMPDIR"

	[ ! -e "$BATS_TEST_TMPDIR/get_sudo_password.calls" ]
	[ "$(grep -o -e '^xattr -cr /Applications/' -e '^chown -R root:admin /Applications/' -e '^chmod -R 775 /Applications/' "$BATS_TEST_TMPDIR/sudo.log")" = "xattr -cr /Applications/
chown -R root:admin /Applications/
chmod -R 775 /Applications/" ]
}

@test "outdated pip packages are upgraded when confirmed" {
	stub_command pip3 list $'platformdirs==4.14.5\nrequests==2.32.0\n'

	run update_pip_packages <<<"y"

	[ "$status" -eq 0 ]
	grep -x -e "install --upgrade platformdirs requests" "$BATS_TEST_TMPDIR/pip3.log"
}

@test "no pip upgrade runs when pip3 list --outdated reports nothing" {
	stub_command pip3 list ""

	run update_pip_packages <<<"y"

	[ "$status" -eq 0 ]
	[ "$(grep -c '^install' "$BATS_TEST_TMPDIR/pip3.log")" -eq 0 ]
}

@test "pip updates are skipped when pip3 is not installed" {
	PATH="$BATS_TEST_TMPDIR/bin" run update_pip_packages <<<"y"

	[ "$status" -eq 0 ]
	[ "$output" = "Python pip not installed — skipping Python package updates." ]
}

@test "outdated npm globals are updated when confirmed" {
	stub_command npm outdated $'Package               Current  Wanted  Latest  Location                            Depended by\nbash-language-server    5.6.0   5.8.1   5.8.1  node_modules/bash-language-server  global\n' 1

	# a fresh bash keeps the script's set -e, which bats run turns off
	run bash -c 'source "$1"; update_npm_globals' _ "$SCRIPT" <<<"y"

	[ "$status" -eq 0 ]
	grep -x -e "update -g --dangerously-allow-all-scripts" "$BATS_TEST_TMPDIR/npm.log"
}

@test "no npm update runs when npm outdated -g reports nothing" {
	stub_command npm outdated ""

	run bash -c 'source "$1"; update_npm_globals' _ "$SCRIPT" <<<"y"

	[ "$status" -eq 0 ]
	[ "$(grep -c '^update' "$BATS_TEST_TMPDIR/npm.log")" -eq 0 ]
}

@test "npm updates are skipped when npm is not installed" {
	PATH="$BATS_TEST_TMPDIR/bin" run update_npm_globals <<<"y"

	[ "$status" -eq 0 ]
	[ "$output" = "npm not installed — skipping npm global package updates." ]
}

@test "main runs the gem, pip, and npm updates" {
	# no stubs are written and the system gem points at a missing path, so every update
	# finds its tool missing, and a system gem update would report its line too
	ln -s "$BASH" "$BATS_TEST_TMPDIR/bin/bash"

	# shellcheck disable=SC2016 # $1 and $2 expand in the inner bash
	run_isolated bash -c 'source "$1"; system_gem="$2"; main' _ "$SCRIPT" "$BATS_TEST_TMPDIR/bin/gem" <<<""

	[ "$status" -eq 0 ]
	[ "$(grep -e "not installed" -e "Checking Sparkle" <<<"$output")" = "Homebrew not installed — skipping brew updates.
Claude Code not installed — skipping Claude Code updates.
GitHub CLI not installed — skipping extension updates.
Ruby gems not installed — skipping gem updates.
Python pip not installed — skipping Python package updates.
npm not installed — skipping npm global package updates.
Checking Sparkle-enabled apps..." ]
}

@test "with --system main runs the system gem update after the gem update" {
	# no stubs are written and the system gem points at a missing path, so each update
	# reports its tool missing, in the order main runs them
	ln -s "$BASH" "$BATS_TEST_TMPDIR/bin/bash"

	# shellcheck disable=SC2016 # $1 and $2 expand in the inner bash
	run_isolated bash -c 'source "$1"; system_gem="$2"; main --system' _ "$SCRIPT" "$BATS_TEST_TMPDIR/bin/gem" <<<""

	[ "$status" -eq 0 ]
	[ "$(grep -e "gems not installed" <<<"$output")" = "Ruby gems not installed — skipping gem updates.
System Ruby gems not installed — skipping system gem updates." ]
}

@test "main obtains sudo before the first update runs" {
	# the system update is the first one main runs; its softwareupdate stub logs to sudo.log
	# too, so the order of the two shows there
	stub_logging_sudo
	local log
	printf -v log '%q' "$BATS_TEST_TMPDIR/sudo.log"
	cat >"$BATS_TEST_TMPDIR/bin/softwareupdate" <<-EOF
		#!/usr/bin/env bash
		printf 'softwareupdate %s\n' "\$*" >>$log
	EOF
	chmod +x "$BATS_TEST_TMPDIR/bin/softwareupdate"
	ln -s "$BASH" "$BATS_TEST_TMPDIR/bin/bash"
	ln -s /bin/sleep "$BATS_TEST_TMPDIR/bin/sleep"
	ln -s /bin/cat "$BATS_TEST_TMPDIR/bin/cat"

	# fd 3 is closed so a keep-alive loop cannot keep bats waiting
	# shellcheck disable=SC2016 # $1 and $2 expand in the inner bash
	run_with_test_env bash -c 'source "$1"; system_gem="$2"; main' _ "$SCRIPT" "$BATS_TEST_TMPDIR/bin/gem" <<<"" 3>&-

	[ "$(grep -m 1 -e '^--validate' -e '^softwareupdate' "$BATS_TEST_TMPDIR/sudo.log")" = "--validate --stdin" ]
}

@test "with --all outdated gems are updated without an answer on stdin" {
	stub_command gem outdated $'rubocop (1.92.2 < 1.92.3)\n'
	ln -s "$BASH" "$BATS_TEST_TMPDIR/bin/bash"

	run_script --all </dev/null

	[ "$status" -eq 0 ]
	grep -x update "$BATS_TEST_TMPDIR/gem.log"
}

@test "an unknown argument is reported and the script exits non-zero" {
	run_script --bogus <<<""

	[ "$status" -eq 1 ]
	grep -x -e "Unknown option -- --bogus" <<<"$output"
}
