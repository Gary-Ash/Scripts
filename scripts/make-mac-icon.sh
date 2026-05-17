#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# make-mac-icon.sh
#
# This script will make a macOS icon given an image file
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  16-May-2026  9:57pm
# Modified :  16-May-2026  9:58pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

if [ -z "$1" ]; then
    echo "Usage: $0 <path_to_image>"
    exit 1
fi

sourceImage="$1"
iconsetDir="AppIcon.iconset"
outputICNS="AppIcon.icns"

# Ensure ImageMagick is installed
if ! command -v magick &> /dev/null && ! command -v convert &> /dev/null; then
    echo "Error: ImageMagick is not installed or not in your PATH."
    exit 1
fi

# Determine the correct ImageMagick command (v7 uses 'magick', v6 uses 'convert')
IM_CMD="magick"
if ! command -v magick &> /dev/null; then
    IM_CMD="convert"
fi

echo "Creating temporary iconset directory..."
mkdir -p "$iconsetDir"

# Define the required dimensions (Size and Scale)
# Format: "Size:RetinaScale"
sizes=(
    "16:1" "16:2"
    "32:1" "32:2"
    "128:1" "128:2"
    "256:1" "256:2"
    "512:1" "512:2"
)

echo "Resizing images using ImageMagick..."
for item in "${sizes[@]}"; do
    # Split the size and scale
    size="${item%%:*}"
    scale="${item##*:}"

    # Calculate target resolution
    target_res=$((size * scale))

    # Determine output filename based on Apple's spec
    if [ "$scale" -eq 1 ]; then
        filename="icon_${size}x${size}.png"
    else
        filename="icon_${size}x${size}@2x.png"
    fi

    # Resize the image. Using -background none and -gravity center
    # to preserve aspect ratio if the source isn't perfectly square.
    $IM_CMD "$sourceImage" -resize "${target_res}x${target_res}" \
        -background none -gravity center -extent "${target_res}x${target_res}" \
        "$iconsetDir/$filename"
done

echo "Compiling .iconset into $outputICNS..."
# iconutil is a native macOS tool to bundle iconsets
if command -v iconutil &> /dev/null; then
    iconutil -c icns "$iconsetDir"
    echo "Success! Created $outputICNS"
else
    echo "Warning: 'iconutil' not found. (Are you on Linux/Windows?)"
    echo "The standard AppIcon.iconset folder was created successfully,"
    echo "but it could not be compiled into a final .icns file automatically."
fi

# Clean up the temporary iconset folder
echo "Cleaning up temporary files..."
rm -rf "$iconsetDir"