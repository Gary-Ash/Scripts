#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# *****************************************************************************************
# test_fix_xcode_templates.py
#
# tests for fix-xcode-templates.py
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  19-Oct-2026  3:47pm
# Modified :  19-Oct-2026  4:19pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
# *****************************************************************************************
import importlib.util
import plistlib
import struct
import zlib
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "fix-xcode-templates.py"
_spec = importlib.util.spec_from_file_location("fix_xcode_templates", SCRIPT)
assert _spec is not None and _spec.loader is not None
fix_xcode_templates = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fix_xcode_templates)

TEXT_KIND = "Xcode.IDEFoundation.TextSubstitutionFileTemplateKind"


def png_size(path: Path) -> tuple[int, int]:
    header = path.read_bytes()[:24]
    assert header[:8] == b"\x89PNG\r\n\x1a\n"
    return int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")


def solid_png(pixels: int) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    rows = b"".join(b"\x00" + b"\x40\x80\xc0\xff" * pixels for _ in range(pixels))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", pixels, pixels, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


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


def test_replaces_file_type_icon_with_badged_template_icon(tmp_path: Path) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    template = make_template(
        xcode,
        "Developer/Library/Xcode/Templates/File Templates/Other/Swift File.xctemplate",
        TEXT_KIND,
        b"//___FILEHEADER___\n",
    )
    (template / "TemplateInfo.plist").write_bytes(
        plistlib.dumps({"Kind": TEXT_KIND, "Image": {"FileTypeIcon": "swift"}})
    )

    fix_xcode_templates.install_templates(xcode, user)

    copied = user / "File Templates/Other/Swift File.xctemplate"
    assert "Image" not in plistlib.loads((copied / "TemplateInfo.plist").read_bytes())
    for name, pixels in [
        ("TemplateIcon-1016.png", 48),
        ("TemplateIcon-1016@2x.png", 96),
    ]:
        assert png_size(copied / name) == (pixels, pixels)


def test_badges_template_icon_shipped_with_template(tmp_path: Path) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    template = make_template(
        xcode,
        "Developer/Library/Xcode/Templates/File Templates/macOS/Cocoa Class.xctemplate",
        TEXT_KIND,
        b"//___FILEHEADER___\n",
    )
    stock = solid_png(96)
    (template / "TemplateIcon-1016@2x.png").write_bytes(stock)

    fix_xcode_templates.install_templates(xcode, user)

    copied = user / "File Templates/macOS/Cocoa Class.xctemplate"
    assert (copied / "TemplateIcon-1016@2x.png").read_bytes() != stock
    assert png_size(copied / "TemplateIcon-1016@2x.png") == (96, 96)
    assert png_size(copied / "TemplateIcon-1016.png") == (48, 48)


PROJECT_TEMPLATES = "Developer/Library/Xcode/Templates/Project Templates"


def make_project_template(
    root: Path, relative: str, info: dict[str, object], files: dict[str, bytes]
) -> Path:
    template = root / PROJECT_TEMPLATES / relative
    template.mkdir(parents=True)
    (template / "TemplateInfo.plist").write_bytes(plistlib.dumps(info))
    for name, source in files.items():
        (template / name).write_bytes(source)
    return template


def installed_info(user: Path, relative: str) -> dict[str, object]:
    info = user / "Project Templates" / relative / "TemplateInfo.plist"
    return dict(plistlib.loads(info.read_bytes()))


def test_copies_project_template_under_renamed_identifier(tmp_path: Path) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    make_project_template(
        xcode,
        "Base/Base_DefinitionsLanguage.xctemplate",
        {"Identifier": "com.apple.dt.unit.base_DefinitionsLanguage"},
        {"ContentView.swift": b"//___FILEHEADER___\n\nimport SwiftUI\n"},
    )

    fix_xcode_templates.install_project_templates(xcode, user)

    copied = user / "Project Templates/Base/Base_DefinitionsLanguage.xctemplate"
    assert (
        copied / "ContentView.swift"
    ).read_bytes() == b"___FILEHEADER___\n\nimport SwiftUI\n"
    assert installed_info(user, "Base/Base_DefinitionsLanguage.xctemplate") == {
        "Identifier": "com.apple.dt.unit.base_DefinitionsLanguage.geedbla"
    }


