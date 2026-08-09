#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# strip-app.sh
#
# Strip dead Intel (x86_64/i386) slices and non-matching language resources from
# macOS application bundles, preserving code signature validity.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   9-Aug-2026  6:35pm
# Modified :   9-Aug-2026  7:09pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

readonly PROGRAM_NAME="${0##*/}"
readonly SUDO_HELPER="/opt/geedbla/lib/shell/lib/get_sudo_password.sh"
readonly DEFAULT_SCAN_ROOT="/Applications"

APPLY=false
VERBOSE=false
FORCE=false
DO_LANG=true
DO_THIN=true
BACKUP_DIR=""
EXTRA_KEEP=""

WORK_DIR=""
TARGETS=()

# per-app tallies
n_thinned=0
n_thin_skipped=0
n_lang_removed=0
n_lang_kept_intact=0
bytes_thin=0
bytes_lang=0
APP=""

# run totals
total_apps=0
total_bytes=0

#*****************************************************************************************
# output helpers
#*****************************************************************************************

log() { printf '%s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
err() { printf 'error: %s\n' "$*" >&2; }
verbose() { [[ ${VERBOSE} == true ]] && printf '    %s\n' "$*" || true; }

# prefix every mutating action so dry-run output reads honestly
action_prefix() {
	if [[ ${APPLY} == true ]]; then
		printf ''
	else
		printf 'WOULD '
	fi
}

usage() {
	cat <<EOF
usage: ${PROGRAM_NAME} [options] [<app-bundle> ...]

Removes the x86_64 slice from universal Mach-O files and deletes localization
resources that do not match the current system language.  Dry-run by default.

With no bundle named, every app in ${DEFAULT_SCAN_ROOT} is scanned.  Apple's own
apps are always skipped; their signatures cannot be replaced.

options:
  -n, --dry-run       report only, change nothing (default)
  -a, --apply         actually modify the bundles
  -b, --backup DIR    archive each bundle into DIR before modifying it
      --keep LANGS    comma separated extra languages to preserve (e.g. de,ja)
      --no-lang       skip language resource stripping
      --no-thin       skip Intel slice thinning
      --force         fully strip and ad-hoc re-sign even a protected app
  -v, --verbose       list every file acted on
  -h, --help          show this help

An app is "protected" when it carries team scoped entitlements (app groups,
iCloud, push) or an embedded provisioning profile.  Ad-hoc re-signing silently
breaks those, so protected apps are thinned only, never re-signed, and any thin
that invalidates a signature is reverted automatically.
EOF
}

cleanup() {
	[[ -n ${WORK_DIR} && -d ${WORK_DIR} ]] && rm -rf "${WORK_DIR}"
	return 0
}
trap cleanup EXIT

#*****************************************************************************************
# language helpers
#*****************************************************************************************

# fold a locale-ish name into a comparable token: lowercase, '-' -> '_', no
# .lproj suffix, no codeset suffix.  "pt-BR.lproj", "pt_BR", "zh_CN.UTF-8" all
# reduce cleanly.
normalize_lang() {
	local name="$1"
	name="${name%.lproj}"
	name="${name%.UTF-8}"
	name="${name%.utf8}"
	name="${name%.UTF8}"
	printf '%s' "$(printf '%s' "${name}" | tr '[:upper:]-' '[:lower:]_')"
}

# Ask the *user's* preferences.  This must run before any sudo re-exec, since
# under root `defaults read -g` returns root's settings, not the user's.
detect_system_language() {
	local raw primary

	raw="$(defaults read -g AppleLanguages 2>/dev/null |
		tr -d '(),"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
		grep -v '^$' | head -1)"

	if [[ -z ${raw} ]]; then
		raw="$(defaults read -g AppleLocale 2>/dev/null || true)"
	fi
	[[ -z ${raw} ]] && raw="en"

	primary="$(normalize_lang "${raw}")"
	printf '%s' "${primary}"
}

