#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# *****************************************************************************************
# ocd-cleanup.py
#
# Strip junk keys, recent-file lists, and caches from app preferences and folders for ocd.sh
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  25-Nov-2026  4:51pm
# Modified :  25-Nov-2026  5:23pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
# *****************************************************************************************
# *****************************************************************************************
# libraries used
# *****************************************************************************************
import datetime
import glob
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys

# *****************************************************************************************
# globals
# *****************************************************************************************
HOME = os.environ["HOME"]

PLIST_KEYS_TO_DELETE = (
    "ChatAPIIdentifier",
    "ChatGPTModel",
    "ClaudeModel",
    "NSWindow Frame ChatGPTKeyEntryPanel",
    "ListSignupEmailAddress",
    "ListSignupUserName",
    "NewBookmarksLocationUUID",
    "RecentSearchStrings",
    "FXRecentFolders",
    "GoToField",
    "RecentApplications",
    "RecentDocuments",
    "RecentServers",
    "Hosts",
    "ExpandedURLs",
    "last_textureFileName",
    "FXLastSearchScope",
    "NSNavPanel",
    "NSNavRecentPlaces",
    "NSNavLastRootDirectory",
    "NSNavLastCurrentDirectory",
    "LRUDocumentPaths",
    "TSAOpenedTemplates.Pages",
    "NSReplacePboard",
    "SelectedURLs",
    "Apple CFPasteboard find",
    "Apple CFPasteboard replace",
    "Apple CFPasteboard general",
    "findHistory",
    "replaceHistory",
    "MGRecentURLPropertyLists",
    "OakFindPanelOptions",
    "Folder Search Options",
    "recentFileList",
    "RecentDirectories",
    "NSRecentXCProjectDocuments",
    "last_dataFileName",
    "lastSpritesFolder",
    "main.lastFileName",
    "defaults.settingsAbsPath",
    "DefaultCheckOutDirectory",
    "RecentWorkingCopies",
    "kProjectBasePath",
    "LastOpenedScene",
    "ABBookWindowController-MainBookWindow-personListController",
    "IDEFileTemplateChooserAssistantSelectedTemplateCategory",
    "IDEFileTemplateChooserAssistantSelectedTemplateName",
    "IDERecentEditorDocuments",
    "XCOpenWorkspaceDocuments",
    "IDETemplateCompletionDefaultPath",
    "IDETemplateOptions",
    "IDEDefaultPrimaryEditorFrameSizeForPaths",
    "IDEDocViewerLastViewedURLKey",
    "IDESourceControlRecentsFavoritesRepositoriesUserDefaultsKey",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateCategory",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateCategory",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateSection",
    "last_name",
    "findRecentPlaces",
    "RecentWebSearches",
    "recentSearches",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_macOS",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_iOS",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_tvOS",
    "SGTRecentFileSearches",
    "IDEDistributionPlanSelection",
    "IDEFileTemplateChooserAssistantSelectedTemplateSection",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_tvOS",
    "IDEFileTemplateChooserAssistantSelectedTemplateName_tvOS",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_iOS",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_Multiplatform",
    "Xcode3ProjectTemplateChooserAssistantSelectedTemplateName_macOS",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateName_Multiplatform",
    "Xcode3TargetTemplateChooserAssistantSelectedTemplateSection",
    "DVTTextCompletionRecentCompletions",
    "GoToFieldHistory",
    "HistoryColors",
    "recentSearchHints",
    "SHKRecentServices",
    "FavoriteColors",
    "LastSetWindowSizeForDocument",
    "recentCatalogPaths",
    "IDELastBreakpointActionClassName",
    "RecentFindStrings",
    "IDEFileTemplateChooserAssistantSelectedTemplateName_iOS",
    "RecentReplaceStrings",
    "IDESwiftMigrationAssistantReviewFilesSelectedChoice",
    "IDERunActionSelectedTab",
    "DVTIgnoredDevices",
    "IBGlobalLastEditorDocumentClassName",
    "IBDocumentOutlineViewMode",
    "IDELibrary.lastSelectedLibraryExtensionIDByEditorID",
    "IBGlobalLastEditorTargetRuntime",
    "CurrentAlertPreferencesSelection",
    "DVTRecentCustomColors",
    "IDEProvisioningTeamManagerLastSelectedTeamID",
    "BKRecentsLastCleared",
    "BKPreviouslyOpenedBookIDs",
    "RecentMoveAndCopyDestinations",
    "DownloadsFolderListViewSettingsVersion",
    "recent_viewed",
    "RecentsArrangeGroupViewBy",
    "IDEAppChooserRecentApplications-My Mac",
    "RecentRegions",
    "IDEFileTemplateChooserAssistantSelectedTemplateName_macOS",
    "lastSource",
    "lastReplacement",
    "lastRegex",
    "TSARecentOpenedDocumentTimestamps",
    "TSAOpenedTemplates.Numbers",
    "FindDialog_SearchReplaceHistory",
    "ApplicationSleepState",
    "ApplicationAutoSaveState",
    "CurrentWorkspaceDocumentName",
    "FindDialog_SelectedSourceNodes",
    "NSOSPLastRootDirectory",
    "RecentItemsData",
    "PropertyWindowsToReopen",
    "LastPersistenceCleanupDateKey",
    "XCCArchiveReminderPromptDate",
    "OpenDocuments",
    "IDEAppStatisticsXcodeVersionMetricsHistoryStorage",
    "IDE_CA_Daily_LastReport",
    "IDE_CA_Daily_UptimeHours",
    "IDE_CA_Daily_SessionCount",
    "PreferencesSnapshotDate",
    "LastOpenByNameString",
    "IDEChatUserSelectedDefaultChatModelDefinitionIdentifier",
    "IDEAnalyticsMetricsNotifications.AnalyticsMetricsNotificationsController.lastRefreshAttemptDate",
    "SULastCheckedDate",
    "LastLaunchOSVersion",
    "savedLastOpen",
    "IDELastViewedSettingsPane",
    "LastTerminalStartTime",
    "IDEMostRecentPostFLEDate",
    "RecentTemplates",
)

