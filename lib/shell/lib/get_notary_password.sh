#!/usr/bin/env bash
#*****************************************************************************************
# get_notary_password
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
get_notary_password() {
	local NOTARY_PASSWORD
	NOTARY_PASSWORD=$(security find-generic-password -w -s '__my__NotaryPassword__' -a "$USER")

	if [[ -z $NOTARY_PASSWORD ]]; then
		echo -n "Enter password for notarizing service: " >&2
		read -rs NOTARY_PASSWORD
		echo "" >&2
	fi

	echo "$NOTARY_PASSWORD"
}
