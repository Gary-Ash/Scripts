#!/usr/bin/env bash
#*****************************************************************************************
# refresh-safari-icons.sh
#
# This script exists for the sillist of reason, that I don't like the black apple on a
# white circle fav icon. This script will download a saved copy of my preferred icon from
# my web server and install them in my Safari browser folder
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   4-Aug-2025  4:29pm
# Modified :   2-Sep-2025  5:00pm
#
# Copyright © 2025 By Gary Ash All rights reserved.
#*****************************************************************************************

password="$(security find-internet-password -ws geedbla.com)"

sshpass -p "$password" rsync -arz "$USER@geedbla.com:~/stuff/Safari/Safari.zip" "$HOME/Downloads/"
unzip -q "$HOME/Downloads/Safari.zip" -d "$HOME/Downloads/" -x '__MACOSX/*' &>/dev/null

cp -rf "$HOME/Downloads/Safari/"* "$HOME/Library/Safari/" &>/dev/null
rm -rf "$HOME/Downloads/Safari/" &>/dev/null
rm -rf "$HOME/Downloads/Safari.zip" &>/dev/null
