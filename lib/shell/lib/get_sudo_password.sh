#!/usr/bin/env bash
#*****************************************************************************************
# get_sudo_password
#
# This routine will prompt the user to enter their password to put the shell in super user
# mode for file I/O and command execution
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************
get_sudo_password() {
	local SUDO_PASSWORD
	if ! sudo --validate --non-interactive &>/dev/null; then

		SUDO_PASSWORD=$(security find-generic-password -w -s '__my__Password__' -a "$USER")
		if [[ -z $SUDO_PASSWORD ]]; then
			if ! sudo --validate --stdin <<<"$SUDO_PASSWORD" 2>/dev/null; then
				while true; do
					echo -n "Enter pasword for sudo: " >&2
					read -rs SUDO_PASSWORD
					echo "" >&2
					if sudo --validate --stdin <<<"$SUDO_PASSWORD" 2>/dev/null; then
						break
					fi
				done
			fi
		fi
	fi

	echo "$SUDO_PASSWORD"
}
