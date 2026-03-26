#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# export-github-secrets.sh
#
# Extract signing certificate and App Store Connect API key from this
# development machine and set them directly as GitHub Actions secrets
# using the gh CLI. Provisioning is handled automatically by xcodebuild
# via -allowProvisioningUpdates and the ASC API key.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   8-Mar-2026  4:30pm
# Modified :  26-Mar-2026 12:00pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$(find "$PROJECT_DIR" -maxdepth 1 -name '*.xcodeproj' -print -quit)" .xcodeproj)"
OUTPUT_DIR="${TMPDIR:-/tmp}/${PROJECT_NAME}-secrets"
ERRORS=0

mkdir -p "$OUTPUT_DIR"

#*****************************************************************************************
# Verify prerequisites
#*****************************************************************************************
check_prerequisites() {
	if ! command -v gh &>/dev/null; then
		echo "ERROR: gh CLI is not installed. Install it with: brew install gh" >&2
		exit 1
	fi

	if ! gh auth status &>/dev/null; then
		echo "ERROR: gh CLI is not authenticated. Run: gh auth login" >&2
		exit 1
	fi

	REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null) || true
	if [[ -z $REPO ]]; then
		echo "ERROR: Not in a GitHub repository or remote not configured." >&2
		exit 1
	fi

	echo "Repository: ${REPO}"
}

#*****************************************************************************************
# Helper to set a secret and report status
#*****************************************************************************************
set_secret() {
	local name="$1"
	local value="$2"

	if echo -n "$value" | gh secret set "$name" 2>/dev/null; then
		echo "  ✓ ${name}"
	else
		echo "  ✗ ${name} — failed to set" >&2
		ERRORS=$((ERRORS + 1))
	fi
}

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

	echo "Project:   $(basename "$PROJECT_FILE")"
	echo "Bundle ID: ${BUNDLE_ID}"
	echo "Team ID:   ${TEAM_ID}"
}

#*****************************************************************************************
# Find and upload the Apple Distribution signing certificate
#*****************************************************************************************
upload_certificate() {
	echo ""
	echo "--- Signing Certificate ---"

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
		echo "ERROR: No signing identity found." >&2
		security find-identity -v -p codesigning >&2
		ERRORS=$((ERRORS + 1))
		return
	fi

	echo "Found identity: ${IDENTITY}"

	P12_PATH="${OUTPUT_DIR}/certificate.p12"

	security export \
		-k login.keychain-db \
		-t identities \
		-f pkcs12 \
		-o "$P12_PATH" \
		-P "" 2>/dev/null || true

	if [[ ! -f $P12_PATH || ! -s $P12_PATH ]]; then
		echo ""
		echo "Keychain access required — click 'Allow' or 'Always Allow' in the dialog."
		read -rsp "Press Enter after granting access, or Ctrl-C to abort..."
		echo ""

		security export \
			-k login.keychain-db \
			-t identities \
			-f pkcs12 \
			-o "$P12_PATH"
	fi

	CERT_B64=$(base64 -i "$P12_PATH")
	set_secret "CERTIFICATE_P12" "$CERT_B64"
	set_secret "CERTIFICATE_PASSWORD" ""
}

#*****************************************************************************************
# Locate and upload the App Store Connect API key
#*****************************************************************************************
upload_api_key() {
	echo ""
	echo "--- App Store Connect API Key ---"

	P8_FOUND=""
	for key_dir in \
		"$HOME/Documents/GeeDblA/Resources/Development/Apple/CertificatesAndKeys" \
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

	if [[ -z $P8_FOUND ]]; then
		echo "ERROR: No AuthKey_*.p8 file found." >&2
		echo "Searched: ~/private_keys/, ~/.appstoreconnect/private_keys/, ~/.private_keys/, ~/Downloads/" >&2
		echo "Download from: App Store Connect → Users and Access → Integrations → App Store Connect API" >&2
		ERRORS=$((ERRORS + 1))
		return
	fi

	KEY_ID=$(basename "$P8_FOUND" | sed 's/AuthKey_//;s/\.p8//')
	echo "Found API key: ${P8_FOUND} (Key ID: ${KEY_ID})"

	KEY_B64=$(base64 -i "$P8_FOUND")
	set_secret "ASC_API_KEY" "$KEY_B64"
	set_secret "ASC_API_KEY_ID" "$KEY_ID"
}

#*****************************************************************************************
# Prompt for the Issuer ID (not stored locally)
#*****************************************************************************************
upload_issuer_id() {
	echo ""
	echo "--- App Store Connect Issuer ID ---"
	echo "Find this at: App Store Connect → Users and Access → Integrations → App Store Connect API"
	echo "It is displayed at the top of the page as 'Issuer ID'."
	echo ""

	read -rp "Enter your ASC_API_ISSUER_ID (or press Enter to skip): " ISSUER_ID

	if [[ -n $ISSUER_ID ]]; then
		set_secret "ASC_API_ISSUER_ID" "$ISSUER_ID"
	else
		echo "  ⊘ ASC_API_ISSUER_ID — skipped (set manually with: gh secret set ASC_API_ISSUER_ID)"
	fi
}

#*****************************************************************************************
# Generate and upload a random keychain password
#*****************************************************************************************
upload_keychain_password() {
	echo ""
	echo "--- Keychain Password ---"

	RANDOM_PW=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
	set_secret "KEYCHAIN_PASSWORD" "$RANDOM_PW"
}

#*****************************************************************************************
# Main
#*****************************************************************************************
echo ""
echo "========================================================"
echo "  GitHub Secrets Setup for ${PROJECT_NAME}"
echo "========================================================"
echo ""

check_prerequisites
echo ""
resolve_project_settings

upload_certificate
upload_api_key
upload_issuer_id
upload_keychain_password

echo ""
echo "========================================================"

rm -f "${OUTPUT_DIR}/certificate.p12"
rmdir "$OUTPUT_DIR" 2>/dev/null || true

if [[ $ERRORS -gt 0 ]]; then
	echo ""
	echo "Completed with ${ERRORS} error(s). Fix the issues above and re-run."
	echo ""
	exit 1
else
	echo ""
	echo "All secrets configured successfully."
	echo ""
fi