# *****************************************************************************************
# each entry is a glob pattern and a keep_root flag - a true flag empties the directory
# but leaves the directory itself in place
# *****************************************************************************************
ITEMS_TO_DELETE = (
    (
        f"{HOME}/Library/Containers/com.apple.corerecents.recentsd/Data/Library/Recents",
        0,
    ),
    (
        f"{HOME}/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments",
        0,
    ),
    (
        f"{HOME}/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentDocuments.sfl3",
        0,
    ),
    (
        f"{HOME}/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ProjectsItems.sfl3",
        0,
    ),
    (
        f"{HOME}/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentApplications.sfl3",
        0,
    ),
    (
        f"{HOME}/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentServers.sfl3",
        0,
    ),
    (
        f"{HOME}/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentHosts.sfl3",
        0,
    ),
    (f"{HOME}/Library/Application Support/zoxide/", 1),
    (f"{HOME}/Library/Preferences/com.googlecode.iterm2.private.plist", 0),
    (f"{HOME}/Library/Preferences/com.apple.dock.extra.plist", 0),
    (f"{HOME}/Library/Preferences/us.zoom.ZoomClips.plist", 0),
    (f"{HOME}/Library/Preferences/org.sparkle-project.Sparkle.Autoupdate.plist", 0),
    (f"{HOME}/.proxyman-data", 0),
    (f"{HOME}/.hawtjni", 0),
    (f"{HOME}/.npm", 0),
    (f"{HOME}/.konan", 0),
    (f"{HOME}/.ssh/known_hosts.old", 0),
    (f"{HOME}/.cocoapods", 0),
    (f"{HOME}/.swiftpm", 0),
    (f"{HOME}/.fastlane", 0),
    (f"{HOME}/.subversion", 0),
    (f"{HOME}/.node_modules", 0),
    (f"{HOME}/.android/", 0),
    (f"{HOME}/.cache/", 0),
    (f"{HOME}/.bash_history", 0),
    (f"{HOME}/.python_history", 0),
    (f"{HOME}/.zcompcache", 0),
    (f"{HOME}/.zsh_history", 0),
    (f"{HOME}/.bundle", 0),
    (f"{HOME}/.gem", 0),
    (f"{HOME}/Library/Caches/Yarn", 0),
    (f"{HOME}/.oracle_jre_usage", 0),
    (f"{HOME}/.bash_sessions", 0),
    (f"{HOME}/.gradle", 0),
    (f"{HOME}/.recently-used", 0),
    (f"{HOME}/.cmake", 0),
    (f"{HOME}/.solargraph", 0),
    (f"{HOME}/.TemporaryItems", 0),
    (f"{HOME}/.thumbnails", 0),
    (f"{HOME}/.config/zsh/.zsh_sessions", 0),
    (f"{HOME}/.config/zsh/histfile", 1),
    (f"{HOME}/.config/zsh/.zsh_history", 1),
    (f"{HOME}/.config/zsh/zcompdump-*", 1),
    (f"{HOME}/triald-*.ips", 1),
    (f"{HOME}/.config/configstore", 0),
    (f"{HOME}/Pictures/Pixelmator Pro Sidecar Files/", 0),
    (f"{HOME}/Library/Application Support/BBEdit/Workspaces", 0),
    (f"{HOME}/Library/Logs/Xcode/Coding Assistant", 0),
    (
        f"{HOME}/Library/Containers/com.barebones.bbedit/Data/Library/BBEdit/Rescued Documents",
        1,
    ),
    (
        f"{HOME}/Library/Containers/com.barebones.bbedit/Data/Library/BBEdit/Auto-Save Recovery",
        0,
    ),
    (f"{HOME}/Library/Containers/com.barebones.bbedit/Data/Sleep State.appstate", 0),
    (f"{HOME}/Library/Autosave Information", 0),
    (f"{HOME}/Library/Caches/org.carthage.CarthageKit", 0),
    (f"{HOME}/Library/Saved Application State", 0),
    (f"{HOME}/Library/Application Support/Steam", 0),
    (f"{HOME}/Library/Application Support/iLifeMediaBrowser", 0),
    (f"{HOME}/Library/Application Support/CrashReporter", 0),
    (f"{HOME}/Library/Application Support/CallHistoryDB", 0),
    (f"{HOME}/Library/Application Support/CallHistoryTransactions", 0),
    (f"{HOME}/Library/Application Support/dmd", 0),
    (f"{HOME}/Library/Application Support/iMovie", 0),
    (f"{HOME}/Library/Application Support/Translation", 0),
    (f"{HOME}/Library/Developer/CoreSimulator/Caches", 0),
    (f"{HOME}/Library/Developer/Xcode/UserData/IDEEditorInteractivityHistory", 0),
    (f"{HOME}/Library/Developer/Xcode/DocumentationCache", 0),
    (f"{HOME}/Library/Developer/Xcode/.derived-data-log*", 0),
    (f"{HOME}/Library/Developer/Xcode/DocumentationIndex", 0),
    (f"{HOME}/Library/Developer/Xcode/Products", 0),
    (f"{HOME}/Library/Caches/Homebrew", 0),
    (f"{HOME}/Library/Cookies/Hocom.kapeli.dashdoc.binarycookies", 0),
    (f"{HOME}/Library/Cookies/org.m0k.transmission.binarycookies", 0),
    (f"{HOME}/Library/Caches/com.apple.dt.Xcode", 0),
    (f"{HOME}/Pictures/iSkysoft VideoConverterUltimate", 0),
    (f"{HOME}/Movies/iSkysoft VideoConverterUltimate", 0),
    (f"{HOME}/Library/Preferences/com.apple.LaunchServices", 0),
    (f"{HOME}/Library/Preferences/UITextInputContextIdentifiers.plist", 0),
    (f"{HOME}/Library/Preferences/com.apple.EmojiCache.plist", 1),
    (f"{HOME}/Library/Preferences/com.apple.EmojiPreferences.plist", 1),
    (f"{HOME}/Movies/Motion Templates.localized", 0),
    (f"{HOME}/Movies/Untitled.fcpbundle", 0),
    (f"{HOME}/Movies/iMovie Library.imovielibrary", 0),
    (f"{HOME}/Movies/iMovie Theater.theater", 0),
    (f"{HOME}/Music/Audio Music Apps", 0),
    (f"{HOME}/Library/Application Support/kotlin", 0),
    (f"{HOME}/Library/Application Support/Mozilla", 0),
    (f"{HOME}/Library/Application Support/JetBrains", 0),
    (f"{HOME}/Library/Application Support/Battle.net", 0),
    (f"{HOME}/Library/org.swift.swiftpm", 0),
    (f"{HOME}/Music/Logic", 0),
    (f"{HOME}/Library/Cookies/com.apple.Safari.SearchHelper.binarycookies", 0),
    (f"{HOME}/Library/Application Support/iPhone Simulator", 0),
    (f"{HOME}/Library/Messages/Archive", 0),
    (f"{HOME}/Library/Messages/Attachments", 0),
    (f"{HOME}/Library/Metadata/com.apple.IntelligentSuggestions", 1),
    (f"{HOME}/Library/Application Support/Xcode", 1),
    (f"{HOME}/Library/Developer/Xcode/Archives", 0),
    (f"{HOME}/Library/Developer/Xcode/snapshots", 0),
    (f"{HOME}/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig", 1),
    (f"{HOME}/Library/Developer/Xcode/UserData/*.xcuserstate", 1),
    (f"{HOME}/Library/Developer/Xcode/UserData/CodingAssistant", 1),
    (f"{HOME}/Library/Application Support/Alfred/Caches", 1),
    (f"{HOME}/Library/Application Support/Alfred/Workflow Data", 1),
    (
        f"{HOME}/Library/Application Support/Sublime Merge/Local/Backup Session.sublime_session",
        0,
    ),
    (f"{HOME}/Library/Application Support/Sublime Merge/Log", 0),
    (f"{HOME}/Library/Application Support/Sublime Merge/Cache", 1),
    (f"{HOME}/Library/Application Support/Sublime Text/Backup", 0),
    (f"{HOME}/Library/Application Support/Sublime Text/Cache", 1),
    (f"{HOME}/Library/Application Support/Sublime Text/Index", 1),
    (f"{HOME}/Library/Application Support/Sublime Text/Log", 0),
    (f"{HOME}/Library/Application Support/Sublime Text/Trash", 0),
    (
        f"{HOME}/Library/Application Support/Sublime Text/Local/Backup Auto Save Session.sublime_session",
        0,
    ),
    (
        f"{HOME}/Library/Application Support/Sublime Text/Local/Backup Session.sublime_session",
        0,
    ),
    (
        f"{HOME}/Library/Application Support/Sublime Text/Packages/User/Package Control.cache",
        1,
    ),
    (f"{HOME}/Library/Application Support/Sublime Text (Safe Mode)", 0),
    (f"{HOME}/Library/Caches/com.apple.Safari/Webpage Previews", 1),
    (f"{HOME}/Library/Caches/com.apple.Safari/Cache.*", 1),
    (f"{HOME}/Library/Caches/com.apple.Safari/fsCachedData", 1),
    (f"{HOME}/Library/Caches/com.apple.Safari/WebKitCache", 1),
    (f"{HOME}/Library/Safari/Configurations.plist.signed", 1),
    (f"{HOME}/Library/Caches/com.apple.Safari/Cache.db", 1),
    (f"{HOME}/Library/Safari/CloudBookmarksMigrationCoordinator", 0),
    (f"{HOME}/Library/Safari/Cloud*", 1),
    (f"{HOME}/Library/Safari/LastSession.plist", 1),
    (f"{HOME}/Library/Safari/TopSites.plist", 1),
    (f"{HOME}/Library/Safari/Downloads.plist", 1),
    (f"{HOME}/Library/Safari/WebFeedSources.plist", 1),
    (f"{HOME}/Library/Safari/SearchDescriptions.plist", 1),
    (f"{HOME}/Library/Safari/RecentlyClosedTabs.plist", 1),
    (f"{HOME}/Library/Preferences/test_network.plist", 1),
    (f"{HOME}/Library/Preferences/com.apple.sharekit.recents.plist", 1),
    (f"{HOME}/Library/Preferences/com.trolltech.plist", 1),
    (f"{HOME}/Library/Preferences/com.qtproject.plist", 1),
    (f"{HOME}/Library/Application Support/Dash/Temp", 1),
    (f"{HOME}/Library/Developer/Xcode/UserData/IB Support", 0),
    (
        f"{HOME}/Library/Containers/com.koolesache.ColorSnapper2/Data/Library/Caches/com.koolesache.ColorSnapper2",
        0,
    ),
    (f"{HOME}/Library/Colors/NSColorPanelSwatches.plist", 1),
    (f"{HOME}/Library/Preferences/embeddedBinaryValidationUtility.plist", 1),
    (f"{HOME}/Library/Application Support/Microsoft Edge/Default/Sessions", 0),
    (f"{HOME}/Library/Application Support/Microsoft Edge/Default/*History*", 0),
    (f"{HOME}/Library/Application Support/Microsoft Edge/Default/Local Storage", 0),
    (f"{HOME}/Library/Application Support/Microsoft Edge/Default/Top Sites", 0),
    (f"{HOME}/Library/Application Support/Microsoft Edge/Default/Top Sites-journal", 0),
    (f"{HOME}/Library/Preferences/diagnostics_agent.plist", 0),
    (f"{HOME}/Library/Preferences/sharedfilelistd.plist", 0),
    (f"{HOME}/Library/Application Support/Google/Chrome/Profile 1/History", 0),
    (f"{HOME}/Library/Application Support/Google/Chrome/Profile 1/History-journal", 0),
    (f"{HOME}/Library/Application Support/Google/Chrome/Profile 1/Top Sites", 0),
    (
        f"{HOME}/Library/Application Support/Google/Chrome/Profile 1/Top Sites-journal",
        0,
    ),
    (f"{HOME}/Library/Application Support/Google/Chrome/Profile 1/Visited Links", 0),
    (
        f"{HOME}/Library/Containers/com.apple.iBooksX/Data/Documents/BCRecentlyOpenedBooksDB",
        0,
    ),
    (
        f"{HOME}/Library/Containers/com.runisoft.Video-Joiner-and-Merger/Data/Library/Preferences/com.runisoft.Video-Joiner-and-Merger.plist",
        0,
    ),
    (
        f"{HOME}/Library/Containers/com.bridgetech.asset-catalog/Data/Library/Application Support/saved_asset_catalog_creator",
        0,
    ),
    (f"{HOME}/Library/Caches/com.apple.Music/SubscriptionPlayCache/", 0),
    (f"{HOME}/Library/Application Support/iTerm2/SavedState/lock", 0),
    ("/Library/Logs", 1),
    ("/opt/geedbla/.mypy_cache", 0),
    ("/opt/geedbla/.pytest_cache", 0),
    ("/opt/geedbla/.ruff_cache", 0),
    ("/opt/geedbla/*/__pycache__", 0),
    ("/opt/geedbla/*/*/__pycache__", 0),
    (
        "/private/var/folders/sf/_p_7qs4n7gg_r4yrrrvmphd00000gn/C/us.zoom.ZoomAutoUpdater",
        0,
    ),
    (
        "/private/var/folders/3j/tgfs5z8x2wg2krlgnzj4jzc00000gn/C/com.koolesache.ColorSnapper2",
        0,
    ),
    (
        "/private/var/folders/3j/tgfs5z8x2wg2krlgnzj4jzc00000gn/T/com.koolesache.ColorSnapper2",
        0,
    ),
    (
        "/private/var/folders/3j/tgfs5z8x2wg2krlgnzj4jzc00000gn/C/com.koolesache.ColorSnapper2Helper",
        0,
    ),
    (
        "/private/var/folders/3j/tgfs5z8x2wg2krlgnzj4jzc00000gn/T/com.koolesache.ColorSnapper2Helper",
        0,
    ),
) + tuple((f"{HOME}/{path}", 0) for path in sys.argv[1:])


