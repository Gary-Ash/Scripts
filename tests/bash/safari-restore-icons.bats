#!/usr/bin/env bats
#*****************************************************************************************
# safari-restore-icons.bats
#
# Tests for safari-restore-icons.sh, run against stand-ins for scp and the keychain and a
# scratch directory standing in for $HOME
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  24-Oct-2026  8:03pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

# fake_scp bodies are the stand-in's source, so they are single-quoted on purpose
# shellcheck disable=SC2016
SCRIPT="$BATS_TEST_DIRNAME/../../scripts/safari-restore-icons.sh"

# a hang must fail the test rather than stall the suite
# shellcheck disable=SC2034  # read by bats
BATS_TEST_TIMEOUT=20

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME/Library/Safari"

	local bin="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$bin"
	export PATH="$bin:$PATH"

	printf '#!/usr/bin/env bash\nprintf "secret\\n"\n' >"$bin/security"
	chmod +x "$bin/security"

	local payload="$BATS_TEST_TMPDIR/payload"
	mkdir -p "$payload/Favicon Cache"
	printf 'icon\n' >"$payload/Favicon Cache/icon.png"
	(cd "$payload" && zip -qr "$BATS_TEST_TMPDIR/Safari.zip" .)
	export FAKE_ZIP="$BATS_TEST_TMPDIR/Safari.zip"
}

fake_scp() {
	printf '#!/usr/bin/env bash\n%s\n' "$1" >"$BATS_TEST_TMPDIR/bin/scp"
	chmod +x "$BATS_TEST_TMPDIR/bin/scp"
}

@test "installs the icons when the password is accepted" {
	fake_scp 'printf "password: "; read -r pw; [[ $pw == secret ]] && cp "$FAKE_ZIP" "$2"'

	run "$SCRIPT"

	[ "$status" -eq 0 ]
	[ -f "$HOME/Library/Safari/Favicon Cache/icon.png" ]
}

@test "fails instead of hanging when the password is rejected" {
	fake_scp 'while true; do printf "password: "; read -r pw; printf "\nPermission denied, please try again.\n"; done'

	run "$SCRIPT"

	[ "$status" -ne 0 ]
}
