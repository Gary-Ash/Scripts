#!/usr/bin/env bats
#*****************************************************************************************
# update-ai-tools.bats
#
# Tests for update-ai-tools.sh, run against a local bare repository standing in for
# GitHub and a scratch directory standing in for ~/.claude
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  15-Oct-2026  9:55pm
# Modified :  15-Oct-2026 10:21pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

SCRIPT="$BATS_TEST_DIRNAME/../scripts/update-ai-tools.sh"

setup() {
	export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
	export GIT_CONFIG_NOSYSTEM=1
	git config --global user.name "Test"
	git config --global user.email "test@example.com"
	git config --global commit.gpgsign false
	git config --global init.defaultBranch main

	export AI_TOOLS_REPO="$BATS_TEST_TMPDIR/remote.git"
	export AI_TOOLS_DIR="$BATS_TEST_TMPDIR/AI-Tools"
	export CLAUDE_DIR="$BATS_TEST_TMPDIR/claude"

	# stands in for BBEdit, writing $COMMIT_MESSAGE as the message being edited
	export COMMIT_MESSAGE="message"
	export EDITOR="$BATS_TEST_TMPDIR/editor"
	printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$COMMIT_MESSAGE" >"$1"\n' >"$EDITOR"
	chmod +x "$EDITOR"

	git init --quiet --bare "$AI_TOOLS_REPO"

	local seed="$BATS_TEST_TMPDIR/seed"
	git clone --quiet "$AI_TOOLS_REPO" "$seed" 2>/dev/null
	mkdir -p "$seed/skills/bash-skill"
	printf 'old guidelines\n' >"$seed/CLAUDE.md"
	printf 'old statusline\n' >"$seed/statusline.pl"
	printf 'old bash skill\n' >"$seed/skills/bash-skill/SKILL.md"
	printf 'readme\n' >"$seed/Readme.md"
	git -C "$seed" add -A
	git -C "$seed" commit --quiet -m "seed"
	git -C "$seed" push --quiet origin main

	mkdir -p "$CLAUDE_DIR/skills/bash-skill"
	printf 'old guidelines\n' >"$CLAUDE_DIR/CLAUDE.md"
	printf 'old statusline\n' >"$CLAUDE_DIR/statusline.pl"
	printf 'old bash skill\n' >"$CLAUDE_DIR/skills/bash-skill/SKILL.md"
}

remote_file() {
	git --git-dir="$AI_TOOLS_REPO" show "main:$1"
}

@test "pushes a changed CLAUDE.md to GitHub" {
	printf 'new guidelines\n' >"$CLAUDE_DIR/CLAUDE.md"

	run "$SCRIPT"

	[ "$status" -eq 0 ]
	[ "$(remote_file CLAUDE.md)" = "new guidelines" ]
}

@test "mirrors a published skill, including files deleted locally" {
	git clone --quiet "$AI_TOOLS_REPO" "$BATS_TEST_TMPDIR/extra"
	printf 'gone\n' >"$BATS_TEST_TMPDIR/extra/skills/bash-skill/old.md"
	git -C "$BATS_TEST_TMPDIR/extra" add -A
	git -C "$BATS_TEST_TMPDIR/extra" commit --quiet -m "extra"
	git -C "$BATS_TEST_TMPDIR/extra" push --quiet
	printf 'new bash skill\n' >"$CLAUDE_DIR/skills/bash-skill/SKILL.md"

	run "$SCRIPT"

	[ "$status" -eq 0 ]
	[ "$(remote_file skills/bash-skill/SKILL.md)" = "new bash skill" ]
	run remote_file skills/bash-skill/old.md
	[ "$status" -ne 0 ]
}

@test "succeeds without committing when nothing has changed" {
	run "$SCRIPT"

	[ "$status" -eq 0 ]
	[ "$(git --git-dir="$AI_TOOLS_REPO" rev-list --count main)" -eq 1 ]
}

@test "does not publish a skill that is not on the list" {
	mkdir -p "$CLAUDE_DIR/skills/snippetslab"
	printf 'third party\n' >"$CLAUDE_DIR/skills/snippetslab/SKILL.md"
	printf 'new guidelines\n' >"$CLAUDE_DIR/CLAUDE.md"

	run "$SCRIPT"

	[ "$status" -eq 0 ]
	run remote_file skills/snippetslab/SKILL.md
	[ "$status" -ne 0 ]
}

@test "--package builds the working copy without pushing it" {
	printf 'new guidelines\n' >"$CLAUDE_DIR/CLAUDE.md"

	run "$SCRIPT" --package

	[ "$status" -eq 0 ]
	[ "$(cat "$AI_TOOLS_DIR/CLAUDE.md")" = "new guidelines" ]
	[ "$(remote_file CLAUDE.md)" = "old guidelines" ]
}

@test "rejects an unknown option" {
	run "$SCRIPT" --bogus

	[ "$status" -eq 1 ]
	[ "$(git --git-dir="$AI_TOOLS_REPO" rev-list --count main)" -eq 1 ]
}

@test "commits with the message written in the editor" {
	printf 'new guidelines\n' >"$CLAUDE_DIR/CLAUDE.md"
	COMMIT_MESSAGE="[FEATURE] Tighten the guidelines"

	run "$SCRIPT"

	[ "$status" -eq 0 ]
	[ "$(git --git-dir="$AI_TOOLS_REPO" log -1 --format=%s main)" = "[FEATURE] Tighten the guidelines" ]
}

@test "pushes nothing when the commit message is left blank" {
	printf 'new guidelines\n' >"$CLAUDE_DIR/CLAUDE.md"

	COMMIT_MESSAGE=""

	run "$SCRIPT"

	[ "$status" -eq 1 ]
	[ "$(remote_file CLAUDE.md)" = "old guidelines" ]
}
