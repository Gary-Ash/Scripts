#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# *****************************************************************************************
# test_fix_xcode_templates.py
#
# tests for fix-xcode-templates.py
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  19-Oct-2026  3:47pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
# *****************************************************************************************
import importlib.util
import plistlib
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "fix-xcode-templates.py"
_spec = importlib.util.spec_from_file_location("fix_xcode_templates", SCRIPT)
assert _spec is not None and _spec.loader is not None
fix_xcode_templates = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fix_xcode_templates)

TEXT_KIND = "Xcode.IDEFoundation.TextSubstitutionFileTemplateKind"


def make_template(root: Path, relative: str, kind: str, source: bytes) -> Path:
    template = root / relative
    template.mkdir(parents=True)
    (template / "TemplateInfo.plist").write_bytes(plistlib.dumps({"Kind": kind}))
    (template / "___FILEBASENAME___.swift").write_bytes(source)
    return template


def test_copies_template_to_user_templates_without_comment_slashes(
    tmp_path: Path,
) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    make_template(
        xcode,
        "Developer/Library/Xcode/Templates/File Templates/MultiPlatform/Source/Swift File.xctemplate",
        TEXT_KIND,
        b"//___FILEHEADER___\n\nimport Foundation\n",
    )

    fix_xcode_templates.install_templates(xcode, user)

    copied = user / "File Templates/MultiPlatform/Source/Swift File.xctemplate"
    assert (copied / "___FILEBASENAME___.swift").read_bytes() == (
        b"___FILEHEADER___\n\nimport Foundation\n"
    )
    assert plistlib.loads((copied / "TemplateInfo.plist").read_bytes()) == {
        "Kind": TEXT_KIND
    }


def test_skips_template_without_file_header_marker(tmp_path: Path) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    make_template(
        xcode,
        "Developer/Library/Xcode/Templates/File Templates/Other/Empty.xctemplate",
        TEXT_KIND,
        b"",
    )

    fix_xcode_templates.install_templates(xcode, user)

    assert not (user / "File Templates/Other/Empty.xctemplate").exists()


def test_skips_template_xcode_generates_from_an_editor(tmp_path: Path) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    make_template(
        xcode,
        "Developer/Library/Xcode/Templates/File Templates/SiriKit/App Enum.xctemplate",
        "Xcode.IDEIntentBuilderEditor.AppEnumerationTemplateKind",
        b"//___FILEHEADER___\n",
    )

    fix_xcode_templates.install_templates(xcode, user)

    assert not (user / "File Templates/SiriKit/App Enum.xctemplate").exists()


def test_rerun_replaces_previously_installed_copy(tmp_path: Path) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    template = make_template(
        xcode,
        "Developer/Library/Xcode/Templates/File Templates/Other/PCH File.xctemplate",
        TEXT_KIND,
        b"//___FILEHEADER___\n",
    )
    fix_xcode_templates.install_templates(xcode, user)
    (template / "___FILEBASENAME___.swift").unlink()
    (template / "___FILEBASENAME___.pch").write_bytes(
        b"// ___FILEHEADER___\n#pragma once\n"
    )

    fix_xcode_templates.install_templates(xcode, user)

    copied = user / "File Templates/Other/PCH File.xctemplate"
    assert sorted(path.name for path in copied.iterdir()) == [
        "TemplateInfo.plist",
        "___FILEBASENAME___.pch",
    ]
    assert (copied / "___FILEBASENAME___.pch").read_bytes() == (
        b"___FILEHEADER___\n#pragma once\n"
    )


def test_reads_template_info_in_openstep_plist_format(tmp_path: Path) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    template = make_template(
        xcode,
        "Developer/Library/Xcode/Templates/File Templates/Other/Old Style.xctemplate",
        TEXT_KIND,
        b"//___FILEHEADER___\n",
    )
    (template / "TemplateInfo.plist").write_text(f'{{\n\tKind = "{TEXT_KIND}";\n}}\n')

    fix_xcode_templates.install_templates(xcode, user)

    copied = user / "File Templates/Other/Old Style.xctemplate"
    assert (copied / "___FILEBASENAME___.swift").read_bytes() == b"___FILEHEADER___\n"
