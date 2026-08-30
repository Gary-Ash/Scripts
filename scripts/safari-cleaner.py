#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  safari-cleaner.py
#
# Delete Safari website data that does not match a bookmarked website domain
#
#  Author   :  Gary Ash <gary.ash@icloud.com>
#  Created  :   1-Sep-2026  4:42pm
#  Modified :
#
#  Copyright © 2026 By Gary Ash All rights reserved.
# ****************************************************************************************
import argparse
import glob
import os
import plistlib
import re
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOME = os.environ["HOME"]
SAFARI_DATA = f"{HOME}/Library/Containers/com.apple.Safari/Data/Library"
COOKIE_FILE = f"{SAFARI_DATA}/Cookies/Cookies.binarycookies"
BOOKMARK_FILE = f"{HOME}/Library/Safari/Bookmarks.plist"
OBSERVATIONS = (
    f"{SAFARI_DATA}/WebKit/WebsiteData/ResourceLoadStatistics/observations.db"
)
WEBSITE_DATA = f"{SAFARI_DATA}/WebKit/WebsiteData/Default"
WEBKIT_CACHE = f"{SAFARI_DATA}/Caches/com.apple.Safari/WebKitCache"
ALT_SERVICES = (
    f"{SAFARI_DATA}/Caches/WebKit/AlternativeServices/AlternativeService.sqlite"
)
URL_CACHE_DIR = f"{SAFARI_DATA}/Caches/com.apple.Safari/fsCachedData"
URL_CACHE_DB = f"{SAFARI_DATA}/Caches/com.apple.Safari/Cache.db"
HISTORY_DB = f"{HOME}/Library/Safari/History.db"
CLOSED_TABS = f"{HOME}/Library/Safari/RecentlyClosedTabs.plist"
CB_STATS_DB = f"{HOME}/Library/Safari/ContentBlockerStatistics.db"
HSTS_PLIST = f"{SAFARI_DATA}/Caches/WebKit/HSTS/HSTS.plist"
FAVICONS_DB = f"{HOME}/Library/Safari/Favicon Cache/favicons.db"
KNOWLEDGE_DB = f"{HOME}/Library/Application Support/Knowledge/knowledgeC.db"
SAFARI_TMP = f"{HOME}/Library/Containers/com.apple.Safari/Data/tmp"
COOKIE_MAGIC = b"cook"
PAGE_HEADER = 0x00000100
FILE_TAG = bytes.fromhex("071720050000004b")

BLACKLIST_DOMAINS = """
    advancedswift.com barebones.com batman-news.com gamedev.city
    matteomanferdini.com donnywals.com avanderlee.com jessesquires.com t.co
    devhints.io iosref.com costco.com ios-factor.com iosfeeds.com
    qualitycoding.org 2dgameartguru.com 9to5mac.com macpaw.com angel.co
    blendswap.com codeandweb.com comicscontinuum.com emailtemp.org redd.it
    agner.org swiftpm.co swiftpm.com swiftbysundell.com swiftjectivec.com
    mapeditor.org udemy.com fandom.com wtfautolayout.com 71squared.com
    beautifyconverter.com freeformatter.com sanctum.geek.nz graphicriver.net
    stclairsoft.com jscreenfix.com johncodeos.com opengameart.org
    sqlitebrowser.org pfiddlesoft.com geedbla.com gitignore.io
    packagecontrol.io probot.github.io jamendo.com tutsplus.com itch.io
    nshipster.com testableapple.com iterm2.com shields.io codewars.com
    upwork.com escapistmagazine.com
""".split()

BLACKLIST = set(BLACKLIST_DOMAINS)

WHITELIST_DOMAINS = """
    geedbla.com upwork.com costco.com apple.com x.com gitlab.com
    atlassian.com atlassian.net bing.com live.com duckduckgo.com discord.com
    discordapp.com stackexchange.com sublimehq.com zenhub.com app.zenhub.com
    wikimedia.org wikipedia.org stackoverflow.com apple.stackexchange.com
    twitch.tv twitter.com superuser.com
    fuckingapproachableswiftconcurrency.com
""".split()

