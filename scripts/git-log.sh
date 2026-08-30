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
#   - Uses Python for reliable regex coloring
#   - Works regardless of leading graph characters (|, *, etc.)
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Sep-2026  4:42pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

# Colors (24-bit truecolor)
GOOD_COLOR=$'\x1b[38;2;80;200;120m'
BAD_COLOR=$'\x1b[38;2;255;80;80m'
RESET=$'\x1b[0m'

# The stream is coloured as bytes so a commit message that is not valid UTF-8 passes
# through untouched rather than stopping the log.
git log --decorate --graph --all --show-signature "$@" |
	python3 -c '
import re
import sys

good, bad, reset = (argument.encode() for argument in sys.argv[1:4])
rules = (
    (re.compile(rb"(Good \"git\" signature.*)"), good),
    (re.compile(rb"(BAD \"git\" signature.*)"), bad),
)

for line in sys.stdin.buffer:
    for pattern, colour in rules:
        line = pattern.sub(lambda match: colour + match.group(1) + reset,
                            line, count=1)
    sys.stdout.buffer.write(line)
' "${GOOD_COLOR}" "${BAD_COLOR}" "${RESET}"
