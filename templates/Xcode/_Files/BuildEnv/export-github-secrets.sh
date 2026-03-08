#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# export-github-secrets.sh
#
# Extract signing certificate, provisioning profile, and App Store Connect API key
# from this development machine and output the base64-encoded values needed to
# configure GitHub Actions secrets for App Store submission.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Mar-2026  4:30pm
# Modified :   8-Mar-2026  5:15pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$(find "$PROJECT_DIR" -maxdepth 1 -name '*.xcodeproj' -print -quit)" .xcodeproj)"
OUTPUT_DIR="${TMPDIR:-/tmp}/${PROJECT_NAME}-secrets"

mkdir -p "$OUTPUT_DIR"

#*****************************************************************************************
# Resolve project settings from the Xcode project
#*****************************************************************************************
resolve_project_settings() {
	PROJECT_FILE=$(find "$PROJECT_DIR" -maxdepth 1 -name "*.xcodeproj" -print -quit)
	if [[ -z $PROJECT_FILE ]]; then
		echo "ERROR: No .xcodeproj found in ${PROJECT_DIR}" >&2
		exit 1
	fi

	PBXPROJ="${PROJECT_FILE}/project.pbxproj"

	BUNDLE_ID=$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER' "$PBXPROJ" |
		sed 's/.*= *"\{0,1\}\([^";]*\)"\{0,1\} *;.*/\1/')

	TEAM_ID=$(grep -m1 'DEVELOPMENT_TEAM' "$PBXPROJ" |
		sed 's/.*= *"\{0,1\}\([^";]*\)"\{0,1\} *;.*/\1/')

	if [[ -z $BUNDLE_ID ]]; then
		echo "ERROR: Could not extract PRODUCT_BUNDLE_IDENTIFIER from project" >&2
		exit 1
	fi

	if [[ -z $TEAM_ID ]]; then
		echo "ERROR: Could not extract DEVELOPMENT_TEAM from project" >&2
		exit 1
	fi

	echo "Project: $(basename "$PROJECT_FILE")"
	echo "Bundle ID: ${BUNDLE_ID}"
	echo "Team ID: ${TEAM_ID}"
}

#*****************************************************************************************
# Find and export the Apple Distribution signing certificate
#*****************************************************************************************
export_certificate() {
	echo "=== Signing Certificate ==="
	echo ""

	IDENTITY=$(security find-identity -v -p codesigning |
		grep "Apple Distribution" |
		head -1 |
		sed 's/.*"\(.*\)".*/\1/')

	if [[ -z $IDENTITY ]]; then
		IDENTITY=$(security find-identity -v -p codesigning |
			grep "Apple Development" |
			head -1 |
			sed 's/.*"\(.*\)".*/\1/')
	fi

	if [[ -z $IDENTITY ]]; then
		echo "ERROR: No signing identity found."
		echo "Available identities:"
		security find-identity -v -p codesigning
		return 1
	fi

	echo "Found identity: ${IDENTITY}"
	echo ""

	P12_PATH="${OUTPUT_DIR}/certificate.p12"
	echo "Enter a password to protect the exported .p12 file."
	echo "You will use this same password as the CERTIFICATE_PASSWORD secret."
	echo ""

	security export \
		-k login.keychain-db \
		-t identities \
		-f pkcs12 \
		-o "$P12_PATH" \
		-P "" 2>/dev/null || true

	if [[ ! -f $P12_PATH || ! -s $P12_PATH ]]; then
		echo ""
		echo "Automatic export requires Keychain access approval."
		echo "If prompted, click 'Allow' or 'Always Allow' in the dialog."
		echo ""
		read -rsp "Press Enter after granting access, or Ctrl-C to abort..."
		echo ""

		security export \
			-k login.keychain-db \
			-t identities \
			-f pkcs12 \
			-o "$P12_PATH"
	fi

	echo ""
	echo "CERTIFICATE_P12:"
	echo "----------------"
	base64 -i "$P12_PATH"
	echo ""
	echo ""
	echo "CERTIFICATE_PASSWORD:"
	echo "---------------------"
	echo "(the password you entered in the export dialog — leave empty if none)"
	echo ""
}

