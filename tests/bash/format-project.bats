#!/usr/bin/env bats
#*****************************************************************************************
# format-project.bats
#
# Tests for format-project.sh, run against a scratch project directory
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  11-Nov-2026  8:36pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/format-project.sh"

@test "keeps the zsh commands lookup intact in a zsh script" {
	local project="$BATS_TEST_TMPDIR/project"
	mkdir -p "$project"
	printf '#!/usr/bin/env zsh\nif (( $+commands[bat] )); then\n\techo yes\nfi\n' >"$project/aliases.sh"

	run "$SCRIPT" "$project"

	[ "$status" -eq 0 ]
	run cat "$project/aliases.sh"
	[[ $output == *'$+commands[bat]'* ]]
	[[ $output != *'$ + commands'* ]]
}