MULTIPART_SUFFIX = re.compile(r"^(co|com|org|net|gov|edu|ac)$")
ORIGIN_DOMAIN = re.compile(
    r"\b([a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+)\b",
    re.IGNORECASE,
)
URL_HOST = re.compile(r"^https?://([^/]+)", re.IGNORECASE)

APPLESCRIPT = r"""tell application "Safari" to quit
delay 0.3

tell application "Safari" to activate
delay 0.2

tell application "System Events"
	tell process "Safari"
		set frontmost to true

		keystroke "l" using command down
		delay 0.2

		key code 125 -- down arrow
		delay 0.2

		repeat 50 times
			key code 125
			delay 0.05
		end repeat

		key code 36 -- Return
	end tell


	tell application "System Events"
		tell process "Safari"
			-- Open Safari Settings
			keystroke "," using command down
			delay 1

			-- Click the Search tab
			try
				click button "Search" of toolbar 1 of window 1
			on error
				try
					click radio button "Search" of tab group 1 of window 1
				end try
			end try

			delay 0.5

			-- Target the main Search engine popup
			set mainPopup to pop up button "Search engine:" of group 1 of group 1 of window "Search"
			tell mainPopup
				click
				delay 0.2
				click menu item "DuckDuckGo" of menu 1
			end tell

			-- Optional: also set Private Browsing search engine
			try
				set privatePopup to pop up button "Search engine:" of group 1 of group 1 of window "Search"
				tell privatePopup
					click
					delay 0.2
					click menu item "DuckDuckGo" of menu 1
				end tell
			end try

			delay 0.3

			click button "General" of toolbar 1 of window 1

			-- Close the Preferences window
			click button 1 of window "General" -- button 1 is the red close button
		end tell
	end tell
end tell

tell application "System Events" to tell process "Safari"

	click menu item "Show All History" of menu 1 of menu bar item "History" of menu bar 1
	delay 0.2
	tell application "Safari" to activate
	try
		keystroke "a" using command down
		keystroke (ASCII character 127)
		delay 1
	end try

	tell application "Safari" to activate
	click menu item "Hide History" of menu 1 of menu bar item "History" of menu bar 1

	tell application "Safari" to quit
	delay 0.2
end tell
"""

options = argparse.Namespace(dry_run=False, verbose=False)


# ----- subroutines -----------------------------------------------------------------------


def die(message):
    sys.stderr.write(message + "\n")
    sys.exit(255)


def count_of(text):
    text = text.strip()
    return int(text) if text.lstrip("-").isdigit() else 0


def shell(command):
    return subprocess.run(
        command, shell=True, capture_output=True, text=True, check=False
    ).stdout


def check_safari_not_running():
    # Safari itself must be quit by the user — we refuse to kill the UI app.
    safari_pid = shell("pgrep -x Safari 2>/dev/null").strip()
    if re.search(r"\d", safari_pid):
        die(f"Safari is running (pid {safari_pid}). Please quit Safari first.")

    # WebKit XPC helpers linger after Safari quits and rewrite cache/alt_services
    # on their own schedule. Kill them so our edits stick.
    helpers = (
        "com.apple.WebKit.Networking",
        "com.apple.WebKit.WebContent",
        "com.apple.WebKit.GPU",
        "SafariBookmarksSyncAgent",
        "com.apple.Safari.History",
        "SafariPlatformSupport.Helper",
        "SafariNotificationAgent",
        "SafariLaunchAgent",
    )

    def helper_pids(helper):
        found = shell(f"pgrep -f '{helper}' 2>/dev/null").strip()
        if not re.search(r"\d", found):
            return []
        return re.split(r"\s+", found)

    for helper in helpers:
        pids = helper_pids(helper)
        if not pids:
            continue
        if options.verbose:
            print(f"Killing {helper} ({','.join(pids)})")
        send_signal(pids, signal.SIGTERM)

    # Give them a moment to exit, then SIGKILL stragglers.
    time.sleep(1)
    for helper in helpers:
        send_signal(helper_pids(helper), signal.SIGKILL)


def send_signal(pids, number):
    for pid in pids:
        try:
            os.kill(int(pid), number)
        except (OSError, ValueError):
            pass


