#!/usr/bin/env zsh
#*****************************************************************************************
# blog-post.sh
#
# This script is used to create blog post.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   9-Oct-2024  3:09pm
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

mkdir -p "$HOME/Sites/geedbla.com/_blog" &>/dev/null
mkdir -p "$HOME/Sites/geedbla.com/_product" &>/dev/null

dateStamp=$(date +"%Y-%m-%d-%H%M%S%z")
timestamp=$(date +"%Y-%m-%d %H:%M:%S %z")

n=1
name="$1"
while [ -f "$name" ]; do
	$((++n))
	name="$1-$n"
done

cat <<EOF >"$HOME/Sites/geedbla.com/_$1/$dateStamp-$name.markdown"
---
layout: blog-post
title:  "$2"
date:   $timestamp
categories:: $1
---
EOF

rm -rf "$HOME/Sites/geedbla/_$1/.gitkeep"