# *****************************************************************************************
# read a property list, remembering whether it was stored as XML or binary
# *****************************************************************************************
def readPlist(plistFile):
    try:
        with open(plistFile, "rb") as handle:
            data = handle.read()
        plist = plistlib.loads(data)
    except Exception:
        # this walks every plist on the machine - a malformed one must not stop the run
        return None, None

    if not isinstance(plist, dict):
        return None, None

    fmt = plistlib.FMT_BINARY if data[:8] == b"bplist00" else plistlib.FMT_XML
    return plist, fmt


# *****************************************************************************************
# rewrite a property list in place so the file keeps its owner, group and permissions
# *****************************************************************************************
def writePlist(plistFile, plist, fmt):
    try:
        data = plistlib.dumps(plist, fmt=fmt)
    except Exception:
        return

    try:
        with open(plistFile, "wb") as handle:
            handle.write(data)
    except OSError:
        pass


# *****************************************************************************************
# run the defaults command, as the sudo user when running as root
# *****************************************************************************************
def runDefaults(*arguments):
    sudoUser = os.environ.get("SUDO_USER")
    asUser = ["sudo", "-u", sudoUser] if os.geteuid() == 0 and sudoUser else []
    subprocess.run(
        [*asUser, "defaults", *arguments],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


# *****************************************************************************************
# remove every top-level key the predicate picks out of a property list with defaults
# *****************************************************************************************
def deleteKeysWithDefaults(plistFile, shouldDelete):
    plist, _ = readPlist(plistFile)
    if plist is None:
        return

    domain = plistFile.removesuffix(".plist")
    for key in list(plist):
        if shouldDelete(key):
            runDefaults("delete", domain, key)


# *****************************************************************************************
# set a value with defaults, only when the property list already exists so none is created
# *****************************************************************************************
def writeDefaults(plistFile, *arguments):
    plist, _ = readPlist(plistFile)
    if plist is None:
        return

    runDefaults("write", plistFile.removesuffix(".plist"), *arguments)


# *****************************************************************************************
# remove a file, a symlink or the contents of a directory tree
# *****************************************************************************************
def removeTree(path, keepRoot):
    if os.path.islink(path) or not os.path.isdir(path):
        try:
            os.unlink(path)
        except OSError:
            pass
        return

    try:
        entries = os.listdir(path)
    except OSError:
        return

    for entry in entries:
        child = os.path.join(path, entry)
        if os.path.islink(child) or not os.path.isdir(child):
            try:
                os.unlink(child)
            except OSError:
                pass
        else:
            shutil.rmtree(child, ignore_errors=True)

    if not keepRoot:
        try:
            os.rmdir(path)
        except OSError:
            pass


# *****************************************************************************************
# Books
# *****************************************************************************************
def books():
    datestring = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )

    writeDefaults(
        f"{HOME}/Library/Containers/com.apple.iBooksX/Data/Library/Preferences/com.apple.iBooksX.plist",
        "BKRecentsLastCleared",
        "-string",
        datestring,
    )