#*****************************************************************************************
# Find the App Store provisioning profile for the bundle ID
#*****************************************************************************************
export_provisioning_profile() {
	echo "=== Provisioning Profile ==="
	echo ""

	PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"

	if [[ ! -d $PROFILE_DIR ]]; then
		echo "ERROR: No provisioning profiles directory found."
		echo "Open Xcode and download profiles from Preferences → Accounts first."
		return 1
	fi

	FOUND_PROFILE=""
	for profile in "$PROFILE_DIR"/*.mobileprovision; do
		[[ -f $profile ]] || continue

		DECODED=$(security cms -D -i "$profile" 2>/dev/null) || continue

		PROF_BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" \
			/dev/stdin <<<"$DECODED" 2>/dev/null) || continue

		PROF_TYPE=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:get-task-allow" \
			/dev/stdin <<<"$DECODED" 2>/dev/null) || PROF_TYPE="false"

		PROVISIONS_DEVICES=$(/usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" \
			/dev/stdin <<<"$DECODED" 2>/dev/null) || PROVISIONS_DEVICES=""

		if [[ $PROF_BUNDLE == *"${BUNDLE_ID}" && $PROF_TYPE == "false" ]]; then
			PROF_NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" \
				/dev/stdin <<<"$DECODED" 2>/dev/null)
			PROF_UUID=$(/usr/libexec/PlistBuddy -c "Print :UUID" \
				/dev/stdin <<<"$DECODED" 2>/dev/null)
			PROF_EXPIRY=$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" \
				/dev/stdin <<<"$DECODED" 2>/dev/null)

			if [[ -z $PROVISIONS_DEVICES ]]; then
				echo "Found App Store profile: ${PROF_NAME}"
				echo "  UUID: ${PROF_UUID}"
				echo "  Expires: ${PROF_EXPIRY}"
				FOUND_PROFILE="$profile"
				break
			fi
		fi
	done

	if [[ -z $FOUND_PROFILE ]]; then
		echo "No App Store distribution profile found for ${BUNDLE_ID}."
		echo ""
		echo "Available profiles:"
		for profile in "$PROFILE_DIR"/*.mobileprovision; do
			[[ -f $profile ]] || continue
			DECODED=$(security cms -D -i "$profile" 2>/dev/null) || continue
			NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" /dev/stdin <<<"$DECODED" 2>/dev/null)
			BNDL=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" \
				/dev/stdin <<<"$DECODED" 2>/dev/null)
			echo "  - ${NAME} (${BNDL})"
		done
		echo ""
		echo "You may need to create one in the Apple Developer portal or"
		echo "download it via Xcode → Settings → Accounts → Manage Certificates."
		return 1
	fi

	echo ""
	echo "PROVISIONING_PROFILE:"
	echo "---------------------"
	base64 -i "$FOUND_PROFILE"
	echo ""
}

#*****************************************************************************************
# Locate an App Store Connect API key (.p8)
#*****************************************************************************************
export_api_key() {
	echo "=== App Store Connect API Key ==="
	echo ""

	P8_FOUND=""
	for key_dir in \
		"$HOME/private_keys" \
		"$HOME/.appstoreconnect/private_keys" \
		"$HOME/.private_keys" \
		"$HOME/Downloads"; do

		if [[ -d $key_dir ]]; then
			while IFS= read -r -d '' p8file; do
				P8_FOUND="$p8file"
				break
			done < <(find "$key_dir" -name "AuthKey_*.p8" -print0 2>/dev/null)
		fi
		[[ -n $P8_FOUND ]] && break
	done

	if [[ -n $P8_FOUND ]]; then
		KEY_ID=$(basename "$P8_FOUND" | sed 's/AuthKey_//;s/\.p8//')
		echo "Found API key: ${P8_FOUND}"
		echo "Extracted Key ID: ${KEY_ID}"
		echo ""
		echo "ASC_API_KEY_ID:"
		echo "---------------"
		echo "$KEY_ID"
		echo ""
		echo "ASC_API_KEY:"
		echo "------------"
		base64 -i "$P8_FOUND"
		echo ""
	else
		echo "No AuthKey_*.p8 file found in common locations."
		echo ""
		echo "Searched:"
		echo "  ~/private_keys/"
		echo "  ~/.appstoreconnect/private_keys/"
		echo "  ~/.private_keys/"
		echo "  ~/Downloads/"
		echo ""
		echo "Download your API key from:"
		echo "  App Store Connect → Users and Access → Integrations → App Store Connect API"
		echo ""
		echo "Save it as AuthKey_<KeyID>.p8 in ~/private_keys/ and re-run this script."
		return 1
	fi

	echo ""
	echo "ASC_API_ISSUER_ID:"
	echo "------------------"
	echo "Find this value at:"
	echo "  App Store Connect → Users and Access → Integrations → App Store Connect API"
	echo "  It is displayed at the top of the page as 'Issuer ID'."
	echo ""
}

#*****************************************************************************************
# Generate a random keychain password
#*****************************************************************************************
export_keychain_password() {
	echo "=== Keychain Password ==="
	echo ""
	RANDOM_PW=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
	echo "KEYCHAIN_PASSWORD:"
	echo "------------------"
	echo "$RANDOM_PW"
	echo ""
	echo "(This is a randomly generated password for the temporary CI keychain.)"
	echo ""
}

#*****************************************************************************************
# Main
#*****************************************************************************************
echo ""
echo "========================================================"
echo "  GitHub Secrets Exporter for ${PROJECT_NAME}"
echo "========================================================"
echo ""
echo "This script extracts the values you need for these"
echo "GitHub Actions secrets:"
echo ""
echo "  CERTIFICATE_P12"
echo "  CERTIFICATE_PASSWORD"
echo "  KEYCHAIN_PASSWORD"
echo "  PROVISIONING_PROFILE"
echo "  ASC_API_KEY"
echo "  ASC_API_KEY_ID"
echo "  ASC_API_ISSUER_ID"
echo ""
echo "========================================================"
echo ""

resolve_project_settings
echo ""
echo "========================================================"
echo ""

export_certificate
echo ""
echo "========================================================"
echo ""

export_provisioning_profile
echo ""
echo "========================================================"
echo ""

export_api_key
echo ""
echo "========================================================"
echo ""

export_keychain_password
echo ""
echo "========================================================"
echo ""

echo "Next steps:"
echo "  1. Copy each value above into the corresponding GitHub secret"
echo "     at: Settings → Secrets and variables → Actions → New repository secret"
echo "  2. The ASC_API_ISSUER_ID must be copied manually from App Store Connect."
echo "  3. Delete the temporary files when done:"
echo "     rm -rf ${OUTPUT_DIR}"
echo ""

rm -f "${OUTPUT_DIR}/certificate.p12"
