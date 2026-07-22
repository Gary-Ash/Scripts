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
# Modified :  22-Jul-2026  3:46pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

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
        mv "${tmp_file}" "${file}"
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
        codesign --force --sign - --timestamp=none "${item}"
    done

    find "${app}/Contents" -type f -perm -111 -print0 |
    while IFS= read -r -d '' exe; do
        if file "${exe}" | grep -q "Mach-O"; then
            codesign --force --sign - --timestamp=none "${exe}"
        fi
    done

    codesign \
        --force \
        --deep \
        --sign - \
        --timestamp=none \
        "${app}"

    codesign --verify --deep --strict --verbose=2 "${app}"
fi

find "${app}" -type f -print0 |
while IFS= read -r -d '' file; do
    if file "${file}" | grep -q "Mach-O"; then
        archs=$(lipo -archs "${file}" 2>/dev/null || true)
        [[ -n "${archs}" ]] && printf '%s\n' "${archs} : ${file}"
    fi
done
