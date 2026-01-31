#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
# meeting-direct-link.py
#
# This script will convert Microsoft Teams and Zoom web links into direct into the app
# versions of those links
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Feb-2026  2:48pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
# ****************************************************************************************
import re
import sys


def is_convertible_zoom_url(url):
    matches = re.search(r"https://([\w\-]+\.)?(zoom.us)/j/", url)
    return bool(matches)


def is_convertible_msteams_url(url):
    matches = re.search(r"https://([\w\-]+\.)?(teams.microsoft.com)/l/", url)
    return bool(matches)


def convert_zoom_url_to_direct(zoom_url):
    zoom_url = re.sub(r"https://", "zoommtg://", zoom_url)
    zoom_url = re.sub(r"/j/", "/join?action=join&confno=", zoom_url)
    zoom_url = re.sub(r"\?pwd=", "&pwd=", zoom_url)
    return zoom_url


def convert_msteams_url_to_direct(msteams_url):
    return msteams_url.replace("https://", "msteams://")


# ****************************************************************************************
# script main line
# ****************************************************************************************
if len(sys.argv) != 2:
    print(len(sys.argv))
    print("Command syntax error:\n\tmeeting-direct-link <url>")
    exit(-1)

if is_convertible_msteams_url(sys.argv[1]):
    ret = convert_msteams_url_to_direct(sys.argv[1])
else:
    if is_convertible_zoom_url(sys.argv[1]):
        ret = convert_zoom_url_to_direct(sys.argv[1])
    else:
        print("The given link isn't a convertible meeting link")
        exit(-2)

# "https://us02web.zoom.us/j/5967470315?pwd=eHZZL2hmVW1haUU5aTZTUUJobjFIdz09"
print("direct meeting url:", ret)