def stop_knowledge_daemons():
    # knowledgeC.db is held open by knowledge-agent and ContextStoreAgent.
    # Kicking them releases the WAL so our writes can land. launchd will
    # relaunch them automatically.
    uid = os.getuid()
    for service in (
        "com.apple.knowledge-agent",
        "com.apple.CoreDuet.knowledgeC.syncService",
        "com.apple.contextstoreagent",
    ):
        subprocess.run(
            ["launchctl", "kickstart", "-k", f"gui/{uid}/{service}"], check=False
        )
    time.sleep(1)


def run_sqlite(database, sql):
    result = subprocess.run(["sqlite3", database, sql], check=False)
    if result.returncode != 0:
        sys.stderr.write(
            f"sqlite3 failed on {database} (rc={result.returncode}): {sql}\n"
        )
        return False
    return True


def query_sqlite(database, sql):
    return shell(f'sqlite3 "{database}" "{sql}" 2>/dev/null')


def sqlite_lines(rows):
    # the trailing newline must not count as a row
    lines = rows.split("\n")
    while lines and lines[-1] == "":
        lines.pop()
    return lines


def registrable_domain(host):
    labels = host.split(".")
    if len(labels) < 2:
        return None
    if len(labels) >= 3 and MULTIPART_SUFFIX.match(labels[-2]) and len(labels[-1]) == 2:
        return ".".join(labels[-3:])
    return ".".join(labels[-2:])


def extract_bookmark_domains():
    # Walk the Bookmarks.plist and collect only WebBookmarkTypeLeaf URLs that live
    # outside the com.apple.ReadingList subtree. The old regex-over-XML approach
    # grabbed every URL in the file — including reading-list items and embedded CDN
    # references — which made the keep-list so broad that nothing ever got deleted.
    try:
        with open(BOOKMARK_FILE, "rb") as handle:
            root = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException):
        die("Cannot read bookmarks plist")

    domains = {}
    walk_bookmark_dict(root, domains)
    return domains


def walk_bookmark_dict(node, domains):
    if not isinstance(node, dict):
        return

    # Skip the entire Reading List subtree.
    if node.get("Title", "") == "com.apple.ReadingList":
        return

    if node.get("WebBookmarkType", "") == "WebBookmarkTypeLeaf" and "URLString" in node:
        host = url_host(node["URLString"])
        if host is not None:
            domain = registrable_domain(host)
            if domain is not None:
                domains[domain] = 1

    children = node.get("Children")
    if isinstance(children, list):
        for child in children:
            walk_bookmark_dict(child, domains)


def domain_matches_bookmarks(cookie_domain, bookmark_domains):
    host = re.sub(r"^\.", "", cookie_domain.lower())

    # blacklist overrides everything
    if host in BLACKLIST:
        return False

    # suffix match: extract registrable domain from cookie domain
    registrable = registrable_domain(host)
    if registrable is not None and registrable in BLACKLIST:
        return False

    # direct match
    if host in bookmark_domains:
        return True
    if registrable is not None and registrable in bookmark_domains:
        return True

    return False


def read_cstring(data, offset):
    end = data.find(b"\0", offset)
    if end < 0:
        end = len(data)
    return data[offset:end].decode("utf-8", "surrogateescape")


def parse_cookie(page_data, offset):
    size, flags, unknown1, unknown2, url_off, name_off, path_off, value_off = (
        struct.unpack_from("<8I", page_data, offset)
    )

    return {
        "raw_data": page_data[offset : offset + size],
        "size": size,
        "flags": flags,
        "unknown1": unknown1,
        "unknown2": unknown2,
        "domain": read_cstring(page_data, offset + url_off),
        "name": read_cstring(page_data, offset + name_off),
        "path": read_cstring(page_data, offset + path_off),
        "value": read_cstring(page_data, offset + value_off),
        "comment": page_data[offset + 32 : offset + 40],
        "expiry": struct.unpack_from("<d", page_data, offset + 40)[0],
        "creation": struct.unpack_from("<d", page_data, offset + 48)[0],
    }