# Candidate directory tokens that satisfy the system language: the full
# language_region form and the bare language.  Legacy bundles still name
# directories after the English name of the language, so map the common ones.
language_candidates() {
	local primary="$1"
	local bare="${primary%%_*}"
	local legacy=""

	case "${bare}" in
		en) legacy="english" ;;
		fr) legacy="french" ;;
		de) legacy="german" ;;
		es) legacy="spanish" ;;
		it) legacy="italian" ;;
		ja) legacy="japanese" ;;
		nl) legacy="dutch" ;;
		pt) legacy="portuguese" ;;
		zh) legacy="chinese" ;;
		ko) legacy="korean" ;;
		ru) legacy="russian" ;;
		da) legacy="danish" ;;
		fi) legacy="finnish" ;;
		nb | no) legacy="norwegian" ;;
		sv) legacy="swedish" ;;
	esac

	printf '%s\n%s\n' "${primary}" "${bare}"
	[[ -n ${legacy} ]] && printf '%s\n' "${legacy}"
	if [[ -n ${EXTRA_KEEP} ]]; then
		printf '%s' "${EXTRA_KEEP}" | tr ',' '\n' | while IFS= read -r extra; do
			[[ -n ${extra} ]] || continue
			normalize_lang "${extra}"
			printf '\n'
			printf '%s\n' "${extra%%[-_]*}" | tr '[:upper:]' '[:lower:]'
		done
	fi
	return 0
}

in_list() {
	local needle="$1" item
	shift
	for item in "$@"; do
		[[ ${item} == "${needle}" ]] && return 0
	done
	return 1
}

english_token() {
	case "$1" in
		en | en_us | en_gb | english) return 0 ;;
	esac
	return 1
}

#*****************************************************************************************
# bundle inspection
#*****************************************************************************************

# Apple's own apps are signed by the "Software Signing" authority and live on a
# SIP-protected path.  Their signature cannot be replaced by anyone, so there is
# nothing to do but leave them alone -- which matters once a whole-directory scan
# starts handing us /Applications/Safari.app and friends.
is_apple_signed() {
	codesign -dv --verbose=2 "$1" 2>&1 | grep -q 'Authority=Software Signing'
}

# With no bundle named on the command line, sweep the applications directory.
# -prune stops find descending into a bundle it has already matched, so helper
# apps nested inside another app are not reported as targets in their own right;
# they are handled as part of their container.
collect_default_targets() {
	find "${DEFAULT_SCAN_ROOT}" -maxdepth 2 -type d -name '*.app' -prune -print 2>/dev/null |
		sort
}

# An app is protected when ad-hoc re-signing would strip capabilities the system
# grants by team identity.  Those entitlements cannot survive an ad-hoc signature.
is_protected() {
	local app="$1" ents

	[[ -f "${app}/Contents/embedded.provisionprofile" ]] && return 0

	ents="$(codesign -d --entitlements - --xml "${app}" 2>/dev/null || true)"
	case "${ents}" in
		*com.apple.application-identifier* | \
			*com.apple.developer.* | \
			*com.apple.security.application-groups* | \
			*keychain-access-groups*)
			return 0
			;;
	esac
	return 1
}

# Universal Mach-O files that carry both an Intel and an arm64 slice.  A file
# that is Intel-only must be left alone; thinning it would destroy it.
#
# Spawning lipo once per executable is unusable on a large bundle -- Xcode alone
# holds tens of thousands.  A universal file always begins with the fat magic
# 0xcafebabe/0xcafebabf, so one perl pass reads four bytes from each candidate
# and hands the handful of real matches to lipo.  Java class files share the
# 0xcafebabe magic; lipo rejects them, which is the filter that catches it.
#
# shellcheck disable=SC2016  # the perl program is single quoted on purpose
find_fat_binaries() {
	local app="$1" file archs

	find "${app}" -type f -perm +111 -print0 |
		xargs -0 perl -e '
			for my $f (@ARGV) {
				open my $fh, "<:raw", $f or next;
				my $n = read $fh, my $magic, 4;
				close $fh;
				next unless defined $n && $n == 4;
				my $m = unpack "N", $magic;
				print $f, "\0" if $m == 0xcafebabe || $m == 0xcafebabf;
			}
		' 2>/dev/null |
		while IFS= read -r -d '' file; do
			archs="$(lipo -archs "${file}" 2>/dev/null)" || continue
			case " ${archs} " in
				*" arm64 "* | *" arm64e "*) ;;
				*) continue ;;
			esac
			case " ${archs} " in
				*" x86_64 "* | *" x86_64h "* | *" i386 "*) printf '%s\0' "${file}" ;;
			esac
		done
}

