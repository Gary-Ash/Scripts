#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  reset-dates.py
#
# This script will allow me to reset the file creation and modification dates of files in
# a given directory tree. date information is also edited if my personal source file
# header comment block is detected
#
#  Author   :  Gary Ash <gary.ash@icloud.com>
#  Created  :   1-Sep-2026  4:42pm
#  Modified :
#
#  Copyright © 2026 By Gary Ash All rights reserved.
# ****************************************************************************************
import datetime
import os
import re
import subprocess
import sys
from pathlib import Path

# ----------------------------------------------------------------------------------------
# constants
# ----------------------------------------------------------------------------------------
TEMPLATE_LOCATION = Path("/opt/geedbla/templates/Xcode")

# ----------------------------------------------------------------------------------------
# regular expressions
# ----------------------------------------------------------------------------------------

# this will match copyright declarations an isolate the copyright holder into group 1
FIND_FILES_TO_PROCESS = re.compile(
    r"Copyright\s*(?:.*)\s*(?:\d{4}\s*-\s*\d{4}|\d{4}) By (.*) All rights reserved\."
)

CREATED_LINE = re.compile(
    r"Created  :[\/\t 0-9A-Za-z\-:]*[^\n|\\n]|Created  :*[^\n|\\n]"
)
MODIFIED_LINE = re.compile(
    r"Modified :[\/\t 0-9A-Za-z\-:]*[^\n|\\n]|Modified :*[^\n|\\n]"
)
ORGANIZATION_NAME = re.compile(r"ORGANIZATIONNAME\s*=\s*.*;")

IGNORE_EXTENSIONS = (
    ".png",
    ".ttf",
    "jpg",
    ".jpeg",
    ".bmp",
    ".psd",
    ".mov",
    ".mp3",
    ".ogg",
    ".mp4",
    ".caf",
    ".xcuserstate",
)

# ----------------------------------------------------------------------------------------
#  global variables
# ----------------------------------------------------------------------------------------
companies = []
company_name = "Gary Ash"
timestamp = ""
set_file_date_format = ""
copyright_notice = ""


# =========================================================================================


def is_valid_organization(org):
    return org.lower() in [company.lower() for company in companies]


def should_ignore_file(filename):
    return Path(filename).suffix in IGNORE_EXTENSIONS


def stamp_header(source, count=0):
    source = CREATED_LINE.sub(f"Created  :  {timestamp}", source, count=count)
    source = MODIFIED_LINE.sub("Modified :", source, count=count)
    return source


def process_scpt_file(filename):
    language = "AppleScript"
    decompiled = subprocess.run(
        ["osadecompile", str(filename)], capture_output=True, text=True, check=False
    )
    source = decompiled.stdout

    if decompiled.returncode != 0 or not source:
        language = "JavaScript"
        decompiled = subprocess.run(
            ["osadecompile", "-l", "JavaScript", str(filename)],
            capture_output=True,
            text=True,
            check=False,
        )
        source = decompiled.stdout
        if decompiled.returncode != 0 or not source:
            return

    match = FIND_FILES_TO_PROCESS.search(source)
    if match and is_valid_organization(match.group(1)):
        source = stamp_header(source, count=1)
        source = FIND_FILES_TO_PROCESS.sub(lambda _: copyright_notice, source, count=1)

        subprocess.run(
            ["osacompile", "-l", language, "-o", str(filename)],
            input=source,
            text=True,
            stderr=subprocess.DEVNULL,
            check=False,
        )


def parse_command_line(argv):
    global company_name

    if len(argv) < 1:
        sys.stderr.write(
            'Usage: reset-dates.py "company name" [file|directory ...]\n\n'
        )
        sys.stderr.write("Examples:\n")
        sys.stderr.write(
            '  reset-dates.py "Gary Ash"                              # Process current directory\n'
        )
        sys.stderr.write(
            '  reset-dates.py "Gary Ash" ./src ./lib ./tests          # Process multiple directories\n'
        )
        sys.stderr.write(
            '  reset-dates.py "Gary Ash" main.swift AppDelegate.swift # Process specific files\n'
        )
        sys.stderr.write(
            '  reset-dates.py "Gary Ash" ./src config.swift           # Mix of files and directories\n'
        )
        sys.exit(1)

    company_name = argv[0]
    paths = argv[1:]

    if not paths:
        return [Path.cwd()]
    return [Path(path).resolve() for path in paths]


def prepare():
    global timestamp, set_file_date_format, copyright_notice

    # =====================================================================================
    # get and format timestamp values
    # =====================================================================================
    now = datetime.datetime.now()
    set_file_date_format = now.strftime("%m/%d/%y %I:%M %p")

    hour = now.hour % 12 or 12
    meridiem = "am" if now.hour < 12 else "pm"
    timestamp = f"{now.day:2d}-{now.strftime('%b')}-{now.year}  {hour}:{now.minute:02d}{meridiem}"

    copyright_notice = f"Copyright © {now.year} By {company_name} All rights reserved."

    try:
        with open(
            TEMPLATE_LOCATION / "_Files/organizations.txt", encoding="utf-8"
        ) as handle:
            companies.extend(line.rstrip("\n") for line in handle)
    except OSError as error:
        sys.stderr.write(f"*** Error: Unable to open orginations file : {error}\n")
        sys.exit(1)

    companies.append("CompanyName")


def set_file_dates(path):
    subprocess.run(
        ["SetFile", "-d", set_file_date_format, "-m", set_file_date_format, str(path)],
        capture_output=True,
        check=False,
    )


def search_replace(path):
    name = str(path)

    if name.endswith("/.DS_Store"):
        try:
            os.unlink(name)
        except OSError:
            pass
        return

    extension = path.suffix

    # handle compiled AppleScript files specially
    if extension == ".scpt" and path.is_file():
        process_scpt_file(path)
        set_file_dates(path)
        return

    if "\r" not in name and path.is_file() and not should_ignore_file(name):
        try:
            source = path.read_text(encoding="utf-8", errors="surrogateescape")
        except OSError:
            set_file_dates(path)
            return

        match = FIND_FILES_TO_PROCESS.search(source)
        if match and is_valid_organization(match.group(1)):
            if extension == ".pbxproj":
                source = ORGANIZATION_NAME.sub(
                    f'ORGANIZATIONNAME = "{company_name}";', source, count=1
                )
                source = stamp_header(source)

                count = 0
                while True:
                    match = FIND_FILES_TO_PROCESS.search(source)
                    if not match or not is_valid_organization(match.group(1)):
                        break
                    source = FIND_FILES_TO_PROCESS.sub(
                        lambda _: copyright_notice, source, count=1
                    )
                    count += 1
                    if count > 10:
                        break
            else:
                source = stamp_header(source, count=1)
                source = FIND_FILES_TO_PROCESS.sub(
                    lambda _: copyright_notice, source, count=1
                )

            try:
                path.write_text(source, encoding="utf-8", errors="surrogateescape")
            except OSError:
                pass

    set_file_dates(path)


# ****************************************************************************************
# script main line
# ****************************************************************************************
def main(argv):
    work_paths = parse_command_line(argv)
    prepare()

    for path in work_paths:
        if path.is_dir():
            search_replace(path)
            for root, dirs, files in os.walk(path):
                for name in sorted(dirs) + sorted(files):
                    search_replace(Path(root) / name)
        elif path.is_file():
            search_replace(path)
        else:
            sys.stderr.write(
                f"*** Warning: '{path}' is not a valid file or directory\n"
            )

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
