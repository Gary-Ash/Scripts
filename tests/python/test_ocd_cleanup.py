# *****************************************************************************************
# test_ocd_cleanup.py
#
# tests for ocd-cleanup.py
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  25-Nov-2026  4:54pm
# Modified :  25-Nov-2026  5:21pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
# *****************************************************************************************
import importlib.util
import plistlib
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent.parent / "scripts" / "ocd-cleanup.py"

_spec = importlib.util.spec_from_file_location("ocd_cleanup", SCRIPT)
assert _spec is not None and _spec.loader is not None
ocd_cleanup = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ocd_cleanup)


def write_plist_with_junk_key(tmp_path):
    plist_file = tmp_path / "com.example.ocdtest.plist"
    plist_file.write_bytes(
        plistlib.dumps(
            {"RecentDocuments": ["/tmp/a.txt"], "KeepMe": "yes"},
            fmt=plistlib.FMT_BINARY,
        )
    )
    return plist_file


@pytest.fixture
def run_calls(monkeypatch):
    """Records every subprocess.run argument list while still running the command."""
    calls = []
    real_run = ocd_cleanup.subprocess.run

    def spy_run(args, *rest, **kwargs):
        calls.append(list(args))
        return real_run(args, *rest, **kwargs)

    monkeypatch.setattr(ocd_cleanup.subprocess, "run", spy_run)
    return calls


def test_top_level_junk_key_is_removed_with_defaults_delete(run_calls, tmp_path):
    plist_file = write_plist_with_junk_key(tmp_path)

    ocd_cleanup.processFile(str(plist_file))

    assert [
        "defaults",
        "delete",
        str(tmp_path / "com.example.ocdtest"),
        "RecentDocuments",
    ] in run_calls
    assert plistlib.loads(plist_file.read_bytes()) == {"KeepMe": "yes"}


def test_defaults_delete_runs_as_sudo_user_when_root(monkeypatch, tmp_path):
    plist_file = write_plist_with_junk_key(tmp_path)
    calls = []

    def fake_run(args, *rest, **kwargs):
        calls.append(list(args))
        return ocd_cleanup.subprocess.CompletedProcess(args, 0)

    monkeypatch.setattr(ocd_cleanup.subprocess, "run", fake_run)
    monkeypatch.setattr(ocd_cleanup.os, "geteuid", lambda: 0)
    monkeypatch.setenv("SUDO_USER", "someone")

    ocd_cleanup.processFile(str(plist_file))

    assert [
        "sudo",
        "-u",
        "someone",
        "defaults",
        "delete",
        str(tmp_path / "com.example.ocdtest"),
        "RecentDocuments",
    ] in calls


def test_top_level_and_nested_values_junk_keys_are_both_removed(tmp_path):
    plist_file = tmp_path / "com.example.ocdnested.plist"
    plist_file.write_bytes(
        plistlib.dumps(
            {
                "RecentDocuments": ["/tmp/a.txt"],
                "KeepMe": "yes",
                "values": {"RecentFindStrings": ["needle"], "KeepNested": 1},
            },
            fmt=plistlib.FMT_BINARY,
        )
    )

    ocd_cleanup.processFile(str(plist_file))

    assert plistlib.loads(plist_file.read_bytes()) == {
        "KeepMe": "yes",
        "values": {"KeepNested": 1},
    }


def test_podcast_play_state_key_is_removed_with_defaults_delete(
    monkeypatch, run_calls, tmp_path
):
    prefs_dir = (
        tmp_path / "Library/Containers/com.apple.podcasts/Data/Library/Preferences"
    )
    prefs_dir.mkdir(parents=True)
    plist_file = prefs_dir / "com.apple.podcasts.plist"
    plist_file.write_bytes(
        plistlib.dumps(
            {"playState:abc": 42, "KeepMe": "yes"},
            fmt=plistlib.FMT_BINARY,
        )
    )
    monkeypatch.setattr(ocd_cleanup, "HOME", str(tmp_path))

    ocd_cleanup.podcastapp()

    assert [
        "defaults",
        "delete",
        str(prefs_dir / "com.apple.podcasts"),
        "playState:abc",
    ] in run_calls
    assert plistlib.loads(plist_file.read_bytes()) == {"KeepMe": "yes"}


def test_texturepacker_users_key_is_removed_with_defaults_delete(
    monkeypatch, run_calls, tmp_path
):
    prefs_dir = tmp_path / "Library/Preferences"
    prefs_dir.mkdir(parents=True)
    plist_file = prefs_dir / "de.code-and-web.TexturePacker.plist"
    plist_file.write_bytes(
        plistlib.dumps(
            {"/Users/someone/project.tps": "recent", "KeepMe": "yes"},
            fmt=plistlib.FMT_BINARY,
        )
    )
    monkeypatch.setattr(ocd_cleanup, "HOME", str(tmp_path))

    ocd_cleanup.texturePacker()

    assert [
        "defaults",
        "delete",
        str(prefs_dir / "de.code-and-web.TexturePacker"),
        "/Users/someone/project.tps",
    ] in run_calls
    assert plistlib.loads(plist_file.read_bytes()) == {"KeepMe": "yes"}


def test_bbedit_saved_bounds_key_is_removed_with_defaults_delete(
    monkeypatch, run_calls, tmp_path
):
    prefs_dir = (
        tmp_path / "Library/Containers/com.barebones.bbedit/Data/Library/Preferences"
    )
    prefs_dir.mkdir(parents=True)
    plist_file = prefs_dir / "com.barebones.bbedit.plist"
    plist_file.write_bytes(
        plistlib.dumps(
            {"InstaprojectWindowSavedBounds-1": "{0, 0, 100, 100}", "KeepMe": "yes"},
            fmt=plistlib.FMT_BINARY,
        )
    )
    monkeypatch.setattr(ocd_cleanup, "HOME", str(tmp_path))

    ocd_cleanup.BBEdit()

    assert [
        "defaults",
        "delete",
        str(prefs_dir / "com.barebones.bbedit"),
        "InstaprojectWindowSavedBounds-1",
    ] in run_calls
    assert plistlib.loads(plist_file.read_bytes()) == {"KeepMe": "yes"}


