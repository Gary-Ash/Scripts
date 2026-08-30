#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  new-xcode-project.py
#
# This script will generate a clean new Xcode project based one of template projects
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
import shutil
import subprocess
import sys
import textwrap
import zipfile
from pathlib import Path

# ----------------------------------------------------------------------------------------
# constants
# ----------------------------------------------------------------------------------------
TEMPLATE_LOCATION = "/opt/geedbla/templates/Xcode/"

# ----------------------------------------------------------------------------------------
# regular expressions
# ----------------------------------------------------------------------------------------

# this will match copyright declarations an isolate the copyright holder into group 1
FIND_FILES_TO_PROCESS = re.compile(
    r"Copyright\s*(?:.*)\s*(?:\d{4}\s*-\s*\d{4}|\d{4}) By (.*) All rights reserved\."
)

# this matches the copyright declaration found in non Xcode project files
# group 1 contains the comment leader of the line containing the copyright
NON_PROJECT_FILE_COPYRIGHT = re.compile(
    r"(.*)Copyright\s*(?:.*)\s*(\d{4}\s*-\s*\d{4}|\d{4})\s*By\s*(.*) All rights reserved\."
)

# this matches the copyright declaration found in Xcode project files
PROJECT_FILE_COPYRIGHT = re.compile(
    r"(?:\\n)(.{0,3}\s*)Copyright\s*(?:.*)\s*(?:\d{4}\s*-\s*\d{4}|\d{4})"
    r"\s*By\s*CompanyName All rights reserved\."
)

ORGANIZATION_NAME = re.compile(r"ORGANIZATIONNAME\s*=\s*.*;")
DISPLAY_NAME = re.compile(r"INFOPLIST_KEY_CFBundleDisplayName\s*=\s*.*;")
GENERATE_INFOPLIST = re.compile(r"GENERATE_INFOPLIST_FILE = YES;")
BUNDLE_IDENTIFIER = re.compile(r"PRODUCT_BUNDLE_IDENTIFIER \s*=\s*.*;")
COMPANY_NAME_CREDIT = re.compile(r"By\s+CompanyName\s+All rights reserved\.")

PROJECT_CREATED = re.compile(r'Created  :[^"\\\n]*')
PROJECT_MODIFIED = re.compile(r'Modified :[^"\\\n]*')
SOURCE_CREATED = re.compile(r"Created  :[^\\\n]*")
SOURCE_MODIFIED = re.compile(r"Modified :[^\\\n]*")

VALID_PROJECT_NAME = re.compile(r"^[a-zA-Z][0-9a-zA-Z_-]+$")
VALID_BUNDLE_IDENTIFIER = re.compile(r"^(net|com|org)\.[a-z0-9]+$")

IGNORE_EXTENSIONS = {
    ".png",
    ".ttf",
    ".jpg",
    ".jpeg",
    ".bmp",
    ".psd",
    ".mov",
    ".mp3",
    ".ogg",
    ".mp4",
    ".caf",
    ".scpt",
    ".xcuserstate",
}

# ----------------------------------------------------------------------------------------
#  global variables
# ----------------------------------------------------------------------------------------
options = {
    "projectTemplate": None,
    "projectName": None,
    "projectLocation": None,
    "companyName": "Gary Ash",
    "bundleIdentifier": "",
    "setupGithub": True,
    "openXcode": True,
    "openSourceProject": True,
    "inFileLicense": False,
}

companies = []
templates = []
timestamp = ""
license_text = ""
copyright_notice = ""
set_file_date_format = ""


# ----------------------------------------------------------------------------------------
# utility subroutines
# ----------------------------------------------------------------------------------------


def unzip_files(zip_file, target_dir):
    if not Path(zip_file).is_file():
        die(f"Zip file '{zip_file}' does not exist")
    if not Path(target_dir).is_dir():
        die(f"Target directory '{target_dir}' does not exist")

    with zipfile.ZipFile(zip_file) as archive:
        members = archive.infolist()

        for member in members:
            if "__MACOSX/" in member.filename:
                continue

            output_path = Path(target_dir) / member.filename

            if member.is_dir():
                output_path.mkdir(exist_ok=True)
            else:
                output_path.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(member) as source, open(output_path, "wb") as target:
                    shutil.copyfileobj(source, target)

    return len(members)