def parse_binary_cookies(path):
    data = Path(path).read_bytes()
    position = 0

    # header
    magic, num_pages = struct.unpack_from(">4sI", data, position)
    if magic != COOKIE_MAGIC:
        die("Not a binary cookies file (bad magic)")
    position += 8

    # page sizes
    page_sizes = struct.unpack_from(f">{num_pages}I", data, position)
    position += num_pages * 4

    # parse each page
    all_pages = []
    for page_size in page_sizes:
        page_data = data[position : position + page_size]
        position += page_size

        num_cookies = struct.unpack_from("<I", page_data, 4)[0]
        offsets = struct.unpack_from(f"<{num_cookies}I", page_data, 8)

        all_pages.append([parse_cookie(page_data, offset) for offset in offsets])

    # everything after pages is: 4-byte checksum + 8-byte tag + policy plist
    policy_plist = b""
    if position + 12 <= len(data):
        policy_plist = data[position + 12 :]  # skip checksum + tag

    return all_pages, policy_plist


def build_page(cookies):
    count = len(cookies)

    # header area size: 4 (page header) + 4 (count) + count*4 (offsets) + 4 (end marker)
    header_size = 12 + count * 4

    # compute cookie offsets and collect raw data
    offsets = []
    cookie_data = b""
    for cookie in cookies:
        offsets.append(header_size + len(cookie_data))
        cookie_data += cookie["raw_data"]

    page = struct.pack(">I", PAGE_HEADER)
    page += struct.pack("<I", count)
    page += struct.pack(f"<{count}I", *offsets)
    page += struct.pack("<I", 0)  # end marker
    page += cookie_data

    return page


def compute_checksum(page_blobs):
    checksum = 0
    for page in page_blobs:
        for index in range(0, len(page), 4):
            checksum += page[index]
    return checksum


def write_binary_cookies(path, pages, policy_plist):
    page_blobs = [build_page(page) for page in pages if page]

    if not page_blobs:
        die("No pages to write")

    out = COOKIE_MAGIC
    out += struct.pack(">I", len(page_blobs))
    out += struct.pack(f">{len(page_blobs)}I", *(len(blob) for blob in page_blobs))
    out += b"".join(page_blobs)

    out += struct.pack(">I", compute_checksum(page_blobs) & 0xFFFFFFFF)
    out += FILE_TAG
    if policy_plist:
        out += policy_plist

    handle, temp_path = tempfile.mkstemp(dir=f"{SAFARI_DATA}/Cookies")
    with os.fdopen(handle, "wb") as temp_file:
        temp_file.write(out)

    try:
        os.replace(temp_path, path)
    except OSError as error:
        die(f"Failed to replace cookie file: {error}")
    os.chmod(path, 0o644)


def clean_cookies(bookmark_domains):
    if not Path(COOKIE_FILE).is_file():
        print("No cookies file found, skipping")
        return

    pages, policy_plist = parse_binary_cookies(COOKIE_FILE)

    total_before = 0
    total_after = 0
    filtered_pages = []

    for page in pages:
        kept = []
        for cookie in page:
            total_before += 1
            if domain_matches_bookmarks(cookie["domain"], bookmark_domains):
                kept.append(cookie)
                total_after += 1
            elif options.verbose:
                print(
                    f"  DELETE: {cookie['domain']:<40}  "
                    f"{cookie['name']}={cookie['value'][:30]}"
                )
        if kept:
            filtered_pages.append(kept)

    removed = total_before - total_after
    action = "Would remove" if options.dry_run else "Removing"
    print(f"{action} {removed} of {total_before} cookies ({total_after} kept)")

    if not options.dry_run and removed > 0:
        backup = f"{COOKIE_FILE}.bak"
        try:
            shutil.copy(COOKIE_FILE, backup)
        except OSError as error:
            die(f"Backup failed: {error}")
        if options.verbose:
            print(f"Backup saved to {backup}")
        write_binary_cookies(COOKIE_FILE, filtered_pages, policy_plist)
        print("Cookies file updated.")