def test_books_recents_last_cleared_is_set_with_defaults_write_string(
    monkeypatch, run_calls, tmp_path
):
    prefs_dir = (
        tmp_path / "Library/Containers/com.apple.iBooksX/Data/Library/Preferences"
    )
    prefs_dir.mkdir(parents=True)
    plist_file = prefs_dir / "com.apple.iBooksX.plist"
    plist_file.write_bytes(plistlib.dumps({"KeepMe": "yes"}, fmt=plistlib.FMT_BINARY))
    monkeypatch.setattr(ocd_cleanup, "HOME", str(tmp_path))

    ocd_cleanup.books()

    write_prefix = [
        "defaults",
        "write",
        str(prefs_dir / "com.apple.iBooksX"),
        "BKRecentsLastCleared",
        "-string",
    ]
    write_calls = [call for call in run_calls if call[:5] == write_prefix]
    assert len(write_calls) == 1, run_calls
    date_string = write_calls[0][-1]
    plist = plistlib.loads(plist_file.read_bytes())
    assert isinstance(date_string, str)
    assert plist["BKRecentsLastCleared"] == date_string
    assert plist["KeepMe"] == "yes"


def test_xcode_template_options_and_nav_root_are_set_with_defaults_write(
    monkeypatch, run_calls, tmp_path
):
    prefs_dir = tmp_path / "Library/Preferences"
    prefs_dir.mkdir(parents=True)
    plist_file = prefs_dir / "com.apple.dt.Xcode.plist"
    plist_file.write_bytes(
        plistlib.dumps(
            {
                "IDETemplateOptions": {"languageChoice": "Objective-C", "old": "x"},
                "KeepMe": "yes",
            },
            fmt=plistlib.FMT_BINARY,
        )
    )
    monkeypatch.setattr(ocd_cleanup, "HOME", str(tmp_path))

    ocd_cleanup.xcode()

    domain = str(prefs_dir / "com.apple.dt.Xcode")
    assert [
        "defaults",
        "write",
        domain,
        "IDETemplateOptions",
        "-dict",
        "languageChoice",
        "Swift",
        "bundleIdentifierPrefix",
        "com.geedbla",
        "ORGANIZATIONNAME",
        "Gee Dbl A",
    ] in run_calls
    assert [
        "defaults",
        "write",
        domain,
        "NSNavLastRootDirectory",
        "-string",
        f"{tmp_path}/Developer/",
    ] in run_calls
    plist = plistlib.loads(plist_file.read_bytes())
    assert plist["IDETemplateOptions"] == {
        "languageChoice": "Swift",
        "bundleIdentifierPrefix": "com.geedbla",
        "ORGANIZATIONNAME": "Gee Dbl A",
    }
    assert plist["NSNavLastRootDirectory"] == f"{tmp_path}/Developer/"
    assert plist["KeepMe"] == "yes"


def test_sublime_text_nav_root_is_set_with_defaults_write_string(
    monkeypatch, run_calls, tmp_path
):
    session_dir = tmp_path / "Library/Application Support/Sublime Text/Local"
    session_dir.mkdir(parents=True)
    (session_dir / "Session.sublime_session").write_text("{}")
    prefs_dir = tmp_path / "Library/Preferences"
    prefs_dir.mkdir(parents=True)
    plist_file = prefs_dir / "com.sublimetext.4.plist"
    plist_file.write_bytes(
        plistlib.dumps(
            {"NSNavLastRootDirectory": "/old/place/", "KeepMe": "yes"},
            fmt=plistlib.FMT_BINARY,
        )
    )
    monkeypatch.setattr(ocd_cleanup, "HOME", str(tmp_path))

    ocd_cleanup.sublimeText()

    assert [
        "defaults",
        "write",
        str(prefs_dir / "com.sublimetext.4"),
        "NSNavLastRootDirectory",
        "-string",
        f"{tmp_path}/Developer/",
    ] in run_calls
    plist = plistlib.loads(plist_file.read_bytes())
    assert plist["NSNavLastRootDirectory"] == f"{tmp_path}/Developer/"
    assert plist["KeepMe"] == "yes"


def test_sublime_merge_nav_root_is_set_with_defaults_write_string(
    monkeypatch, run_calls, tmp_path
):
    session_dir = tmp_path / "Library/Application Support/Sublime Merge/Local"
    session_dir.mkdir(parents=True)
    (session_dir / "Session.sublime_session").write_text("{}")
    prefs_dir = tmp_path / "Library/Preferences"
    prefs_dir.mkdir(parents=True)
    plist_file = prefs_dir / "com.sublimemerge.plist"
    plist_file.write_bytes(
        plistlib.dumps(
            {"NSNavLastRootDirectory": "/old/place/", "KeepMe": "yes"},
            fmt=plistlib.FMT_BINARY,
        )
    )
    monkeypatch.setattr(ocd_cleanup, "HOME", str(tmp_path))

    ocd_cleanup.sublimeMerge()

    assert [
        "defaults",
        "write",
        str(prefs_dir / "com.sublimemerge"),
        "NSNavLastRootDirectory",
        "-string",
        f"{tmp_path}/Developer/",
    ] in run_calls
    plist = plistlib.loads(plist_file.read_bytes())
    assert plist["NSNavLastRootDirectory"] == f"{tmp_path}/Developer/"
    assert plist["KeepMe"] == "yes"