# *****************************************************************************************
# Sublime Text
# *****************************************************************************************
def sublimeText():
    filename = (
        f"{HOME}/Library/Application Support/Sublime Text/Local/Session.sublime_session"
    )
    keysToDelete = (
        "auto_complete",
        "file_history",
        "replace",
        "find_state",
        "find_in_files",
        "project",
        "buffers",
        "command_palette",
        "expanded_folders",
        "workspace_name",
        "folders",
        "console",
        "groups",
    )

    if not os.path.exists(filename):
        return

    with open(filename, "rb") as configFile:
        config = json.loads(configFile.read())

    config.pop("workspaces", None)
    config.pop("folder_history", None)
    for key in keysToDelete:
        config.pop(key, None)

    settings = config.get("settings")
    if isinstance(settings, dict):
        newWindowSettings = settings.get("new_window_settings")
        for key in keysToDelete:
            if isinstance(newWindowSettings, dict):
                newWindowSettings.pop(key, None)
            settings.pop(key, None)

    windows = config.get("windows") or []
    if windows:
        window = windows[0]
        for key in keysToDelete:
            window.pop(key, None)
        window["console"] = {"height": 220.0}
        config["windows"] = [window]

    with open(filename, "w", encoding="UTF-8") as configFile:
        configFile.write(json.dumps(config))

    writeDefaults(
        f"{HOME}/Library/Preferences/com.sublimetext.4.plist",
        "NSNavLastRootDirectory",
        "-string",
        f"{HOME}/Developer/",
    )


