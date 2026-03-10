#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# refresh-safari-icons.sh
#
# This script exists for the sillist of reason, that I don't like the black apple on a
# white circle fav icon. This script will download a saved copy of my preferred icon from
# my web server and install them in my Safari browser folder
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :  11-Mar-2026  5:54pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

SAFARI_DIR="$HOME/Library/Safari"
REMOTE_HOST="geedbla.com"
REMOTE_FILE="~/stuff/Safari/Safari.zip"
USER_NAME="$USER"

ZIP_FILE="$(mktemp -t SafariDownload.XXXXXX).zip"

DIRS=(
"Link Presentation Icons"
"Favicon Cache"
"Template Icons"
"Touch Icons Cache"
)

# Retrieve password from Keychain
password="$(security find-internet-password -ws geedbla.com)"

echo "Downloading Safari.zip from $REMOTE_HOST"

expect <<EOF
set timeout -1
spawn scp ${USER_NAME}@${REMOTE_HOST}:${REMOTE_FILE} "$ZIP_FILE"
expect {
    "*password:*" {
        send "$password\r"
    }
}
expect eof
EOF

if [[ ! -s "$ZIP_FILE" ]]; then
    echo "Download failed."
    rm -f "$ZIP_FILE"
    exit 1
fi

echo "Removing existing Safari cache folders"

for d in "${DIRS[@]}"; do
    rm -rf "${SAFARI_DIR:?}/$d"
done

echo "Extracting archive"

unzip -q "$ZIP_FILE" -d "$SAFARI_DIR"

echo "Cleaning up"
rm -f "$ZIP_FILE"

echo "Safari cache restore complete."