def clean_observations_db(bookmark_domains):
    if not Path(OBSERVATIONS).is_file():
        return

    to_delete = []
    rows = query_sqlite(
        OBSERVATIONS, "SELECT domainID, registrableDomain FROM ObservedDomains;"
    )
    lines = sqlite_lines(rows)

    for line in lines:
        identifier, _, domain = line.partition("|")
        if not domain:
            continue
        if not domain_matches_bookmarks(domain, bookmark_domains):
            to_delete.append({"id": identifier, "domain": domain})

    if not to_delete:
        return

    action = "Would remove" if options.dry_run else "Removing"
    print(f"{action} {len(to_delete)} of {len(lines)} entries from observations.db")

    if options.verbose:
        for item in to_delete:
            print(f"  DELETE: {item['domain']}")

    if not options.dry_run:
        identifiers = ",".join(item["id"] for item in to_delete)
        run_sqlite(
            OBSERVATIONS,
            f"PRAGMA foreign_keys = ON; DELETE FROM ObservedDomains WHERE domainID IN ({identifiers});",
        )


def clean_website_data(bookmark_domains):
    if not Path(WEBSITE_DATA).is_dir():
        return

    to_delete = []
    try:
        entries = os.listdir(WEBSITE_DATA)
    except OSError:
        return

    for entry in entries:
        if entry.startswith("."):
            continue
        origin_file = f"{WEBSITE_DATA}/{entry}/{entry}/origin"
        if not Path(origin_file).is_file():
            continue

        try:
            content = Path(origin_file).read_text(
                encoding="utf-8", errors="surrogateescape"
            )
        except OSError:
            continue

        # origin file contains domain name(s) — extract the first recognizable one
        match = ORIGIN_DOMAIN.search(content)
        if not match:
            continue

        domain = match.group(1)
        if not domain_matches_bookmarks(domain, bookmark_domains):
            to_delete.append({"dir": f"{WEBSITE_DATA}/{entry}", "domain": domain})

    if not to_delete:
        return

    action = "Would remove" if options.dry_run else "Removing"
    print(f"{action} {len(to_delete)} LocalStorage directories")

    if options.verbose:
        for item in to_delete:
            print(f"  DELETE: {item['domain']}")

    if not options.dry_run:
        for item in to_delete:
            shutil.rmtree(item["dir"], ignore_errors=True)


def clean_alt_services(bookmark_domains):
    if not Path(ALT_SERVICES).is_file():
        return

    # Check if anything actually needs removal (for dry-run reporting).
    rows = query_sqlite(ALT_SERVICES, "SELECT host FROM alt_services;")
    total = 0
    would_keep = 0
    for host in sqlite_lines(rows):
        if not host:
            continue
        total += 1
        if domain_matches_bookmarks(host, bookmark_domains):
            would_keep += 1

    if not total:
        return
    if not total - would_keep:
        return

    # alt_services is a pure HTTP alt-svc cache. WebKit respawns its XPC
    # helper on demand and flushes in-memory state back to this file, so
    # selective DELETEs race. Nuking the file is reliable — Safari rebuilds
    # it as sites advertise alt-svc on next visit.
    action = "Would wipe" if options.dry_run else "Wiping"
    print(
        f"{action} HTTP Alternative Service cache ({total} entries, "
        f"{would_keep} would re-populate on use)"
    )

    if not options.dry_run:
        for path in (ALT_SERVICES, f"{ALT_SERVICES}-wal", f"{ALT_SERVICES}-shm"):
            if Path(path).is_file():
                os.unlink(path)


def clean_url_cache():
    if not Path(URL_CACHE_DIR).is_dir():
        return

    files = glob.glob(f"{URL_CACHE_DIR}/*")
    if not files:
        return

    if options.dry_run:
        print(f"Would clear {len(files)} URL cache files")
    else:
        for path in files:
            try:
                os.unlink(path)
            except OSError:
                pass
        # Also clear the Cache.db entries
        if Path(URL_CACHE_DB).is_file():
            run_sqlite(
                URL_CACHE_DB,
                "DELETE FROM cfurl_cache_response; DELETE FROM cfurl_cache_blob_data; "
                "DELETE FROM cfurl_cache_receiver_data;",
            )
        print(f"Cleared {len(files)} URL cache files")


