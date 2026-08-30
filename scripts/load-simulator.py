#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  load-simulator.py
#
# This script will restore the state of the iOS simulator
#
#  Author   :  Gary Ash <gary.ash@icloud.com>
#  Created  :   1-Sep-2026  4:42pm
#  Modified :
#
#  Copyright © 2026 By Gary Ash All rights reserved.
# ****************************************************************************************
import os
import plistlib
import subprocess
import sys
from pathlib import Path

SIMCTL = "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl"
ICON_NAME = "Icon\r"


# ****************************************************************************************
# this routine will build a dictionary of names and UUIDs of the currently defined
# simulators
# ****************************************************************************************
def get_simulators(simulators_location):
    simulators = {}

    for root, _dirs, files in os.walk(simulators_location):
        if "device.plist" not in files:
            continue

        try:
            with open(Path(root) / "device.plist", "rb") as plist_file:
                plist = plistlib.load(plist_file)
        except (OSError, plistlib.InvalidFileException):
            continue

        platform = plist.get("runtime", "")
        if "iOS" in platform:
            simulators[plist["name"]] = plist["UDID"]

    return simulators


# ****************************************************************************************
# this routine will build a list of all the media in the SimulatorBackup folder
# ****************************************************************************************
def collect_media(media_location):
    media = []

    for root, _dirs, files in os.walk(media_location):
        for name in files:
            if name.startswith(".") or name == ICON_NAME:
                continue
            path = Path(root) / name
            if path.is_file():
                media.append(str(path))

    return media


# ****************************************************************************************
# main line
# ****************************************************************************************
def main():
    home = Path(os.environ["HOME"])
    simulators_location = home / "Library/Developer/CoreSimulator/Devices"
    media_location = (
        home / "Documents/GeeDblA/Resources/Development/Apple/SimulatorBackup"
    )

    simulators = get_simulators(simulators_location)
    media = collect_media(media_location)

    for arguments in (["shutdown", "all"], ["delete", "unavailable"], ["erase", "all"]):
        subprocess.run([SIMCTL] + arguments, capture_output=True, check=False)

    for name in simulators:
        booted = subprocess.run(
            [SIMCTL, "boot", name], capture_output=True, check=False
        )
        if booted.returncode != 0:
            continue

        if (
            subprocess.run(
                [SIMCTL, "addmedia", "booted"] + media, check=False
            ).returncode
            != 0
        ):
            return 1

        if subprocess.run([SIMCTL, "shutdown", "booted"], check=False).returncode != 0:
            return 1

    subprocess.run([SIMCTL, "shutdown", "all"], capture_output=True, check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
