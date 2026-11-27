# *****************************************************************************************
# test_safari_cleaner.py
#
# tests for safari-cleaner.py
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  24-Nov-2026  7:37pm
# Modified :  24-Nov-2026  7:39pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
# *****************************************************************************************
import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent.parent / "scripts" / "safari-cleaner.py"

_spec = importlib.util.spec_from_file_location("safari_cleaner", SCRIPT)
assert _spec is not None and _spec.loader is not None
safari_cleaner = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(safari_cleaner)


def test_microsoft_login_cookie_is_kept_with_only_whitelist_domains():
    bookmark_domains = {d: 1 for d in safari_cleaner.WHITELIST_DOMAINS}

    kept = safari_cleaner.domain_matches_bookmarks(".login.microsoftonline.com", bookmark_domains)

    assert kept is True


def test_copilot_cookie_is_kept_with_only_whitelist_domains():
    bookmark_domains = {d: 1 for d in safari_cleaner.WHITELIST_DOMAINS}

    kept = safari_cleaner.domain_matches_bookmarks("copilot.com", bookmark_domains)

    assert kept is True