def clean_history_db(bookmark_domains):
    if not Path(HISTORY_DB).is_file():
        return

    total = query_sqlite(HISTORY_DB, "SELECT COUNT(*) FROM history_items;").strip()
    if count_of(total) <= 0:
        return

    action = "Would remove" if options.dry_run else "Removing"
    print(f"{action} all {total} Safari history items")

    if options.dry_run:
        return

    run_sqlite(
        HISTORY_DB,
        "DELETE FROM history_visits; DELETE FROM history_items; "
        "DELETE FROM history_tombstones; VACUUM;",
    )

    remaining = shell(
        f'sqlite3 "{HISTORY_DB}" "SELECT COUNT(*) FROM history_items;"'
    ).strip()
    if count_of(remaining) > 0:
        sys.stderr.write(
            f"History.db still has {remaining} rows after DELETE — "
            "com.apple.Safari.History helper may have respawned.\n"
        )


def clean_recently_closed_tabs():
    if not Path(CLOSED_TABS).is_file():
        return

    if options.dry_run:
        print("Would remove RecentlyClosedTabs.plist")
    else:
        try:
            os.unlink(CLOSED_TABS)
        except OSError as error:
            sys.stderr.write(f"Failed to remove {CLOSED_TABS}: {error}\n")
        print("Cleared recently closed tabs")


def clean_content_blocker_stats(bookmark_domains):
    if not Path(CB_STATS_DB).is_file():
        return

    def collect(sql):
        found = {}
        total = 0
        for line in sqlite_lines(query_sqlite(CB_STATS_DB, sql)):
            identifier, _, domain = line.partition("|")
            if not domain:
                continue
            total += 1
            if not domain_matches_bookmarks(domain, bookmark_domains):
                found[identifier] = domain
        return found, total

    to_delete, total_1p = collect(
        "SELECT firstPartyDomainID, domain FROM FirstPartyDomains;"
    )
    to_delete_3p, total_3p = collect(
        "SELECT thirdPartyDomainID, domain FROM ThirdPartyDomains;"
    )

    if not to_delete and not to_delete_3p:
        return

    action = "Would remove" if options.dry_run else "Removing"
    print(
        f"{action} {len(to_delete)}/{total_1p} first-party + "
        f"{len(to_delete_3p)}/{total_3p} third-party ContentBlocker entries"
    )

    if options.verbose:
        for key in sorted(to_delete, key=lambda k: to_delete[k]):
            print(f"  DELETE 1P: {to_delete[key]}")
        for key in sorted(to_delete_3p, key=lambda k: to_delete_3p[k]):
            print(f"  DELETE 3P: {to_delete_3p[key]}")

    if options.dry_run:
        return

    statements = []
    if to_delete:
        identifiers = ",".join(to_delete)
        statements += [
            f"DELETE FROM BlockedResources WHERE firstPartyDomainID IN ({identifiers});",
            f"DELETE FROM FirstPartyDomains WHERE firstPartyDomainID IN ({identifiers});",
        ]
    if to_delete_3p:
        identifiers = ",".join(to_delete_3p)
        statements += [
            f"DELETE FROM BlockedResources WHERE thirdPartyDomainID IN ({identifiers});",
            f"DELETE FROM ThirdPartyDomains WHERE thirdPartyDomainID IN ({identifiers});",
        ]
    run_sqlite(CB_STATS_DB, " ".join(statements))


def clean_hsts(bookmark_domains):
    if not Path(HSTS_PLIST).is_file():
        return

    try:
        with open(HSTS_PLIST, "rb") as handle:
            root = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        sys.stderr.write(f"Failed to parse HSTS plist: {error}\n")
        return

    # Structure: the defaultStorageSession dictionary maps each host to its own
    # dictionary of HSTS state
    session = root.get("com.apple.CFNetwork.defaultStorageSession")
    if not isinstance(session, dict):
        return

    removed = [
        host for host in session if not domain_matches_bookmarks(host, bookmark_domains)
    ]
    total = len(session)

    if not removed:
        return

    action = "Would remove" if options.dry_run else "Removing"
    print(f"{action} {len(removed)} of {total} HSTS entries")

    if options.verbose:
        for host in removed:
            print(f"  DELETE: {host}")

    if options.dry_run:
        return

    for host in removed:
        del session[host]

    handle, temp_path = tempfile.mkstemp()
    with os.fdopen(handle, "wb") as temp_file:
        plistlib.dump(root, temp_file, fmt=plistlib.FMT_BINARY)

    try:
        os.replace(temp_path, HSTS_PLIST)
    except OSError as error:
        sys.stderr.write(f"HSTS rename failed: {error}\n")


