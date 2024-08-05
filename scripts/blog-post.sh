#!/usr/bin/env zsh
#*****************************************************************************************
# blog-post.sh
#
# This script is used to create blog post.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   5-Aug-2024  7:21pm
# Modified :
#
# Copyright © 2024 By Gary Ash All rights reserved.
#*****************************************************************************************

if [[ $# -ne 2 ]]; then
	echo 'Command error - expected  <blog or product> "Blog entry title"' 1>&2
	exit 2
fi
if [[ $1 != "blog" && $1 != "products" ]]; then
	echo "unknown website entry type." 1>&2
	echo 'Command error - expected  <blog or product> base filename "Blog entry title"' 1>&2
	exit 2
fi

mkdir -p "$HOME/Sites/geedbla/_blog" &>/dev/null
mkdir -p "$HOME/Sites/geedbla/_product" &>/dev/null

dateStamp=$(date +"%Y-%m-%d-%H%M%S%z")
timestamp=$(date +"%Y-%m-%d %H:%M:%S %z")

n=1
name="$1"
while [ -f "$name" ]; do
	$((++n))
	name="$1-$n"
done

at <<EOF >"$HOME/Sites/geedbla/_$1/$dateStamp-$name.markdown"
---
layout: $1-post
title:  "$2"
date:   $timestamp
collection: $1
---
EOF

rm -rf "$HOME/Sites/geedbla/_$1/.gitkeep"