# *****************************************************************************************
# Sublime Merge
# *****************************************************************************************
def sublimeMerge():
    filename = f"{HOME}/Library/Application Support/Sublime Merge/Local/Session.sublime_session"
    keysToDelete = ("recent", "select_repository", "windows", "window_positions")

    if not os.path.exists(filename):
        return

    with open(filename, "rb") as configFile:
        config = json.loads(configFile.read())

    for key in keysToDelete:
        config.pop(key, None)
    config["project_dir"] = f"{HOME}/Developer"

    with open(filename, "w", encoding="UTF-8") as configFile:
        configFile.write(json.dumps(config))

    writeDefaults(
        f"{HOME}/Library/Preferences/com.sublimemerge.plist",
        "NSNavLastRootDirectory",
        "-string",
        f"{HOME}/Developer/",
    )


# *****************************************************************************************
# BBEdit
# *****************************************************************************************
def BBEdit():
    files = (
        f"{HOME}/Library/Containers/com.barebones.bbedit/Data/Library/Preferences/com.barebones.bbedit.plist",
        f"{HOME}/Library/Application Support/BBEdit/Setup/BBEdit Preferences Backup.plist",
    )
    checksum = re.compile(r"~[0-9A-Fa-f]{40}$")

    def isWindowStateOrChecksum(key):
        return (
            key.startswith("InstaprojectWindowSavedBounds")
            or key.startswith("ImageDisplayGrayLevel_")
            or key.startswith("ApplyTextTransformPanelSaved")
            or checksum.match(key)
        )

    for plistFile in files:
        deleteKeysWithDefaults(plistFile, isWindowStateOrChecksum)


