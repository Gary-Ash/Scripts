#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ****************************************************************************************
#  fix-xcode-templates.py
#
# This script installs copies of Xcode's file and project templates in the user's
# template folder with the comment marker // ___FILEHEADER___ replaced by
# ___FILEHEADER___, so a block comment file header doesn't start with a stray double
# slash.  The copies' icons carry the Geedbla logo.  Xcode.app itself is never
# modified; editing its templates breaks its code signature.
#
#  Author   :  Gary Ash <gary.ash@icloud.com>
#  Created  :   1-Sep-2026  4:42pm
#  Modified :  19-Oct-2026  6:53pm
#
#  Copyright © 2026 By Gary Ash All rights reserved.
# ****************************************************************************************
import plistlib
import re
import shutil
import subprocess
from collections.abc import Iterator
from pathlib import Path
from typing import Any

XCODE_CONTENTS = Path("/Applications/Xcode.app/Contents")
USER_TEMPLATES = Path.home() / "Library/Developer/Xcode/Templates"

# other kinds are generated from Xcode's editors (SiriKit, Core Data, refactoring), not
# from the New File dialog
TEXT_SUBSTITUTION_KIND = "Xcode.IDEFoundation.TextSubstitutionFileTemplateKind"

IDENTIFIER_SUFFIX = ".geedbla"

LOGO = Path(__file__).resolve().parent.parent / "pictures/Logo.png"

# the templates are a mix of text and binaries, so they are edited as bytes
FILE_HEADER_MARKER = re.compile(rb"//\s*___FILEHEADER___")

# Swift script that draws the logo as a badge on each template's icon so the copies
# stand out from Xcode's own templates.  Its first argument is the logo, followed by
# pairs of template directory and icon source: "png" badges the template's own TemplateIcon-1016 image,
# "type:<extension>" the system icon for that file type, "symbol:<name>" an SF Symbol
# drawn on a tile, and "image:<name>:<bundle path>" an image from one of Xcode's bundles
# drawn on a tile.
BADGE_ICONS = """
import AppKit
import UniformTypeIdentifiers

func render(_ base: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    base.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    let width = size * 0.6
    let height = width * logo.size.height / logo.size.width
    logo.draw(in: NSRect(x: size - width, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func tile(_ symbol: NSImage) -> NSImage {
    NSImage(size: NSSize(width: 96, height: 96), flipped: false) { rect in
        let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), xRadius: 18, yRadius: 18)
        NSColor(white: 0.97, alpha: 1).setFill()
        tile.fill()
        NSColor(white: 0.78, alpha: 1).setStroke()
        tile.lineWidth = 1.5
        tile.stroke()
        let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
            .applying(.init(paletteColors: [.systemBlue]))
        let image = symbol.withSymbolConfiguration(config)
            ?? NSImage(size: NSSize(width: 48, height: 48), flipped: false) { frame in
                symbol.draw(in: frame)
                return true
            }
        image.draw(in: NSRect(
            x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2 + 6,
            width: image.size.width, height: image.size.height))
        return true
    }
}

let logo = NSImage(contentsOfFile: CommandLine.arguments[1])!
let arguments = Array(CommandLine.arguments.dropFirst(2))
for index in stride(from: 0, to: arguments.count, by: 2) {
    let template = URL(fileURLWithPath: arguments[index])
    let source = arguments[index + 1]
    let base: NSImage
    if source.hasPrefix("type:") {
        base = NSWorkspace.shared.icon(
            for: UTType(filenameExtension: String(source.dropFirst(5))) ?? .data)
    } else if source.hasPrefix("symbol:") {
        let name = String(source.dropFirst(7))
        // some of Xcode's symbols are private, which only this AppKit method loads
        let privateSymbol = NSSelectorFromString(
            "imageWithPrivateSystemSymbolName:accessibilityDescription:")
        base = tile(
            NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? (NSImage.self as AnyObject).perform(privateSymbol, with: name, with: nil)
                .takeUnretainedValue() as! NSImage)
    } else if source.hasPrefix("image:") {
        let parts = source.split(separator: ":", maxSplits: 2).map(String.init)
        base = tile(Bundle(path: parts[2])!.image(forResource: parts[1])!)
    } else {
        base = NSImage(contentsOf: template.appendingPathComponent("TemplateIcon-1016@2x.png"))!
    }
    let small = render(base, pixels: 48)
    let large = render(base, pixels: 96)
    for name in ["TemplateIcon", "TemplateIcon-1016"] {
        try! small.write(to: template.appendingPathComponent("\\(name).png"))
        try! large.write(to: template.appendingPathComponent("\\(name)@2x.png"))
    }
}
"""


