#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# git-log.sh
#
# Pretty git log with signature highlighting (truecolor).
#
# Features:
#   - Graph view: --graph --decorate --all
#   - Signature display: --show-signature
#   - 24-bit ANSI coloring:
#       Good signatures → green (rgb 80,200,120)
#       BAD signatures  → red   (rgb 255,80,80)
#
# Requirements:
#   - git with SSH or GPG signing enabled
#   - terminal with truecolor support (COLORTERM=truecolor)
#   - pager that preserves ANSI (less -R recommended)
#
# Notes:
#   - Uses Perl for reliable regex coloring
#   - Works regardless of leading graph characters (|, *, etc.)
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  23-Mar-2026  1:19pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

# Colors (24-bit truecolor)
GOOD_COLOR=$'\x1b[38;2;80;200;120m'
BAD_COLOR=$'\x1b[38;2;255;80;80m'
RESET=$'\x1b[0m'

git log --decorate --graph --all --show-signature "$@" |
	perl -pe "
    s/(Good \"git\" signature.*)/${GOOD_COLOR}\$1${RESET}/;
    s/(BAD \"git\" signature.*)/${BAD_COLOR}\$1${RESET}/;
"