# *****************************************************************************************
# Texture Packer
# *****************************************************************************************
def texturePacker():
    deleteKeysWithDefaults(
        f"{HOME}/Library/Preferences/de.code-and-web.TexturePacker.plist",
        lambda key: "Users" in key,
    )


# *****************************************************************************************
# Podcast
# *****************************************************************************************
def podcastapp():
    deleteKeysWithDefaults(
        f"{HOME}/Library/Containers/com.apple.podcasts/Data/Library/Preferences/com.apple.podcasts.plist",
        lambda key: "playState:" in key,
    )


# *****************************************************************************************
# strip the junk keys out of a single property list
# *****************************************************************************************
def processFile(plistFile):
    plist, fmt = readPlist(plistFile)
    if plist is None:
        return

    domain = plistFile.removesuffix(".plist")
    deletedWithDefaults = False
    for key in PLIST_KEYS_TO_DELETE:
        if key in plist:
            runDefaults("delete", domain, key)
            deletedWithDefaults = True

    # defaults rewrote the file, so reload it before touching the nested values
    if deletedWithDefaults:
        plist, fmt = readPlist(plistFile)
        if plist is None:
            return

    dirty = False
    values = plist.get("values")
    if isinstance(values, dict):
        for key in PLIST_KEYS_TO_DELETE:
            if key in values:
                del values[key]
                dirty = True

    if dirty:
        writePlist(plistFile, plist, fmt)


