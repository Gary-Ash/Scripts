#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  wtf-autolayout.py
#
# This script parses an autolayout warning and passes it on to the www.wtfautolayout.com
# website for further analysis and with any luck helpful advice to resolve the issue
# ****************************************************************************************

import sys
import urllib.parse
import subprocess


def string_escape(s, encoding="utf-8"):
    return s.encode("latin1").decode("unicode-escape").encode("latin1").decode(encoding)


input = ", ".join(sys.argv[1:])
input = string_escape(input)

stripped_input = input.rstrip('"').lstrip('@"')
quoted_log = urllib.parse.quote(stripped_input)
url = "https://www.wtfautolayout.com/?constraintlog=%s" % quoted_log

subprocess.call(["open", url])
