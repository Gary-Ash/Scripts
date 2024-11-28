#!/usr/bin/env python3
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