# Every node codesign treats as its own unit, deepest first, so nested seals are
# rebuilt before the parents that seal them.
find_signed_nodes() {
	local app="$1"

	{
		printf '%s\n' "${app}"
		find "${app}" -type d \
			\( -name '*.app' -o -name '*.framework' -o -name '*.appex' \
			-o -name '*.xpc' -o -name '*.plugin' -o -name '*.bundle' \) -print
	} | awk -F/ '{ print NF "\t" $0 }' | sort -rn -k1,1 | cut -f2-
}

#*****************************************************************************************
# Intel thinning
#*****************************************************************************************

thin_binary() {
	local file="$1" tmp mode owner before after

	before="$(stat -f '%z' "${file}")"

	if [[ ${APPLY} != true ]]; then
		after="$(lipo "${file}" -thin arm64 -output /dev/stdout 2>/dev/null | wc -c | tr -d ' ')" || after=0
		verbose "$(action_prefix)thin ${file#"${APP}"/} ($((before / 1024)) KB)"
		printf '%s' "$((before - after))"
		return 0
	fi

	tmp="${WORK_DIR}/thin.$$"
	if ! lipo "${file}" -thin arm64 -output "${tmp}" 2>/dev/null; then
		rm -f "${tmp}"
		printf '0'
		return 1
	fi

	mode="$(stat -f '%OLp' "${file}")"
	owner="$(stat -f '%u:%g' "${file}")"
	chmod "${mode}" "${tmp}"
	chown "${owner}" "${tmp}" 2>/dev/null || true
	mv -f "${tmp}" "${file}"

	after="$(stat -f '%z' "${file}")"
	verbose "thinned ${file#"${APP}"/} ($((before / 1024)) KB -> $((after / 1024)) KB)"
	printf '%s' "$((before - after))"
	return 0
}

#*****************************************************************************************
# language resource stripping
#*****************************************************************************************

# Decide, for one directory of sibling .lproj folders, which to keep.
#
#   * a sibling matching the system language wins
#   * otherwise Base.lproj is the development-region fallback and is sufficient
#   * otherwise keep English
#   * otherwise keep everything -- we cannot prove a fallback exists
#
# The decision is per directory because a bundle can hold several independent
# localization sets: Ghostty's Sparkle resources have Base plus 36 languages and
# no en.lproj at all.
strip_lproj_dir() {
	local parent="$1"
	shift
	local candidates=("$@")
	local child name norm freed size
	local matched=false has_base=false has_english=false
	local keep_mode

	for child in "${parent}"/*.lproj; do
		[[ -d ${child} ]] || continue
		name="${child##*/}"
		norm="$(normalize_lang "${name}")"
		[[ ${norm} == "base" ]] && has_base=true && continue
		in_list "${norm}" "${candidates[@]}" && matched=true
		english_token "${norm}" && has_english=true
	done

	if [[ ${matched} == true ]]; then
		keep_mode="match"
	elif [[ ${has_base} == true ]]; then
		keep_mode="base"
	elif [[ ${has_english} == true ]]; then
		keep_mode="english"
	else
		keep_mode="all"
	fi

	if [[ ${keep_mode} == "all" ]]; then
		verbose "no system-language, Base or English resource in ${parent#"${APP}"/} - left intact"
		n_lang_kept_intact=$((n_lang_kept_intact + 1))
		return 0
	fi

	freed=0
	for child in "${parent}"/*.lproj; do
		[[ -d ${child} ]] || continue
		name="${child##*/}"
		norm="$(normalize_lang "${name}")"

		[[ ${norm} == "base" ]] && continue
		case "${keep_mode}" in
			match) in_list "${norm}" "${candidates[@]}" && continue ;;
			english) english_token "${norm}" && continue ;;
		esac

		size="$(du -sk "${child}" | cut -f1)"
		freed=$((freed + size * 1024))
		n_lang_removed=$((n_lang_removed + 1))
		verbose "$(action_prefix)remove ${child#"${APP}"/} (${size} KB)"
		[[ ${APPLY} == true ]] && rm -rf "${child}"
	done

	bytes_lang=$((bytes_lang + freed))
	return 0
}