def url_host(url):
    match = URL_HOST.match(url)
    if not match:
        return None
    host = match.group(1).lower()
    host = re.sub(r"^www\.", "", host)
    return re.sub(r":\d+$", "", host)


def clean_favicons(bookmark_domains):
    if not Path(FAVICONS_DB).is_file():
        return

    page_delete = {}  # uuid => host (for page_url table)
    reject_delete = []  # page_url rows to remove from rejected_resources

    total_page = 0
    for line in sqlite_lines(
        query_sqlite(FAVICONS_DB, "SELECT url, uuid FROM page_url;")
    ):
        url, _, uuid = line.partition("|")
        if not url:
            continue
        total_page += 1
        host = url_host(url)
        if host is None:
            continue
        if not domain_matches_bookmarks(host, bookmark_domains):
            page_delete[uuid] = host

    total_rej = 0
    for url in sqlite_lines(
        query_sqlite(FAVICONS_DB, "SELECT page_url FROM rejected_resources;")
    ):
        if not url:
            continue
        total_rej += 1
        host = url_host(url)
        if host is None:
            continue
        if not domain_matches_bookmarks(host, bookmark_domains):
            reject_delete.append(url)

    if not page_delete and not reject_delete:
        return

    action = "Would remove" if options.dry_run else "Removing"
    print(
        f"{action} {len(page_delete)}/{total_page} favicon page rows + "
        f"{len(reject_delete)}/{total_rej} rejected_resources rows"
    )

    if options.dry_run:
        return

    statements = []
    if page_delete:
        uuids = ",".join(f"'{uuid}'" for uuid in page_delete)
        statements += [
            f"DELETE FROM page_url  WHERE uuid IN ({uuids});",
            f"DELETE FROM icon_info WHERE uuid IN ({uuids});",
        ]
    if reject_delete:
        urls = ",".join("'" + url.replace("'", "''") + "'" for url in reject_delete)
        statements.append(f"DELETE FROM rejected_resources WHERE page_url IN ({urls});")
    run_sqlite(FAVICONS_DB, " ".join(statements))


def clean_screen_time(bookmark_domains):
    if not Path(KNOWLEDGE_DB).is_file():
        return

    # Reset Screen Time TCC authorizations — clears which apps have
    # been granted Screen Time API access. Does not touch knowledgeC
    # data; the SQL below handles that.
    if options.dry_run:
        print("Would run: tccutil reset ScreenTime")
    else:
        if (
            subprocess.run(["tccutil", "reset", "ScreenTime"], check=False).returncode
            != 0
        ):
            sys.stderr.write("tccutil reset ScreenTime failed\n")
        elif options.verbose:
            print("Reset ScreenTime TCC entries")

    # Query ZSTRUCTUREDMETADATA directly so orphaned rows (no ZOBJECT
    # reference) are also caught. We'll cascade-delete ZOBJECT rows that
    # point at the metadata we're removing.
    rows = query_sqlite(
        KNOWLEDGE_DB,
        "SELECT Z_PK, Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN FROM ZSTRUCTUREDMETADATA "
        "WHERE Z_DKDIGITALHEALTHMETADATAKEY__WEBDOMAIN IS NOT NULL;",
    )

    to_delete = []
    total = 0
    for line in sqlite_lines(rows):
        primary_key, _, domain = line.partition("|")
        if not domain:
            continue
        total += 1
        if not domain_matches_bookmarks(domain, bookmark_domains):
            to_delete.append({"pk": primary_key, "domain": domain})

    if not to_delete:
        return

    action = "Would remove" if options.dry_run else "Removing"
    print(f"{action} {len(to_delete)} of {total} Screen Time web usage entries")

    if options.verbose:
        for item in to_delete:
            print(f"  DELETE: {item['domain']}")

    if options.dry_run:
        return

    keys = ",".join(item["pk"] for item in to_delete)
    sql = (
        f"DELETE FROM ZOBJECT WHERE ZSTRUCTUREDMETADATA IN ({keys}); "
        f"DELETE FROM ZSTRUCTUREDMETADATA WHERE Z_PK IN ({keys});"
    )
    count_sql = f"SELECT COUNT(*) FROM ZSTRUCTUREDMETADATA WHERE Z_PK IN ({keys});"

    run_sqlite(KNOWLEDGE_DB, sql)
    remaining = shell(f'sqlite3 "{KNOWLEDGE_DB}" "{count_sql}"').strip()

    if count_of(remaining) > 0:
        if options.verbose:
            print(
                f"knowledgeC.db blocked ({remaining} rows remain), "
                "kicking daemons and retrying"
            )
        stop_knowledge_daemons()
        run_sqlite(KNOWLEDGE_DB, sql)
        remaining = shell(f'sqlite3 "{KNOWLEDGE_DB}" "{count_sql}"').strip()
        if count_of(remaining) > 0:
            sys.stderr.write(
                f"knowledgeC.db still has {remaining} target rows after daemon "
                "restart. Screen Time cleanup failed.\n"
            )


