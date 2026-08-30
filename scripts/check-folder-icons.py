#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  check-folder-icons.py
#
# verifies -- and optionally repairs -- the attributes macOS requires for a custom
# folder icon: the Icon\r file, its resource fork, and the Finder flags on both the
# folder and the icon file
#
#  Author   :  Gary Ash <gary.ash@icloud.com>
#  Created  :   1-Sep-2026  4:42pm
#  Modified :
#
#  Copyright © 2026 By Gary Ash All rights reserved.
# ****************************************************************************************
import argparse
import os
import re
import struct
import subprocess
import sys
from pathlib import Path

ICON_NAME = "Icon\r"
FINDER_INFO_SIZE = 32
HAS_CUSTOM_ICON = 0x0400
IS_INVISIBLE = 0x4000
ICNS_RESOURCE_ID = -16455

NON_HEX = re.compile(rb"[^0-9A-Fa-f]")


class ResourceForkError(Exception):
    pass


# ****************************************************************************************
# extended attribute plumbing
#
# /usr/bin/xattr is used rather than a binding to getxattr(2) because Python's os module
# exposes the extended attribute calls on Linux only
# ****************************************************************************************
def run_xattr(*arguments):
    result = subprocess.run(
        ["/usr/bin/xattr", *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.stdout if result.returncode == 0 else None


def read_finder_info(path):
    output = run_xattr("-px", "com.apple.FinderInfo", str(Path(path).resolve()))
    if output is None:
        return None

    hexadecimal = NON_HEX.sub(b"", output)
    if len(hexadecimal) < FINDER_INFO_SIZE * 2:
        return None
    return bytes.fromhex(hexadecimal[: FINDER_INFO_SIZE * 2].decode("ascii"))


# an all zero Finder info record is what the file system reports for a file that has
# none, so clearing the last flag removes the attribute rather than storing zeros
def write_finder_info(path, info):
    target = str(Path(path).resolve())

    if not info.strip(b"\0"):
        run_xattr("-d", "com.apple.FinderInfo", target)
        return True

    hexadecimal = " ".join(f"{byte:02X}" for byte in info)
    return run_xattr("-wx", "com.apple.FinderInfo", hexadecimal, target) is not None


def finder_flags(path):
    info = read_finder_info(path)
    if info is None:
        return 0
    return struct.unpack_from(">H", info, 8)[0]


def set_finder_flags(path, flags):
    info = read_finder_info(path)
    if info is None:
        info = b"\0" * FINDER_INFO_SIZE
    info = info[:8] + struct.pack(">H", flags & 0xFFFF) + info[10:]
    return write_finder_info(path, info)


# ****************************************************************************************
# resource fork reading
#
# a reader is a callable taking an offset and a length and returning that slice of the
# fork, or None if it falls outside it -- the file backed form keeps multi megabyte icon
# suites off the heap
# ****************************************************************************************
def string_reader(data):
    def read(offset, length):
        if offset < 0 or length < 0 or offset + length > len(data):
            return None
        return data[offset : offset + length]

    return read


def file_reader(handle):
    def read(offset, length):
        if offset < 0 or length < 0:
            return None
        try:
            handle.seek(offset)
        except OSError:
            return None
        buffer = handle.read(length)
        return buffer if len(buffer) == length else None

    return read


def open_resource_fork(path):
    fork = Path(str(Path(path).resolve()) + "/..namedfork/rsrc")

    try:
        size = fork.stat().st_size
    except OSError:
        size = 0

    if size:
        try:
            return file_reader(open(fork, "rb")), size
        except OSError:
            pass

    output = run_xattr("-px", "com.apple.ResourceFork", str(Path(path).resolve()))
    if output is None:
        return None, 0

    hexadecimal = NON_HEX.sub(b"", output)
    if not hexadecimal:
        return None, 0

    try:
        data = bytes.fromhex(hexadecimal.decode("ascii"))
    except ValueError:
        return None, 0
    return string_reader(data), len(data)


# resource fork layout: a 16 byte header, a data area of length prefixed resources and a
# resource map holding a type list, each entry of which points at a list of resource
# references -- see Inside Macintosh: More Macintosh Toolbox, "Resource Manager"
def parse_resource_map(reader, size):
    header = reader(0, 16)
    if not header:
        raise ResourceForkError("resource fork is too short to hold a header")

    data_offset, map_offset, data_length, map_length = struct.unpack(">4I", header)

    if map_length < 30 or map_offset + map_length > size:
        raise ResourceForkError("resource map lies outside the resource fork")
    if data_offset + data_length > size:
        raise ResourceForkError("resource data lies outside the resource fork")

    resource_map = reader(map_offset, map_length)
    if not resource_map:
        raise ResourceForkError("resource map cannot be read")

    type_list = struct.unpack_from(">H", resource_map, 24)[0]
    if type_list + 2 > map_length:
        raise ResourceForkError("resource type list lies outside the resource map")

    type_count = struct.unpack_from(">H", resource_map, type_list)[0] + 1
    types = {}

    for type_index in range(type_count):
        entry = type_list + 2 + type_index * 8
        if entry + 8 > map_length:
            raise ResourceForkError("resource type list is truncated")

        name, reference_count, reference_list = struct.unpack_from(
            ">4sHH", resource_map, entry
        )

        for reference_index in range(reference_count + 1):
            reference = type_list + reference_list + reference_index * 12
            if reference + 12 > map_length:
                raise ResourceForkError("resource reference list is truncated")

            identifier, _name_offset, packed = struct.unpack_from(
                ">hHI", resource_map, reference
            )
            types.setdefault(name, []).append(
                {
                    "id": identifier,
                    "offset": data_offset + (packed & 0x00FFFFFF),
                }
            )

    return {"data_offset": data_offset, "types": types}


# returns a complaint about the icns payload, or None when it looks like a real icon
def icns_problem(reader, reference):
    prefix = reader(reference["offset"], 4)
    if not prefix:
        return "the icns resource cannot be read"

    length = struct.unpack(">I", prefix)[0]
    if length < 8:
        return "the icns resource is empty"

    head = reader(reference["offset"] + 4, 8)
    if not head:
        return "the icns resource cannot be read"
    if head[:4] != b"icns":
        return "the icns resource does not begin with an icns signature"

    declared = struct.unpack(">I", head[4:8])[0]
    if declared != length:
        return f"the icns image claims {declared} bytes but the resource holds {length}"

    return None


# ****************************************************************************************
# checking
# ****************************************************************************************
def issue(code, level, fixable, path, message):
    return {
        "code": code,
        "level": level,
        "fixable": fixable,
        "path": path,
        "message": message,
        "repaired": None,
    }


def check_icon_resources(icon, issues):
    reader, size = open_resource_fork(icon)

    if reader is None:
        issues.append(
            issue(
                "icon-no-resource-fork",
                "error",
                False,
                icon,
                "the icon file has no resource fork, so it carries no icon at all",
            )
        )
        return

    try:
        resource_map = parse_resource_map(reader, size)
    except (ResourceForkError, struct.error) as error:
        reason = str(error) or "the resource fork could not be parsed"
        issues.append(issue("icon-bad-resource-fork", "error", False, icon, reason))
        return

    references = resource_map["types"].get(b"icns")
    if not references:
        issues.append(
            issue(
                "icon-no-icns-resource",
                "error",
                False,
                icon,
                "the resource fork holds no icns resource",
            )
        )
        return

    icon_resource = next(
        (item for item in references if item["id"] == ICNS_RESOURCE_ID), None
    )
    if icon_resource is None:
        identifiers = ", ".join(str(item["id"]) for item in references)
        issues.append(
            issue(
                "icon-wrong-icns-id",
                "error",
                False,
                icon,
                f"the icns resource must have id {ICNS_RESOURCE_ID}, "
                f"but the fork holds id {identifiers}",
            )
        )
        return

    problem = icns_problem(reader, icon_resource)
    if problem:
        issues.append(issue("icon-bad-icns-data", "error", False, icon, problem))


def check_folder(directory):
    issues = []
    icon = os.path.join(directory, ICON_NAME)
    flags = finder_flags(directory)

    if not os.path.islink(icon) and not os.path.exists(icon):
        if flags & HAS_CUSTOM_ICON:
            issues.append(
                issue(
                    "stray-custom-icon-flag",
                    "error",
                    True,
                    directory,
                    "the folder is marked as having a custom icon but contains no icon file",
                )
            )

        if os.path.isfile(os.path.join(directory, "Icon")):
            issues.append(
                issue(
                    "plain-icon-file",
                    "warning",
                    False,
                    directory,
                    "the folder holds a file named Icon with no trailing carriage return, "
                    "which the Finder ignores",
                )
            )

        return issues

    if os.path.islink(icon) or not os.path.isfile(icon):
        issues.append(
            issue(
                "icon-not-regular-file",
                "error",
                False,
                icon,
                "the icon file must be a regular file",
            )
        )
        return issues

    if not flags & HAS_CUSTOM_ICON:
        issues.append(
            issue(
                "missing-custom-icon-flag",
                "error",
                True,
                directory,
                "the folder holds an icon file but is not marked as having a custom icon",
            )
        )

    if not finder_flags(icon) & IS_INVISIBLE:
        issues.append(
            issue(
                "icon-not-invisible",
                "error",
                True,
                icon,
                "the icon file is not marked invisible, so it shows up in the Finder",
            )
        )

    mode = os.stat(icon).st_mode & 0o7777
    if (mode & 0o444) != 0o444:
        issues.append(
            issue(
                "icon-not-readable",
                "error",
                True,
                icon,
                f"the icon file is mode {mode:04o} and is not readable by everyone",
            )
        )

    data_fork = os.stat(icon).st_size
    if data_fork:
        issues.append(
            issue(
                "icon-data-fork-not-empty",
                "warning",
                False,
                icon,
                f"the icon file's data fork holds {data_fork} bytes; the Finder reads "
                "only the resource fork",
            )
        )

    check_icon_resources(icon, issues)
    return issues


def fix_issue(item):
    if not item["fixable"]:
        return False

    path = item["path"]
    code = item["code"]

    if code == "missing-custom-icon-flag":
        return set_finder_flags(path, finder_flags(path) | HAS_CUSTOM_ICON)
    if code == "stray-custom-icon-flag":
        return set_finder_flags(path, finder_flags(path) & ~HAS_CUSTOM_ICON)
    if code == "icon-not-invisible":
        return set_finder_flags(path, finder_flags(path) | IS_INVISIBLE)
    if code == "icon-not-readable":
        try:
            os.chmod(path, (os.stat(path).st_mode & 0o7777) | 0o444)
        except OSError:
            return False
        return True

    return False


def walk_folders(root, recursive):
    if not recursive:
        return [root]

    folders = []
    queue = [root]

    while queue:
        directory = queue.pop(0)
        folders.append(directory)

        try:
            entries = sorted(os.listdir(directory))
        except OSError:
            continue

        for entry in entries:
            path = os.path.join(directory, entry)
            if os.path.isdir(path) and not os.path.islink(path):
                queue.append(path)

    return folders


# ****************************************************************************************
# driver
# ****************************************************************************************
USAGE = r"""usage: check-folder-icons.py [-r] [-f] [-q] folder [folder ...]

Checks that each folder's custom icon is set up the way the Finder expects: an
invisible Icon\r file whose resource fork holds an icns resource with id -16455,
inside a folder whose Finder flags carry the custom icon bit.

  -r, --recursive  check every folder beneath the ones named
  -f, --fix        repair the problems that can be repaired
  -q, --quiet      report nothing; use the exit status
  -h, --help       show this message

Exit status is 0 when nothing is wrong, 1 when an unrepaired error remains and 2
when the command line is malformed.
"""


def usage(status):
    stream = sys.stderr if status else sys.stdout
    stream.write(USAGE)
    return status


def report(directory, issues):
    print(directory)

    for item in issues:
        note = ""

        if not item["fixable"]:
            note = " -- cannot be repaired automatically"
        elif item["repaired"]:
            note = " -- fixed"
        elif item["repaired"] is not None:
            note = " -- repair failed"

        print(f"  {item['level']:<7} {item['code']}: {item['message']}{note}")


def main(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-r", "--recursive", action="store_true")
    parser.add_argument("-f", "--fix", action="store_true")
    parser.add_argument("-q", "--quiet", action="store_true")
    parser.add_argument("-h", "--help", action="store_true")
    parser.add_argument("folders", nargs="*")

    try:
        option = parser.parse_args(argv)
    except SystemExit:
        return usage(2)

    if option.help:
        return usage(0)
    if not option.folders:
        return usage(2)

    checked = problems = repaired = unresolved = 0

    for root in option.folders:
        if not os.path.isdir(root):
            if not option.quiet:
                sys.stderr.write(f"check-folder-icons.py: {root} is not a folder\n")
            unresolved += 1
            continue

        for directory in walk_folders(root, option.recursive):
            checked += 1

            issues = check_folder(directory)
            if not issues:
                continue

            problems += len(issues)

            if option.fix:
                for item in issues:
                    item["repaired"] = bool(fix_issue(item))
                    repaired += item["repaired"]

            if not option.quiet:
                report(directory, issues)

            unresolved += sum(
                1
                for item in issues
                if item["level"] == "error" and not item["repaired"]
            )

    if not option.quiet:
        print(
            f"{checked} folder{'' if checked == 1 else 's'} checked, "
            f"{problems} problem{'' if problems == 1 else 's'} found, "
            f"{repaired} repaired"
        )

    return 1 if unresolved else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
