#!/usr/bin/env bash
#*****************************************************************************************
# get_sudo_password
#
# This routine will prompt the user to enter their password to put the shell in super user
# mode for file I/O and command execution
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Sep-2026  4:42pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************
get_sudo_password() {
	local pw=""

	# Try keychain first
	pw=$(security find-generic-password -w -s '__my__Password__' -a "$USER" 2>/dev/null)

	# If keychain password exists AND works, return it
	if [[ -n $pw ]] && sudo --validate --stdin <<<"$pw" &>/dev/null; then
		echo "$pw"
		return
	fi

	# Otherwise prompt
	while true; do
		echo -n "Enter password for sudo: " >&2
		read -rs pw
		echo >&2
		if sudo --validate --stdin <<<"$pw" &>/dev/null; then
			echo "$pw"
			return
		fi
	done
}