# gettext catalogues: <root>/<lang>/LC_MESSAGES/*.mo
#
# Unlike .lproj there is no Base directory, and a missing catalogue is not a
# failure: gettext falls back to the msgid text compiled into the binary, which
# is the source language.  So when nothing matches, every catalogue is dead
# weight and all of them go.
strip_gettext_root() {
	local root="$1"
	shift
	local candidates=("$@")
	local child name norm size freed matched=false

	for child in "${root}"/*; do
		[[ -d "${child}/LC_MESSAGES" ]] || continue
		name="${child##*/}"
		norm="$(normalize_lang "${name}")"
		in_list "${norm}" "${candidates[@]}" && matched=true
	done

	freed=0
	for child in "${root}"/*; do
		[[ -d "${child}/LC_MESSAGES" ]] || continue
		name="${child##*/}"
		norm="$(normalize_lang "${name}")"

		if [[ ${matched} == true ]] && in_list "${norm}" "${candidates[@]}"; then
			continue
		fi

		size="$(du -sk "${child}" | cut -f1)"
		freed=$((freed + size * 1024))
		n_lang_removed=$((n_lang_removed + 1))
		verbose "$(action_prefix)remove ${child#"${APP}"/} (${size} KB)"
		[[ ${APPLY} == true ]] && rm -rf "${child}"
	done

	bytes_lang=$((bytes_lang + freed))
	return 0
}

strip_languages() {
	local app="$1"
	local candidates=()
	local parent root line

	while IFS= read -r line; do
		[[ -n ${line} ]] && candidates+=("${line}")
	done < <(language_candidates "${SYS_LANG}")

	while IFS= read -r parent; do
		[[ -n ${parent} ]] || continue
		strip_lproj_dir "${parent}" "${candidates[@]}"
	done < <(find "${app}" -type d -name '*.lproj' -print0 |
		xargs -0 -n1 dirname 2>/dev/null | sort -u)

	while IFS= read -r root; do
		[[ -n ${root} ]] || continue
		strip_gettext_root "${root}" "${candidates[@]}"
	done < <(find "${app}" -type d -name 'LC_MESSAGES' -print0 |
		xargs -0 -n1 dirname 2>/dev/null |
		xargs -n1 dirname 2>/dev/null | sort -u)
}

#*****************************************************************************************
# signing
#*****************************************************************************************

# codesign refuses to write a signature over a Finder info or resource fork
# xattr.  Clear only those two -- a blanket `xattr -cr` would also drop
# com.apple.macl, which records file access the user already granted the app.
clear_signing_xattrs() {
	local app="$1" file

	find "${app}" -print0 | while IFS= read -r -d '' file; do
		xattr -d com.apple.FinderInfo "${file}" 2>/dev/null || true
		xattr -d com.apple.ResourceFork "${file}" 2>/dev/null || true
	done
	return 0
}

has_hardened_runtime() {
	codesign -dv --verbose=2 "$1" 2>&1 | grep -q 'flags=.*runtime'
}