def test_renames_chain_of_templates_that_lead_to_marker(tmp_path: Path) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    make_project_template(
        xcode,
        "Base/Language.xctemplate",
        {"Identifier": "base.language"},
        {"A.swift": b"//___FILEHEADER___\n"},
    )
    make_project_template(
        xcode, "Base/Storage.xctemplate", {"Identifier": "base.storage"}, {}
    )
    make_project_template(
        xcode,
        "Base/App Base.xctemplate",
        {"Identifier": "base.app", "Ancestors": ["base.language", "base.storage"]},
        {},
    )
    make_project_template(
        xcode,
        "iOS/App.xctemplate",
        {
            "Identifier": "ios.app",
            "Concrete": True,
            "Ancestors": ["base.app"],
            "Options": [
                {
                    "Units": {
                        "XCTest": [{"Components": [{"Identifier": "base.language"}]}]
                    }
                }
            ],
        },
        {},
    )

    fix_xcode_templates.install_project_templates(xcode, user)

    assert installed_info(user, "iOS/App.xctemplate") == {
        "Identifier": "ios.app.geedbla",
        "Concrete": True,
        "Ancestors": ["base.app.geedbla"],
        "Options": [
            {
                "Units": {
                    "XCTest": [
                        {"Components": [{"Identifier": "base.language.geedbla"}]}
                    ]
                }
            }
        ],
    }
    assert installed_info(user, "Base/App Base.xctemplate")["Ancestors"] == [
        "base.language.geedbla",
        "base.storage",
    ]
    assert not (user / "Project Templates/Base/Storage.xctemplate").exists()


def test_reads_openstep_project_template_and_skips_folder_without_info(
    tmp_path: Path,
) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    template = make_project_template(
        xcode, "Base/Old Style.xctemplate", {}, {"A.m": b"//___FILEHEADER___\n"}
    )
    (template / "TemplateInfo.plist").write_text('{\n\tIdentifier = "base.old";\n}\n')
    (xcode / PROJECT_TEMPLATES / "macOS/Other/Common.xctemplate/Common").mkdir(
        parents=True
    )

    fix_xcode_templates.install_project_templates(xcode, user)

    assert installed_info(user, "Base/Old Style.xctemplate") == {
        "Identifier": "base.old.geedbla"
    }


def test_badges_symbol_icon_of_project_template_shown_in_dialog(tmp_path: Path) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    symbol = {"SystemSymbolName": "puzzlepiece.extension"}
    make_project_template(
        xcode,
        "Base/Base.xctemplate",
        {"Identifier": "base", "Image": symbol},
        {"A.swift": b"//___FILEHEADER___\n"},
    )
    make_project_template(
        xcode,
        "iOS/Extension.xctemplate",
        {
            "Identifier": "ios.extension",
            "Concrete": True,
            "Ancestors": ["base"],
            "Image": symbol,
        },
        {},
    )

    fix_xcode_templates.install_project_templates(xcode, user)

    concrete = user / "Project Templates/iOS/Extension.xctemplate"
    assert "Image" not in installed_info(user, "iOS/Extension.xctemplate")
    assert png_size(concrete / "TemplateIcon-1016@2x.png") == (96, 96)
    assert png_size(concrete / "TemplateIcon-1016.png") == (48, 48)
    assert installed_info(user, "Base/Base.xctemplate")["Image"] == symbol
    assert not (
        user / "Project Templates/Base/Base.xctemplate/TemplateIcon-1016.png"
    ).exists()


def test_badges_private_symbol_icon(tmp_path: Path) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    make_project_template(
        xcode,
        "macOS/Game.xctemplate",
        {
            "Identifier": "macos.game",
            "Concrete": True,
            "Image": {"SystemSymbolName": "metal"},
        },
        {"Renderer.swift": b"//___FILEHEADER___\n"},
    )

    fix_xcode_templates.install_project_templates(xcode, user)

    copied = user / "Project Templates/macOS/Game.xctemplate"
    assert png_size(copied / "TemplateIcon-1016@2x.png") == (96, 96)


def test_badges_icon_named_from_xcode_bundle(tmp_path: Path) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    resources = xcode / "Frameworks/Fake.framework/Resources"
    resources.mkdir(parents=True)
    (resources / "Info.plist").write_bytes(
        plistlib.dumps({"CFBundleIdentifier": "com.example.fake"})
    )
    (resources / "tile.png").write_bytes(solid_png(32))
    make_project_template(
        xcode,
        "iOS/Framework.xctemplate",
        {
            "Identifier": "ios.framework",
            "Concrete": True,
            "Image": {
                "BundleIdentifier": "com.example.fake",
                "BundleImageName": "tile",
            },
        },
        {"Framework.h": b"//___FILEHEADER___\n"},
    )

    fix_xcode_templates.install_project_templates(xcode, user)

    copied = user / "Project Templates/iOS/Framework.xctemplate"
    assert "Image" not in installed_info(user, "iOS/Framework.xctemplate")
    assert png_size(copied / "TemplateIcon-1016@2x.png") == (96, 96)


def test_fixes_marker_inside_template_info(tmp_path: Path) -> None:
    xcode = tmp_path / "Xcode.app/Contents"
    user = tmp_path / "UserTemplates"
    make_project_template(
        xcode,
        "Base/Base_DefinitionsLanguage.xctemplate",
        {
            "Identifier": "base.language",
            "Definitions": {"*:comments": "//___FILEHEADER___\n"},
        },
        {},
    )

    fix_xcode_templates.install_project_templates(xcode, user)

    assert installed_info(user, "Base/Base_DefinitionsLanguage.xctemplate")[
        "Definitions"
    ] == {"*:comments": "___FILEHEADER___\n"}
