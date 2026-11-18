#!/usr/bin/env bats
#*****************************************************************************************
# update-software.bats
#
# Tests for update-software.sh, run against stub package manager commands placed first on
# PATH so nothing on the real machine is updated
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  17-Nov-2026  4:40pm
# Modified :  17-Nov-2026  9:01pm
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

# runs the whole script with arguments $@, with only the test's stubs and a no-op sudo on
# PATH, and HOME pointing at the test's own space so the cleanup paths do too
run_script() {
	ln -s /usr/bin/true "$BATS_TEST_TMPDIR/bin/sudo"

	HOME="$BATS_TEST_TMPDIR" XDG_CACHE_HOME="$BATS_TEST_TMPDIR/.cache" PATH="$BATS_TEST_TMPDIR/bin" \
		run "$BASH" "$SCRIPT" "$@"
}

@test "outdated gems are updated and then cleaned up when confirmed" {
	stub_command gem outdated $'rubocop (1.92.2 < 1.92.3)\n'

	run update_ruby_gems <<<"y"

	[ "$status" -eq 0 ]
	[ "$(grep -x -e update -e cleanup "$BATS_TEST_TMPDIR/gem.log")" = $'update\ncleanup' ]
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
	# no stubs are written, so every update finds its tool missing
	run_script <<<""

	[ "$status" -eq 0 ]
	[ "$(grep -e "not installed" -e "Checking Sparkle" <<<"$output")" = "Homebrew not installed — skipping brew updates.
Claude Code not installed — skipping Claude Code updates.
GitHub CLI not installed — skipping extension updates.
Ruby gems not installed — skipping gem updates.
Python pip not installed — skipping Python package updates.
npm not installed — skipping npm global package updates.
Checking Sparkle-enabled apps..." ]
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