# ****************************************************************************************
# copy every file template that uses the marker into the user's template folder
# ****************************************************************************************
def install_templates(xcode_contents: Path, user_templates: Path) -> list[Path]:
    installed = []
    badge_arguments: list[str] = []
    for template in sorted(xcode_contents.rglob("File Templates/**/*.xctemplate")):
        # plutil, unlike plistlib, reads the OpenStep format some templates still use
        kind = subprocess.run(
            ["plutil", "-extract", "Kind", "raw", template / "TemplateInfo.plist"],
            capture_output=True,
            text=True,
            check=False,
        ).stdout.strip()
        if kind != TEXT_SUBSTITUTION_KIND:
            continue
        if not any(
            path.is_file() and FILE_HEADER_MARKER.search(path.read_bytes())
            for path in template.rglob("*")
        ):
            continue
        relative = template.as_posix().split("/File Templates/", 1)[1]
        destination = user_templates / "File Templates" / relative
        shutil.rmtree(destination, ignore_errors=True)
        shutil.copytree(template, destination)
        for path in destination.rglob("*"):
            if path.is_file():
                path.write_bytes(
                    FILE_HEADER_MARKER.sub(b"___FILEHEADER___", path.read_bytes())
                )
        # an Image key takes precedence over icon files, so it gives way to the badge
        info = destination / "TemplateInfo.plist"
        file_type = subprocess.run(
            ["plutil", "-extract", "Image.FileTypeIcon", "raw", info],
            capture_output=True,
            text=True,
            check=False,
        ).stdout.strip()
        if file_type:
            subprocess.run(
                ["plutil", "-remove", "Image", info], capture_output=True, check=True
            )
            badge_arguments += [str(destination), f"type:{file_type}"]
        elif (destination / "TemplateIcon-1016@2x.png").exists():
            badge_arguments += [str(destination), "png"]
        installed.append(destination)
    badge_icons(badge_arguments)
    return installed


# ****************************************************************************************
# draw the badge on the icons named by pairs of template directory and icon source
# ****************************************************************************************
def badge_icons(badge_arguments: list[str]) -> None:
    if badge_arguments:
        subprocess.run(
            ["swift", "-", str(LOGO), *badge_arguments],
            input=BADGE_ICONS,
            text=True,
            check=True,
        )


# ****************************************************************************************
# copy every project template that leads to the marker into the user's template folder
# ****************************************************************************************
def install_project_templates(xcode_contents: Path, user_templates: Path) -> list[Path]:
    templates: dict[str, tuple[Path, dict[str, Any]]] = {}
    for template in sorted(xcode_contents.rglob("Project Templates/**/*.xctemplate")):
        info = template / "TemplateInfo.plist"
        if not info.is_file():
            continue
        # plutil converts the OpenStep format some templates still use
        xml = subprocess.run(
            ["plutil", "-convert", "xml1", "-o", "-", info],
            capture_output=True,
            check=True,
        ).stdout
        properties = plistlib.loads(xml)
        if "Identifier" in properties:
            templates[properties["Identifier"]] = (template, properties)

    # Xcode ignores a user template that reuses one of its identifiers, so a fixed
    # template gets a new identifier, and so must every template that refers to it
    references = {
        identifier: {
            string
            for string in plist_strings(properties)
            if string in templates and string != identifier
        }
        for identifier, (_template, properties) in templates.items()
    }
    needs_copy: dict[str, bool] = {}

    def leads_to_marker(identifier: str) -> bool:
        if identifier not in needs_copy:
            needs_copy[identifier] = False  # breaks reference cycles
            template = templates[identifier][0]
            needs_copy[identifier] = any(
                path.is_file() and FILE_HEADER_MARKER.search(path.read_bytes())
                for path in template.rglob("*")
            ) or any(leads_to_marker(reference) for reference in references[identifier])
        return needs_copy[identifier]

    copied = {identifier for identifier in templates if leads_to_marker(identifier)}

    # TemplateInfo.plist is rewritten here, so the marker in its definitions is fixed too
    def fix(value: Any) -> Any:
        if isinstance(value, str) and value in copied:
            return value + IDENTIFIER_SUFFIX
        if isinstance(value, str):
            return FILE_HEADER_MARKER.sub(b"___FILEHEADER___", value.encode()).decode()
        if isinstance(value, dict):
            return {key: fix(item) for key, item in value.items()}
        if isinstance(value, list):
            return [fix(item) for item in value]
        return value

    bundles = {}
    for bundle_info in xcode_contents.glob("*/*.framework/Resources/Info.plist"):
        bundle_identifier = plistlib.loads(bundle_info.read_bytes()).get(
            "CFBundleIdentifier"
        )
        bundles[bundle_identifier] = bundle_info.parent.parent

    installed = []
    badge_arguments: list[str] = []
    for identifier in sorted(copied):
        template, properties = templates[identifier]
        properties = fix(properties)
        relative = template.as_posix().split("/Project Templates/", 1)[1]
        destination = user_templates / "Project Templates" / relative
        shutil.rmtree(destination, ignore_errors=True)
        shutil.copytree(template, destination)
        for path in destination.rglob("*"):
            if path.is_file():
                path.write_bytes(
                    FILE_HEADER_MARKER.sub(b"___FILEHEADER___", path.read_bytes())
                )
        # only templates shown in the New Project dialog need the badge
        image = properties.get("Image", {})
        if properties.get("Concrete") and "SystemSymbolName" in image:
            del properties["Image"]
            badge_arguments += [str(destination), f"symbol:{image['SystemSymbolName']}"]
        elif properties.get("Concrete") and image.get("BundleIdentifier") in bundles:
            del properties["Image"]
            bundle = bundles[image["BundleIdentifier"]]
            badge_arguments += [
                str(destination),
                f"image:{image['BundleImageName']}:{bundle}",
            ]
        (destination / "TemplateInfo.plist").write_bytes(plistlib.dumps(properties))
        installed.append(destination)
    badge_icons(badge_arguments)
    return installed


def plist_strings(value: Any) -> Iterator[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from plist_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from plist_strings(item)


# ****************************************************************************************
# script main line
# ****************************************************************************************
if __name__ == "__main__":
    for installed in install_templates(XCODE_CONTENTS, USER_TEMPLATES):
        print(installed)
    for installed in install_project_templates(XCODE_CONTENTS, USER_TEMPLATES):
        print(installed)
