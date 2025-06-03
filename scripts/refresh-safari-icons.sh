#!/usr/bin/env bash
#*****************************************************************************************
# refresh-safari-icons.sh
#
# This script exists for the sillist of reason, that I don't like the black apple on a
# white circle fav icon. This script will download a saved copy of my preferred icon from
# my web server and install them in my Safari browser folder
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Jun-2025  3:54pm
# Modified :
#
# Copyright © 2025 By Gary Ash All rights reserved.
#*****************************************************************************************

password="$(security find-internet-password -ws geedbla.com)"

sshpass -p "$password" rsync -arz "$USER@geedbla.com:~/stuff/Safari/Safari.zip" "$HOME/Downloads/"
unzip -q "$HOME/Downloads/Safari.zip" -d "$HOME/Downloads/Safari/" -x '__MACOSX/*'

cp -rf "$HOME/Downloads/Safari/"* "$HOME/Library/Safari/"
rm -rf "$HOME/Downloads/Safari/"
rm -rf "$HOME/Downloads/Safari.zip"