def clean_biome_streams():
    # Safari's "Screen Time" website-data rows are fed by Biome log streams,
    # not knowledgeC. The streams are binary append-logs with no per-domain
    # delete API, so we wipe the local chunks and let biomed rebuild — same
    # tradeoff as alt_services. biomed holds the files open and rewrites on
    # exit, so it must be stopped first.
    biome_root = f"{HOME}/Library/Biome/streams/restricted"
    streams = ("Safari.AutoPlay", "Safari.Navigations", "App.WebUsage")

    to_clean = [
        f"{biome_root}/{stream}/local"
        for stream in streams
        if Path(f"{biome_root}/{stream}/local").is_dir()
    ]
    if not to_clean:
        return

    action = "Would wipe" if options.dry_run else "Wiping"
    print(f"{action} {len(to_clean)} Biome stream local chunks (Screen Time web data)")

    if options.verbose:
        for path in to_clean:
            print(f"  DELETE: {path}")

    if options.dry_run:
        return

    uid = os.getuid()
    subprocess.run(["launchctl", "bootout", f"gui/{uid}/com.apple.biomed"], check=False)
    for path in to_clean:
        shutil.rmtree(path, ignore_errors=True)
    subprocess.run(
        ["launchctl", "kickstart", f"gui/{uid}/com.apple.biomed"], check=False
    )


def clean_webkit_cache():
    for directory in (WEBKIT_CACHE, f"{SAFARI_TMP}/WebKit/MediaCache"):
        if not Path(directory).is_dir():
            continue
        if options.dry_run:
            print(f"Would clear {directory}")
        else:
            for entry in os.listdir(directory):
                path = f"{directory}/{entry}"
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path, ignore_errors=True)
                else:
                    try:
                        os.unlink(path)
                    except OSError:
                        pass
            print(f"{directory} cleared")


# ****************************************************************************************
# script main line
# ****************************************************************************************
def main(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--dry-run", "-n", action="store_true", dest="dry_run")
    parser.add_argument("--verbose", "-v", action="store_true")

    try:
        parser.parse_args(argv, namespace=options)
    except SystemExit:
        die(f"Usage: {sys.argv[0]} [--dry-run|-n] [--verbose|-v]")

    # Run the AppleScript
    subprocess.run(["/usr/bin/osascript"], input=APPLESCRIPT, text=True, check=False)
    check_safari_not_running()

    bookmark_domains = extract_bookmark_domains()
    if not bookmark_domains:
        die("No bookmarked domains found")
    for domain in WHITELIST_DOMAINS:
        bookmark_domains[domain] = 1

    if options.verbose:
        print(
            f"Found {len(bookmark_domains)} bookmarked domains "
            f"(incl. {len(WHITELIST_DOMAINS)} whitelisted)"
        )

    clean_cookies(bookmark_domains)
    clean_observations_db(bookmark_domains)
    clean_website_data(bookmark_domains)
    clean_alt_services(bookmark_domains)
    clean_url_cache()
    clean_history_db(bookmark_domains)
    clean_recently_closed_tabs()
    clean_content_blocker_stats(bookmark_domains)
    clean_hsts(bookmark_domains)
    clean_favicons(bookmark_domains)
    clean_screen_time(bookmark_domains)
    clean_biome_streams()
    clean_webkit_cache()
    shell("safari-restore-icons.sh")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