# Text::Wrap measures tabs at eight columns and folds leading runs of spaces back into
# tabs on the way out, so both passes are reproduced here
def unexpand(line):
    line = line.expandtabs(8)
    body = line.lstrip(" ")
    indent = len(line) - len(body)
    return "\t" * (indent // 8) + " " * (indent % 8) + body


def wrap_text(text, width, prefix):
    columns = width - len(prefix)
    available = max(columns - 1 - len(prefix.expandtabs(8)), 1)

    lines = []
    for segment in text.split("\n"):
        if not segment.strip():
            lines.append(prefix)
            continue
        for line in textwrap.wrap(
            segment, width=available, break_long_words=True, break_on_hyphens=False
        ):
            lines.append(prefix + line)

    return "\n".join(unexpand(line) for line in lines)


def is_valid_organization(org):
    return org.lower() in [company.lower() for company in companies]


def should_ignore_file(filename):
    return Path(filename).suffix in IGNORE_EXTENSIONS


def die(message):
    sys.stderr.write(f"*** Error: {message}\n")
    sys.exit(1)


# ----------------------------------------------------------------------------------------
# startup subroutines
# ----------------------------------------------------------------------------------------


def search_path(name):
    directories = os.environ.get("PATH", "").split(":") + ["/Applications/"]

    for directory in directories:
        candidate = os.path.join(directory, name)
        if (os.path.isfile(candidate) and os.access(candidate, os.X_OK)) or (
            candidate.endswith(".app") and os.path.isdir(candidate)
        ):
            return candidate
    return None


def check_for_required_tools():
    if not Path(TEMPLATE_LOCATION).is_dir():
        die(f"No project templates found at {TEMPLATE_LOCATION}")

    root = TEMPLATE_LOCATION.rstrip("/")
    for parent, directories, _files in os.walk(root):
        for name in directories:
            if re.match(r"^[A-Za-z]", name) and parent.count("/") < 6:
                templates.append(name)

    if not search_path("Xcode.app") or not search_path("git") or not search_path("gh"):
        die("Missing dependency")


# ----------------------------------------------------------------------------------------
# parse the command line
# ----------------------------------------------------------------------------------------


def help_text():
    script_name = Path(sys.argv[0]).name

    sys.stderr.write(
        f"{script_name} <template name> <project name> <location of project> "
        "[company] [bundle ID]\n\n"
    )
    sys.stderr.write(
        "-cs,\t---closed        \tCreated a project with a closed source license\n"
    )
    sys.stderr.write("-lif,\t--inFileLicense \tAdd the source license to the files\n")
    sys.stderr.write("-ng,\t--no-github      \tDo Not create a GitHub repository\n")
    sys.stderr.write(
        "-nx,\t--no-xcode       \tDo Not start Xcode after the project is generated\n"
    )
    sys.exit(1)


def create_bundle_identifier():
    company = re.sub(r"[^A-Za-z0-9]", "", options["companyName"].lower())
    project = re.sub(r"[^A-Za-z0-9]", "", options["projectName"])
    options["bundleIdentifier"] = f"com.{company}.{project}"


def validate_bundle_identifier():
    if options["bundleIdentifier"] == "":
        create_bundle_identifier()
        return

    if not VALID_BUNDLE_IDENTIFIER.match(options["bundleIdentifier"]):
        sys.stderr.write(
            f"*** Error: Invalid bundle identifer - {options['bundleIdentifier']}\n"
        )
        help_text()


def parse_command_line(argv):
    names = [
        "projectTemplate",
        "projectName",
        "projectLocation",
        "companyName",
        "bundleIdentifier",
    ]
    name_index = 0

    if len(argv) < 3:
        sys.stderr.write("*** Error: Not enough information given.\n")
        help_text()

    for argument in argv:
        if argument.startswith("-"):
            # =============================================================================
            #  process a probable option switch
            # =============================================================================
            option = argument.lower()
            if option in ("--no-github", "-ng"):
                options["setupGithub"] = False
            elif option in ("--no-xcode", "-nx"):
                options["openXcode"] = False
            elif option in ("--closed", "-cs"):
                options["openSourceProject"] = False
            elif option in ("--infilelicense", "-lif"):
                options["inFileLicense"] = True
            else:
                sys.stderr.write(f"*** Error: Unknown option: {argument}\n")
                help_text()
        else:
            # =============================================================================
            #  process a name or location argument
            # =============================================================================
            if name_index >= len(names):
                sys.stderr.write(f"*** Error: Too many arguments -- {argument}\n")
                help_text()
            else:
                options[names[name_index]] = argument
                name_index += 1

    # =====================================================================================
    #  validate the chosen template exits
    # =====================================================================================
    if not Path(f"{TEMPLATE_LOCATION}/{options['projectTemplate']}").is_dir():
        die("invalid template name")

    for item in templates:
        if options["projectTemplate"].lower() == item.lower():
            options["projectTemplate"] = item
            break

    # =====================================================================================
    #  validate the project name
    # =====================================================================================
    project_name = options["projectName"]
    if len(project_name) < 3 or len(project_name) > 255:
        die("Bad project name")
    if project_name in (".", "..") or not VALID_PROJECT_NAME.match(project_name):
        die("Bad project name")

    # =====================================================================================
    #  validate the project location
    # =====================================================================================
    if options["projectLocation"] == ".":
        options["projectLocation"] = str(Path.cwd())
    else:
        options["projectLocation"] = str(Path(options["projectLocation"]).resolve())

    if not Path(options["projectLocation"]).is_dir():
        die("invalid project location")

    if Path(options["projectLocation"], project_name).is_dir():
        die("project or directory already exists")

    validate_bundle_identifier()


# ----------------------------------------------------------------------------------------
# project building subroutines
# ----------------------------------------------------------------------------------------


def prepare_template_variables():
    global timestamp, set_file_date_format, copyright_notice, license_text

    # =====================================================================================
    # get and format timestamp values
    # =====================================================================================
    now = datetime.datetime.now()
    set_file_date_format = now.strftime("%m/%d/%y %I:%M %p")

    hour = now.hour % 12 or 12
    meridiem = "am" if now.hour < 12 else "pm"
    timestamp = f"{now.day:2d}-{now.strftime('%b')}-{now.year}  {hour}:{now.minute:02d}{meridiem}"

    copyright_notice = (
        f"Copyright © {now.year} By {options['companyName']} All rights reserved."
    )

    try:
        with open(
            f"{TEMPLATE_LOCATION}/_Files/organizations.txt", encoding="utf-8"
        ) as handle:
            companies.extend(line.rstrip("\n") for line in handle)
    except OSError as error:
        die(f"Unable to open organizations file: {error}")

    companies.append("CompanyName")

    if options["inFileLicense"]:
        # =================================================================================
        # the user wants "in the source code license statement"
        # load the text of selected license (open or closed) to allow for faster processing
        # =================================================================================
        license_file = f"{TEMPLATE_LOCATION}/_Files/LICENSE-Open.md"
        if not options["openSourceProject"]:
            license_file = f"{TEMPLATE_LOCATION}/_Files/LICENSE-Closed.md"

        try:
            license_text = Path(license_file).read_text(encoding="utf-8")
        except OSError as error:
            die(f"Unable to read the license file: {error}")

        license_text = license_text[license_text.index("Copyright") :]
        license_text = FIND_FILES_TO_PROCESS.sub(
            lambda _: copyright_notice, license_text, count=1
        )
        license_text = license_text.strip()


def copy_or_die(source, destination):
    try:
        shutil.copy(source, destination)
    except OSError as error:
        die(f"disk error : {error}")


def tree_copy_or_die(source, destination):
    try:
        shutil.copytree(source, destination, symlinks=True, dirs_exist_ok=True)
    except OSError as error:
        die(f"disk error : {error}")


def create_project_file_structure():
    project_location = options["projectLocation"]
    project_name = options["projectName"]
    project_template = options["projectTemplate"]
    project_root = f"{project_location}/{project_name}"

    def rename(path):
        path = re.sub(TEMPLATE_LOCATION, lambda _: project_location, path)
        return re.sub(project_template, lambda _: project_name, path)

    skip = re.compile(r".*/\.DS_Store|.*/\.ProjectDescription").search

    # File::Find creates a directory only while walking its contents, so a template
    # directory holding nothing is never reproduced -- that is preserved here
    template_root = f"{TEMPLATE_LOCATION}/{project_template}"
    for parent, directories, files in os.walk(template_root):
        if skip(parent):
            directories[:] = []
            continue

        kept = [
            f"{parent}/{name}"
            for name in directories + files
            if not skip(f"{parent}/{name}")
        ]

        if parent == template_root or kept:
            os.makedirs(rename(parent), exist_ok=True)

        for entry in kept:
            if os.path.isfile(entry):
                copy_or_die(entry, rename(entry))

    resources_dir = None
    for parent, directories, _files in os.walk(project_root):
        for name in directories:
            if name == "Resources":
                resources_dir = f"{parent}/{name}"
    if resources_dir is None:
        # the original reaches this one through die rather than exit, so 255 it is
        sys.stderr.write("*** Error: Resources directory not found\n")
        sys.exit(255)

    unzip_files(f"{TEMPLATE_LOCATION}/_Files/Assets.xcassets.zip", resources_dir)

    tree_copy_or_die(f"{TEMPLATE_LOCATION}/_Files/BuildEnv", f"{project_root}/BuildEnv")

    if options["setupGithub"]:
        tree_copy_or_die(
            f"{TEMPLATE_LOCATION}/_Files/.github", f"{project_root}/.github"
        )

    copy_or_die(f"{TEMPLATE_LOCATION}/_Files/.swiftlint.yml", f"{project_root}/")
    copy_or_die(f"{TEMPLATE_LOCATION}/_Files/.gitignore", f"{project_root}/")

    license_file = f"{TEMPLATE_LOCATION}/_Files/LICENSE-Open.md"
    if not options["openSourceProject"]:
        license_file = f"{TEMPLATE_LOCATION}/_Files/LICENSE-Closed.md"
    copy_or_die(license_file, f"{project_root}/LICENSE.md")

    macros_file = f"{TEMPLATE_LOCATION}/_Files/IDETemplateMacros.plist"
    if options["inFileLicense"]:
        if options["openSourceProject"]:
            macros_file = f"{TEMPLATE_LOCATION}/_Files/IDETemplateMacros-Open.plist"
        else:
            macros_file = f"{TEMPLATE_LOCATION}/_Files/IDETemplateMacros-Closed.plist"

    xcuserdata = f"{project_root}/{project_name}.xcodeproj/xcuserdata"
    copy_or_die(macros_file, f"{xcuserdata}/IDETemplateMacros.plist")
    copy_or_die(f"{TEMPLATE_LOCATION}/_Files/.xcodesamplecode.plist", f"{xcuserdata}/")

    os.makedirs(f"{project_root}/Documentation", exist_ok=True)

    try:
        Path(f"{project_root}/README.md").write_text("\n", encoding="utf-8")
    except OSError as error:
        die(f"disk error: {error}")

    if (
        subprocess.run(
            ["git", "init", f"{project_root}/"], capture_output=True, check=False
        ).returncode
        != 0
    ):
        die("disk error")

    if (
        subprocess.run(
            ["git", "checkout", "-b", "develop"],
            cwd=project_root,
            capture_output=True,
            check=False,
        ).returncode
        != 0
    ):
        die("disk error")


def stamp_project_file(source):
    company_name = options["companyName"]
    project_name = options["projectName"]

    source = ORGANIZATION_NAME.sub(
        lambda _: f'ORGANIZATIONNAME = "{company_name}";', source, count=1
    )

    if DISPLAY_NAME.search(source):
        source = DISPLAY_NAME.sub(
            lambda _: f'INFOPLIST_KEY_CFBundleDisplayName = "{project_name}";', source
        )
    elif GENERATE_INFOPLIST.search(source):
        source = GENERATE_INFOPLIST.sub(
            lambda _: "GENERATE_INFOPLIST_FILE = YES;\n\t\t\t"
            f'INFOPLIST_KEY_CFBundleDisplayName = "{project_name}";',
            source,
        )

    source = BUNDLE_IDENTIFIER.sub(
        lambda _: f"PRODUCT_BUNDLE_IDENTIFIER  = {options['bundleIdentifier']};", source
    )
    source = PROJECT_CREATED.sub(lambda _: f"Created  :  {timestamp}", source)
    source = PROJECT_MODIFIED.sub(lambda _: "Modified :", source)

    count = 0
    while True:
        match = PROJECT_FILE_COPYRIGHT.search(source)
        if not match:
            break

        comment_leader = match.group(1)
        if options["inFileLicense"]:
            wrapped = wrap_text(license_text, 90, comment_leader)
            wrapped = wrapped.replace("\\", "\\\\")
            wrapped = wrapped.replace("'", "\\'")
            wrapped = wrapped.replace('"', '\\"')
            wrapped = wrapped.replace("\n", "\\n")
            wrapped = "\\n" + wrapped
            source = PROJECT_FILE_COPYRIGHT.sub(lambda _: wrapped, source, count=1)
        else:
            source = FIND_FILES_TO_PROCESS.sub(
                lambda _: copyright_notice, source, count=1
            )

        count += 1
        if count > 10:
            break

    return COMPANY_NAME_CREDIT.sub(
        lambda _: f"By {company_name} All rights reserved.", source
    )


def stamp_source_file(source):
    source = SOURCE_CREATED.sub(lambda _: f"Created  :  {timestamp}", source, count=1)
    source = SOURCE_MODIFIED.sub(lambda _: "Modified :", source, count=1)

    if options["inFileLicense"]:
        match = NON_PROJECT_FILE_COPYRIGHT.search(source)
        if match:
            wrapped = wrap_text(license_text, 90, match.group(1))
            source = NON_PROJECT_FILE_COPYRIGHT.sub(lambda _: wrapped, source, count=1)
    else:
        source = FIND_FILES_TO_PROCESS.sub(lambda _: copyright_notice, source, count=1)

    return source


def set_file_dates(path):
    subprocess.run(
        ["SetFile", "-d", set_file_date_format, "-m", set_file_date_format, str(path)],
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

    extension = Path(name).suffix

    if "\r" not in name and os.path.isfile(name) and not should_ignore_file(name):
        try:
            source = Path(name).read_text(encoding="utf-8", errors="surrogateescape")
        except OSError:
            set_file_dates(name)
            return

        match = FIND_FILES_TO_PROCESS.search(source)
        if match and is_valid_organization(match.group(1)):
            source = re.sub(
                options["projectTemplate"], lambda _: options["projectName"], source
            )
            source = source.replace("__PROJECT_NAME__", options["projectName"])

            if extension == ".pbxproj":
                source = stamp_project_file(source)
            else:
                source = stamp_source_file(source)

            try:
                Path(name).write_text(
                    source, encoding="utf-8", errors="surrogateescape"
                )
            except OSError:
                pass

    set_file_dates(name)


# ****************************************************************************************
# script main line
# ****************************************************************************************
def main(argv):
    check_for_required_tools()
    parse_command_line(argv)
    prepare_template_variables()
    create_project_file_structure()

    project_root = f"{options['projectLocation']}/{options['projectName']}"

    search_replace(project_root)
    for parent, directories, files in os.walk(project_root):
        for name in sorted(directories) + sorted(files):
            search_replace(f"{parent}/{name}")

    if options["openXcode"]:
        subprocess.Popen(
            [
                "open",
                "-a",
                "Xcode",
                f"{project_root}/{options['projectName']}.xcodeproj",
            ]
        )

    if options["setupGithub"]:
        subprocess.run(
            [
                "gh",
                "repo",
                "create",
                options["projectName"],
                "--private",
                "--source=.",
                "--remote=upstream",
            ],
            cwd=project_root,
            capture_output=True,
            check=False,
        )

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
