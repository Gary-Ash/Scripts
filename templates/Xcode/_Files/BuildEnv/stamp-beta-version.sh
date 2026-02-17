#!/usr/bin/env zsh
#*****************************************************************************************
# stamp-beta-version.sh
#
# This script is meant to be run during the app build process, it make copy of the app's
# icon resources and then modifies the app icon to include a Beta stamp and version numbers
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  20-Feb-2026  5:21pm
# Modified :
#
# Copyright © 2026 By CompanyName All rights reserved.
#*****************************************************************************************

if [[ ${CONFIGURATION} != "TestFlight" ]]; then
	exit 0
fi

buildInformation="text 0,0 \'v${MARKETING_VERSION} Build ${CURRENT_PROJECT_VERSION}\'"

#*****************************************************************************************
#  make sure the PATH includes Home Brew so that we can access the ImageMagick tools
#*****************************************************************************************
if [ -f "/opt/homebrew/bin/brew" ]; then
	export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
elif [ -f "/usr/local/bin/brew" ]; then
	export PATH="/usr/local/bin:$PATH"
fi

if ! command -v magick &>/dev/null; then
	brew install imagemagick
fi

#*****************************************************************************************
#  find the app icon graphics and make backups
#*****************************************************************************************
appIconDir=$(find "${SRCROOT}/" -type d -name "AppIcon.appiconset" -print)
tvOSappIconDir=$(find "${SRCROOT}/" -type d -name "Brand Assets.brandassets" -print)

if [[ -n $appIconDir ]]; then
	mkdir -p "${TMPDIR}/${PROJECT_NAME}"
	cp -rf "${appIconDir}" "${TMPDIR}/${PROJECT_NAME}/AppIcon.appiconset"
fi

if [[ -n ${tvOSappIconDir} ]]; then
	mkdir -p "${TMPDIR}/${PROJECT_NAME}"
	cp -rf "${tvOSappIconDir}" "${TMPDIR}/${PROJECT_NAME}/Brand Assets.brandassets"
fi

#*****************************************************************************************
#  add the Beta flag, version, and build information to the AppStore icon
#*****************************************************************************************
find "$appIconDir" -name "*.png" -type f -print |
	while IFS= read -r file; do
		dimWidth=$(magick identify -format "%w" "${file}")
		dimHeight=$(magick identify -format "%h" "${file}")

		betaPoint=$((72 * dimHeight / 1024))
		buildPoint=$((35 * dimHeight / 1024))
		betaX=$((80 * dimWidth / 1024))
		betaY=$((200 * dimHeight / 1024))

		echo "${file} rotate -25 text ${betaX},${betaY} ' Beta '"

		magick "${file}" \
			-font Courier-New-Bold -fill white -pointsize ${betaPoint} -undercolor red \
			-draw "rotate -25 text ${betaX},${betaY} ' Beta '" \
			-font Courier-New-Bold -fill white -pointsize ${buildPoint} -undercolor lightgrey \
			-fill white -gravity south -draw "${buildInformation}" "${file}"
	done

#*****************************************************************************************
#  if there are tvOS assets add those to the list icons
#*****************************************************************************************
if [[ -n ${tvOSappIconDir} ]]; then
	find "$tvOSappIconDir/App Icon - App Store.imagestack/Front.imagestacklayer" -name "*.png" -type f -print |
		while IFS= read -r file; do
			icons+=("${file}")
		done

	find "$tvOSappIconDir/App Icon.imagestack/Front.imagestacklayer" -name "*.png" -type f -print |
		while IFS= read -r file; do
			icons+=("${file}")
		done

	find "$tvOSappIconDir/Top Shelf Image Wide.imageset" -name "*.png" -type f -print |
		while IFS= read -r file; do
			icons+=("${file}")
		done

	find "$tvOSappIconDir/Top Shelf Image.imageset" -name "*.png" -type f -print |
		while IFS= read -r file; do
			icons+=("${file}")
		done

fi

#*****************************************************************************************
#  finish prepping the last of icons
#*****************************************************************************************
for icon in "${icons[@]}"; do
	dimWidth=$(magick identify -format "%w" "${icon}")
	dimHeight=$(magick identify -format "%h" "${icon}")

	betaPoint=$((72 * dimHeight / 1024))
	buildPoint=$((35 * dimHeight / 1024))
	betaX=$((80 * dimWidth / 1024))
	betaY=$((200 * dimHeight / 1024))

	echo "${icon} rotate -25 text ${betaX},${betaY} ' Beta '"

	magick "${icon}" \
		-font Courier-New-Bold -fill white -pointsize ${betaPoint} -undercolor red \
		-draw "rotate -25 text ${betaX},${betaY} ' Beta '" \
		-font Courier-New-Bold -fill white -pointsize ${buildPoint} -undercolor lightgrey \
		-fill white -gravity south -draw "${buildInformation}" "${icon}"
done
