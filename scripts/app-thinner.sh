#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# app-thinner.sh
#
# Strip the intel binary from a macOS app bundles, and resign with an adhoc signature if
# if requested.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  21-Jul-2026  7:47pm
# Modified :  23-Jul-2026  7:04pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# source in library functions
#*****************************************************************************************
source "/opt/geedbla/lib/shell/lib/get_sudo_password.sh"

export SUDO_PASSWORD
SUDO_SHELL_PID=""

resign=false
app=""
tmp_file=""

usage() {
    cat <<EOF
Usage:
    $(basename "$0") [--resign] /path/to/MyApp.app

Options:
    --resign    Re-sign the app with an ad hoc signature after stripping.
    -h, --help  Show this help.

Examples:
    $(basename "$0") MyApp.app
    $(basename "$0") --resign MyApp.app
EOF
}

cleanup() {
    [[ -n "$SUDO_SHELL_PID" ]] && kill "$SUDO_SHELL_PID" 2>/dev/null
    wait 2>/dev/null
    unset SUDO_SHELL_PID
    unset SUDO_PASSWORD

    rm -f "${tmp_file:-}"
}
trap cleanup EXIT

strip_intel() {
    local file="$1"
    local archs

    if ! file "${file}" | grep -q "Mach-O"; then
        return
    fi

    archs=$(lipo -archs "${file}" 2>/dev/null || true)
    [[ -z "${archs}" ]] && return

    if [[ "${archs}" == *x86_64* && "${archs}" == *arm64* ]]; then
        tmp_file=$(mktemp)
        lipo "${file}" -remove x86_64 -output "${tmp_file}"
        chmod "$(stat -f '%A' "${file}")" "${tmp_file}"
        sudo mv "${tmp_file}" "${file}"
        tmp_file=""
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --resign)
            resign=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            app="$1"
            shift
            ;;
    esac
done

if [[ -z "${app}" ]]; then
    usage
    exit 1
fi

if [[ ! -d "${app}" ]]; then
    printf '%s\n' "App bundle not found: ${app}"
    exit 1
fi

#*****************************************************************************************
# setup the sudo until the script is done
#*****************************************************************************************
SUDO_PASSWORD="$(get_sudo_password)"
echo "$SUDO_PASSWORD" | sudo --validate --stdin &>/dev/null
while true; do
    sudo --non-interactive -E true
    sleep 20
done &
export SUDO_SHELL_PID=$!

while IFS= read -r -d '' file; do
    strip_intel "${file}"
done < <(find "${app}" -type f -print0)

if ${resign}; then
    printf '\n%s\n' "Ad hoc signing nested code..."

    find "${app}/Contents" \
        \( \
            -name "*.framework" -o \
            -name "*.dylib" -o \
            -name "*.so" -o \
            -name "*.appex" -o \
            -name "*.xpc" -o \
            -name "*.bundle" -o \
            -name "*.app" \
        \) \
        -print0 |
    while IFS= read -r -d '' item; do
        sudo codesign --force --sign - --timestamp=none "${item}"
    done

    find "${app}/Contents" -type f -perm -111 -print0 |
    while IFS= read -r -d '' exe; do
        if file "${exe}" | grep -q "Mach-O"; then
            sudo codesign --force --sign - --timestamp=none "${exe}"
        fi
    done

    sudo codesign \
        --force \
        --deep \
        --sign - \
        --timestamp=none \
        "${app}"

    sudo codesign --verify --deep --strict --verbose=2 "${app}"
fi

find "${app}" -type f -print0 |
while IFS= read -r -d '' file; do
    if file "${file}" | grep -q "Mach-O"; then
        archs=$(lipo -archs "${file}" 2>/dev/null || true)
    fi
done
