#!/usr/bin/env bats
#*****************************************************************************************
# update-dots.bats
#
# Tests for update-dots.sh, run against a scratch directory standing in for $HOME with
# the tools the script calls by name replaced by no-op stubs
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  13-Nov-2026 10:10pm
# Modified :  13-Nov-2026 10:22pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/update-dots.sh"

setup() {
	export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
	export GIT_CONFIG_NOSYSTEM=1

	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME/Downloads"

	# stand-ins for the tools the script calls by name, so the real repository,
	# Homebrew and the package managers are left alone
	local bin="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$bin"
	local tool
	for tool in format-project.sh brew gem pip3 npm generate-gitkeep.sh; do
		printf '#!/usr/bin/env bash\nexit 0\n' >"$bin/$tool"
		chmod +x "$bin/$tool"
	done
	export PATH="$bin:$PATH"
}

@test "a file deleted from a dot folder in HOME is removed from the repo copy" {
	mkdir -p "$HOME/.config/tool"
	printf 'keep\n' >"$HOME/.config/tool/keep.conf"
	local copy="$HOME/Downloads/dotfiles/home/.config/tool"
	mkdir -p "$copy"
	printf 'keep\n' >"$copy/keep.conf"
	printf 'gone\n' >"$copy/gone.conf"

	run "$SCRIPT" --package

	[ "$status" -eq 0 ]
	[ ! -e "$copy/gone.conf" ]
	[ -f "$copy/keep.conf" ]
}

@test "a dot file deleted from HOME is removed from the repo copy" {
	printf 'keep\n' >"$HOME/.keeprc"
	local copy="$HOME/Downloads/dotfiles/home"
	mkdir -p "$copy"
	printf 'keep\n' >"$copy/.keeprc"
	printf 'gone\n' >"$copy/.oldrc"

	run "$SCRIPT" --package

	[ "$status" -eq 0 ]
	[ ! -e "$copy/.oldrc" ]
	[ -f "$copy/.keeprc" ]
}

@test "a dot folder deleted from HOME is removed from the repo copy" {
	mkdir -p "$HOME/.keeptool"
	printf 'keep\n' >"$HOME/.keeptool/config"
	local copy="$HOME/Downloads/dotfiles/home"
	mkdir -p "$copy/.keeptool" "$copy/.oldtool"
	printf 'keep\n' >"$copy/.keeptool/config"
	printf 'gone\n' >"$copy/.oldtool/config"

	run "$SCRIPT" --package

	[ "$status" -eq 0 ]
	[ ! -e "$copy/.oldtool" ]
	[ -f "$copy/.keeptool/config" ]
}

@test "an ignored path already in the repo copy is kept" {
	mkdir -p "$HOME/.claude"
	printf '{}\n' >"$HOME/.claude/settings.json"
	local copy="$HOME/Downloads/dotfiles/home/.claude/skills/bash-skill"
	mkdir -p "$copy"
	printf 'skill\n' >"$copy/SKILL.md"

	run "$SCRIPT" --package

	[ "$status" -eq 0 ]
	[ -f "$copy/SKILL.md" ]
}

@test "a dangling symlink in HOME keeps its repo copy" {
	ln -s "$HOME/missing" "$HOME/.linkrc"
	local copy="$HOME/Downloads/dotfiles/home"
	mkdir -p "$copy"
	printf 'link\n' >"$copy/.linkrc"

	run "$SCRIPT" --package

	[ "$status" -eq 0 ]
	[ -e "$copy/.linkrc" ] || [ -L "$copy/.linkrc" ]
}

@test "a file deleted from the Xcode folder in HOME is removed from the repo copy" {
	mkdir -p "$HOME/Library/Developer/Xcode/UserData/KeyBindings"
	printf 'keep\n' >"$HOME/Library/Developer/Xcode/UserData/KeyBindings/keep.idekeybindings"
	local copy="$HOME/Downloads/dotfiles/xcode/UserData/KeyBindings"
	mkdir -p "$copy"
	printf 'keep\n' >"$copy/keep.idekeybindings"
	printf 'gone\n' >"$copy/gone.idekeybindings"

	run "$SCRIPT" --package

	[ "$status" -eq 0 ]
	[ ! -e "$copy/gone.idekeybindings" ]
	[ -f "$copy/keep.idekeybindings" ]
}