# Sign one node ad-hoc.
#
# `requirements` is never preserved: the designated requirement names the
# original Developer ID certificate and would refuse to validate ad-hoc.
#
# The subtle part is library validation.  Under the hardened runtime a process
# may only load libraries signed by its own team, and an ad-hoc signature has no
# team at all -- so an ad-hoc app cannot load its own ad-hoc frameworks.  The
# bundle still passes `codesign --verify`; it simply refuses to launch, with dyld
# reporting "different Team IDs".  Granting disable-library-validation is what
# makes a re-signed bundle actually runnable, so hardened nodes are signed with
# their original entitlements plus that key.
sign_node() {
	local node="$1" ents

	if ! has_hardened_runtime "${node}"; then
		codesign --force --sign - \
			--preserve-metadata=identifier,entitlements,flags,runtime \
			"${node}" 2>/dev/null
		return
	fi

	ents="${WORK_DIR}/ents.plist"
	rm -f "${ents}"
	codesign -d --entitlements - --xml "${node}" 2>/dev/null >"${ents}" || true

	if [[ ! -s ${ents} ]]; then
		cat >"${ents}" <<-'EOF'
			<?xml version="1.0" encoding="UTF-8"?>
			<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
			<plist version="1.0"><dict/></plist>
		EOF
	fi

	# PlistBuddy, not plutil: plutil reads '.' in a key as a path separator, so
	# it cannot address a reverse-DNS entitlement name at all.
	/usr/libexec/PlistBuddy \
		-c "Add :com.apple.security.cs.disable-library-validation bool true" \
		"${ents}" >/dev/null 2>&1 || true

	codesign --force --sign - --options runtime \
		--preserve-metadata=identifier \
		--entitlements "${ents}" \
		"${node}" 2>/dev/null
}

resign_bundle() {
	local app="$1" node rc=0

	clear_signing_xattrs "${app}"

	while IFS= read -r node; do
		[[ -n ${node} ]] || continue
		[[ -e ${node} ]] || continue
		verbose "sign ${node#"${APP}"/}"
		if ! sign_node "${node}"; then
			warn "failed to sign ${node}"
			rc=1
		fi
	done < <(find_signed_nodes "${app}")

	return "${rc}"
}

#*****************************************************************************************
# per-app drivers
#*****************************************************************************************

# Protected apps get no re-sign, so every thin has to stand on its own.
#
# Thinning is often invisible to codesign: each slice of a universal file carries
# its own signature, so the arm64 cdhash is unchanged and anything sealed by
# cdhash still matches.  Sparkle's Autoupdate and a helper tool sitting beside an
# .xpc main binary both survive it.  But a Mach-O sealed as a plain *resource*
# does not -- in AirBuddy, DeviceGlyphs.bundle inside AirUI.framework/Resources
# is hashed as a file, and thinning it invalidates the framework.
#
# The rule is not worth deriving.  Thin one file at a time and let codesign rule
# on the whole bundle; a full deep verify costs about a tenth of a second.
process_protected() {
	local app="$1" file saved freed output sub

	info "protected: team-scoped entitlements present - thinning only, no re-sign"
	info "language resources left untouched (removing them requires a re-sign)"

	if [[ ${DO_THIN} != true ]]; then
		info "thinning disabled by --no-thin; nothing to do"
		return 0
	fi

	[[ ${APPLY} == true ]] ||
		info "a dry run cannot tell which thins break the seal - some of the"
	[[ ${APPLY} == true ]] ||
		info "binaries counted below will be reverted and left fat"

	while IFS= read -r -d '' file; do
		if [[ ${APPLY} != true ]]; then
			freed="$(thin_binary "${file}")" || freed=0
			bytes_thin=$((bytes_thin + freed))
			n_thinned=$((n_thinned + 1))
			continue
		fi

		saved="${WORK_DIR}/saved.$(printf '%s' "${file}" | shasum | cut -d' ' -f1)"
		cp -p "${file}" "${saved}"

		freed="$(thin_binary "${file}")" || freed=0

		if output="$(codesign --verify --deep --strict "${app}" 2>&1)"; then
			rm -f "${saved}"
			bytes_thin=$((bytes_thin + freed))
			n_thinned=$((n_thinned + 1))
			continue
		fi

		cp -p "${saved}" "${file}"
		rm -f "${saved}"
		n_thin_skipped=$((n_thin_skipped + 1))

		sub="$(printf '%s\n' "${output}" | sed -n 's/^In subcomponent: //p' | tail -1)"
		[[ -n ${sub} ]] && sub="${sub##*/}" || sub="the app bundle"
		info "kept fat: ${file#"${app}"/} (breaks the seal on ${sub})"
	done < <(find_fat_binaries "${app}")

	if [[ ${APPLY} == true ]]; then
		if codesign --verify --deep --strict "${app}" 2>/dev/null; then
			info "signature: original Developer ID, still verifies"
		else
			err "bundle no longer verifies - restore it from a backup"
			return 1
		fi
	fi

	return 0
}

