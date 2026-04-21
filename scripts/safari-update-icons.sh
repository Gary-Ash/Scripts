#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# safari-update-icons.sh
#
# This script exists for the sillist of reason, that I don't like the black apple on a
# white circle fav icon. This script will update a saved copy of my preferred icon on
# my web server. I run it when I update my bookmarks
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :  21-Apr-2026  2:35pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

SAFARI_DIR="$HOME/Library/Safari"
REMOTE_HOST="geedbla.com"
REMOTE_DEST="~/stuff/Safari/Safari.zip"
USER_NAME="$USER"

# Create secure temp file
ZIP_FILE="$(mktemp -t Safari.XXXXXX).zip"

# Required directories
DIRS=(
	"Link Presentation Icons"
	"Favicon Cache"
	"Template Icons"
	"Touch Icons Cache"
)

# Get password from Apple Keychain
password="$(security find-internet-password -ws geedbla.com)"

# Build list of existing directories
existing_dirs=()
for d in "${DIRS[@]}"; do
	if [[ -d "$SAFARI_DIR/$d" ]]; then
		existing_dirs+=("$d")
	fi
done

if [[ ${#existing_dirs[@]} -eq 0 ]]; then
	echo "No Safari cache directories found."
	exit 1
fi

echo "Creating archive $ZIP_FILE"

(
	cd "$SAFARI_DIR"
	/usr/bin/zip -rq "$ZIP_FILE" "${existing_dirs[@]}"
)

echo "Uploading to $REMOTE_HOST"

expect <<EOF
set timeout -1
spawn scp "$ZIP_FILE" "${USER_NAME}@${REMOTE_HOST}:${REMOTE_DEST}"
expect {
    "*password:*" {
        send "$password\r"
    }
}
expect eof
EOF

scp_status=$?

if [[ $scp_status -eq 0 ]]; then
	rm -f "$ZIP_FILE"
	echo "Upload succeeded — local archive removed."
else
	echo "Upload failed — archive kept at $ZIP_FILE"
	exit 1
fi