# *****************************************************************************************
# process the plists in the Preferences and Containers folders
# *****************************************************************************************
def plists():
    subprocess.run(
        ["killall", "Dock", "Finder", "recentsd"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    for plistFile in glob.glob(f"{HOME}/Library/Preferences/*.plist"):
        processFile(plistFile)

    for root, _, files in os.walk(f"{HOME}/Library/Containers/"):
        for name in files:
            if name.endswith(".plist"):
                processFile(os.path.join(root, name))


# *****************************************************************************************
# delete junk from a list of file and folders
# *****************************************************************************************
def deleteFilesAndFolders():
    subprocess.run(
        ["killall", "Dock", "Finder", "recentsd"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    for pattern, keepRoot in ITEMS_TO_DELETE:
        for path in glob.glob(pattern):
            if os.path.isfile(path) and not os.path.islink(path):
                try:
                    os.unlink(path)
                except OSError:
                    pass
            else:
                removeTree(path, keepRoot)

    temp = os.environ.get("TMPDIR")
    if temp:
        removeTree(temp, 1)


# *****************************************************************************************
# Xcode settings
# *****************************************************************************************
def xcode():
    plistFile = f"{HOME}/Library/Preferences/com.apple.dt.Xcode.plist"
    writeDefaults(
        plistFile,
        "IDETemplateOptions",
        "-dict",
        "languageChoice",
        "Swift",
        "bundleIdentifierPrefix",
        "com.geedbla",
        "ORGANIZATIONNAME",
        "Gee Dbl A",
    )
    writeDefaults(plistFile, "NSNavLastRootDirectory", "-string", f"{HOME}/Developer/")


# *****************************************************************************************
# script main line
# *****************************************************************************************
if __name__ == "__main__":
    podcastapp()
    texturePacker()
    BBEdit()

    plists()
    deleteFilesAndFolders()
    books()
    xcode()
    sublimeText()
    sublimeMerge()