process_open() {
	local app="$1" file freed

	if [[ ${DO_THIN} == true ]]; then
		while IFS= read -r -d '' file; do
			freed="$(thin_binary "${file}")" || freed=0
			bytes_thin=$((bytes_thin + freed))
			n_thinned=$((n_thinned + 1))
		done < <(find_fat_binaries "${app}")
	fi

	[[ ${DO_LANG} == true ]] && strip_languages "${app}"

	if [[ $((n_thinned + n_lang_removed)) -eq 0 ]]; then
		info "nothing to strip - signature left as-is"
		return 0
	fi

	if [[ ${APPLY} != true ]]; then
		info "WOULD ad-hoc re-sign the bundle and its nested code"
		return 0
	fi

	resign_bundle "${app}" || true

	if codesign --verify --deep --strict "${app}" 2>/dev/null; then
		info "signature: ad-hoc, verifies"
	else
		err "signature verification FAILED after re-signing"
		return 1
	fi

	return 0
}

make_backup() {
	local app="$1" name archive

	name="${app##*/}"
	archive="${BACKUP_DIR}/${name}.$(date '+%Y%m%d-%H%M%S').tar.zst"

	if [[ ${APPLY} != true ]]; then
		info "WOULD back up to ${archive}"
		return 0
	fi

	mkdir -p "${BACKUP_DIR}"
	if command -v zstd >/dev/null 2>&1; then
		tar --zstd -cf "${archive}" -C "$(dirname "${app}")" "${name}"
	else
		archive="${archive%.zst}.gz"
		tar -czf "${archive}" -C "$(dirname "${app}")" "${name}"
	fi
	info "backed up to ${archive}"
}

process_app() {
	local app="$1" before after protected

	app="${app%/}"
	APP="${app}"

	if [[ ! -d "${app}/Contents" ]]; then
		err "not an app bundle: ${app}"
		return 1
	fi

	n_thinned=0
	n_thin_skipped=0
	n_lang_removed=0
	n_lang_kept_intact=0
	bytes_thin=0
	bytes_lang=0

	before="$(du -sk "${app}" | cut -f1)"

	log ""
	log "${app##*/}  (${before} KB)"

	if is_apple_signed "${app}"; then
		info "Apple system app - skipped"
		return 0
	fi

	if is_protected "${app}" && [[ ${FORCE} != true ]]; then
		protected=true
	else
		protected=false
		is_protected "${app}" && info "protected app forced open by --force"
	fi

	[[ -n ${BACKUP_DIR} ]] && make_backup "${app}"

	if [[ ${protected} == true ]]; then
		process_protected "${app}" || return 1
	else
		process_open "${app}" || return 1
	fi

	after="$(du -sk "${app}" | cut -f1)"

	info "binaries thinned      : ${n_thinned}"
	[[ ${n_thin_skipped} -gt 0 ]] && info "binaries left fat     : ${n_thin_skipped} (seal would break)"
	info "language dirs removed : ${n_lang_removed}"
	[[ ${n_lang_kept_intact} -gt 0 ]] && info "language sets untouched: ${n_lang_kept_intact} (no safe fallback)"
	info "reclaimed             : $(((bytes_thin + bytes_lang) / 1024)) KB (intel $((bytes_thin / 1024)) KB, lang $((bytes_lang / 1024)) KB)"
	[[ ${APPLY} == true ]] && info "size                  : ${before} KB -> ${after} KB"

	total_apps=$((total_apps + 1))
	total_bytes=$((total_bytes + bytes_thin + bytes_lang))

	return 0
}

#*****************************************************************************************
# entry point
#*****************************************************************************************

