#!/usr/bin/env bats
#*****************************************************************************************
# get_sudo_password.bats
#
# Tests for get_sudo_password.sh, run against stub security and sudo commands placed first
# on PATH so the real keychain and sudo are never touched
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  17-Nov-2026  8:32pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

LIB="$BATS_TEST_DIRNAME/../../lib/shell/lib/get_sudo_password.sh"

setup() {
	mkdir -p "$BATS_TEST_TMPDIR/bin"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$BATS_TEST_TMPDIR/bin/security"
	chmod +x "$BATS_TEST_TMPDIR/bin/security"
	PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	export PATH
}

@test "the prompt loop gives up with an empty password when stdin reaches EOF" {
	printf '#!/usr/bin/env bash\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/sudo"
	chmod +x "$BATS_TEST_TMPDIR/bin/sudo"

	run /usr/bin/timeout 5 bash -c "source \"\$1\"; get_sudo_password 2>/dev/null" _ "$LIB" </dev/null

	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "a last line with no trailing newline is still tried as the password" {
	cat >"$BATS_TEST_TMPDIR/bin/sudo" <<-'STUB'
		#!/usr/bin/env bash
		read -r pw
		[[ $pw == secret ]]
	STUB
	chmod +x "$BATS_TEST_TMPDIR/bin/sudo"

	run /usr/bin/timeout 5 bash -c "source \"\$1\"; printf 'secret' | get_sudo_password 2>/dev/null" _ "$LIB"

	[ "$status" -eq 0 ]
	[ "$output" = "secret" ]
}