# Warm sudo's credential timestamp so the re-exec below never has to prompt.
#
# get_sudo_password returns an empty string when sudo is already validated, and
# otherwise the password from the login keychain, falling back to a prompt.  It
# does not validate a keychain-sourced password itself, so feed it to sudo here.
# Priming this way also means the script works with no controlling terminal,
# where a bare `sudo` would just fail.
prime_sudo() {
	local password=""

	sudo --validate --non-interactive &>/dev/null && return 0

	if [[ -r ${SUDO_HELPER} ]]; then
		# shellcheck source=/dev/null
		. "${SUDO_HELPER}"
		password="$(get_sudo_password)"
	else
		warn "${SUDO_HELPER} not found - falling back to an interactive prompt"
	fi

	if [[ -n ${password} ]]; then
		sudo --validate --stdin <<<"${password}" 2>/dev/null && return 0
	fi

	sudo --validate 2>/dev/null
}

# Bundles under /Applications are root owned, but one sitting in a user
# directory is not.  Only escalate when something actually needs it.
needs_root() {
	local app

	for app in "${TARGETS[@]}"; do
		app="${app%/}"
		[[ -d ${app} ]] || continue
		if [[ ! -w ${app} || ! -w "${app}/Contents" ]]; then
			return 0
		fi
	done
	return 1
}

main() {
	local orig_args=("$@")
	local rc=0 app scanned=false

	while [[ $# -gt 0 ]]; do
		case "$1" in
			-h | --help)
				usage
				exit 0
				;;
			-n | --dry-run)
				APPLY=false
				shift
				;;
			-a | --apply)
				APPLY=true
				shift
				;;
			-b | --backup)
				BACKUP_DIR="${2:-}"
				shift 2
				;;
			--keep)
				EXTRA_KEEP="${2:-}"
				shift 2
				;;
			--no-lang)
				DO_LANG=false
				shift
				;;
			--no-thin)
				DO_THIN=false
				shift
				;;
			--force)
				FORCE=true
				shift
				;;
			-v | --verbose)
				VERBOSE=true
				shift
				;;
			-*)
				err "unknown option: $1"
				usage >&2
				exit 2
				;;
			*)
				TARGETS+=("$1")
				shift
				;;
		esac
	done

	if [[ ${#TARGETS[@]} -eq 0 ]]; then
		scanned=true
		while IFS= read -r app; do
			[[ -n ${app} ]] && TARGETS+=("${app}")
		done < <(collect_default_targets)

		if [[ ${#TARGETS[@]} -eq 0 ]]; then
			err "no app bundles found in ${DEFAULT_SCAN_ROOT}"
			exit 1
		fi
	fi

	# Resolve the language while still running as the invoking user; root has
	# different preferences.  Pass it across the sudo boundary explicitly.
	if [[ -z ${STRIP_APP_LANG:-} ]]; then
		STRIP_APP_LANG="$(detect_system_language)"
	fi
	readonly SYS_LANG="${STRIP_APP_LANG}"
	export STRIP_APP_LANG

	if [[ ${APPLY} == true && ${EUID} -ne 0 ]] && needs_root; then
		log "re-running under sudo to modify root-owned bundles..."
		if ! prime_sudo; then
			err "could not obtain sudo privileges"
			exit 1
		fi
		exec sudo --preserve-env=STRIP_APP_LANG -- "$0" "${orig_args[@]}"
	fi

	WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/strip-app.XXXXXX")"

	log "system language: ${SYS_LANG}"
	[[ ${scanned} == true ]] &&
		log "scanned ${DEFAULT_SCAN_ROOT}: ${#TARGETS[@]} app bundles"
	[[ ${APPLY} == true ]] || log "DRY RUN - nothing will be modified (use --apply)"

	for app in "${TARGETS[@]}"; do
		process_app "${app}" || rc=1
	done

	if [[ ${#TARGETS[@]} -gt 1 ]]; then
		log ""
		log "total: ${total_apps} apps processed, $((total_bytes / 1024)) KB reclaimable"
	fi

	if [[ ${APPLY} == true ]]; then
		log ""
		log "note: re-signed apps lose notarization; macOS will re-prompt for any"
		log "      privacy permissions they had already been granted."
		log "note: an app update replaces the bundle - re-run this afterwards."
	fi

	return "${rc}"
}

main "$@"
