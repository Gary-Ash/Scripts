#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# strip-app.sh
#
# Remove dead Intel slices and unused localizations from macOS application bundles
# without ever invalidating - or replacing - the code signature.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  11-Aug-2026  8:15pm
# Modified :  12-Aug-2026  6:00pm
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

readonly PROGRAM_NAME="${0##*/}"
readonly SUDO_HELPER="/opt/geedbla/lib/shell/lib/get_sudo_password.sh"
readonly DEFAULT_SCAN_ROOT="/Applications"

APPLY=true
VERBOSE=false
DO_LANG=true
DO_THIN=true
MODE="strip"
EXTRA_KEEP=""

WORK_DIR=""
SYS_LANG=""
APP=""
TARGETS=()

# per-app tallies
n_thinned=0
n_thin_skipped=0
n_lang_removed=0
n_lang_kept_intact=0
bytes_thin=0
bytes_lang=0

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

Removes the Intel slices from universal Mach-O files and deletes localizations
that do not match the current system language.  With no bundle named, every app
in ${DEFAULT_SCAN_ROOT} is processed.

Only changes that provably cannot break the code signature are made, so bundles
keep their original Developer ID, notarization and privacy grants.  Nothing is
ever re-signed.  There are no strategy options: the safe method is the only one.

options:
  -n, --dry-run       report only, change nothing
      --keep LANGS    comma separated extra languages to preserve (e.g. de,ja)
      --no-lang       skip localization pruning
      --no-thin       skip Intel slice removal
      --check         report bundles whose seal is already broken, and why
      --repair        report how to repair the bundles --check found
  -v, --verbose       list every file acted on
  -h, --help          show this help
EOF
}

cleanup() {
	[[ -n ${WORK_DIR} && -d ${WORK_DIR} ]] && rm -rf "${WORK_DIR}"
	return 0
}

#*****************************************************************************************
# language helpers
#*****************************************************************************************

# Fold a locale-ish name into a comparable token: lowercase, '-' -> '_', no .lproj
# suffix, no codeset suffix.  "pt-BR.lproj", "pt_BR" and "zh_CN.UTF-8" all reduce
# cleanly.
normalize_lang() {
	local name="$1"

	name="${name%.lproj}"
	name="${name%.UTF-8}"
	name="${name%.utf8}"
	name="${name%.UTF8}"
	printf '%s' "${name}" | tr '[:upper:]-' '[:lower:]_'
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

# Bundles predating the ISO naming still name their directories after the English
# name of the language, so map the ones that actually turn up.
legacy_lang_name() {
	case "$1" in
		en) printf 'english' ;;
		fr) printf 'french' ;;
		de) printf 'german' ;;
		es) printf 'spanish' ;;
		it) printf 'italian' ;;
		ja) printf 'japanese' ;;
		nl) printf 'dutch' ;;
		pt) printf 'portuguese' ;;
		zh) printf 'chinese' ;;
		ko) printf 'korean' ;;
		ru) printf 'russian' ;;
		da) printf 'danish' ;;
		fi) printf 'finnish' ;;
		nb | no) printf 'norwegian' ;;
		sv) printf 'swedish' ;;
	esac
	return 0
}

# Every directory token that satisfies the languages we intend to keep: the full
# language_region form, the bare language, and the legacy English name.
language_candidates() {
	local primary="$1"
	local bare legacy extra

	bare="${primary%%_*}"
	printf '%s\n%s\n' "${primary}" "${bare}"
	legacy="$(legacy_lang_name "${bare}")"
	[[ -n ${legacy} ]] && printf '%s\n' "${legacy}"

	if [[ -n ${EXTRA_KEEP} ]]; then
		while IFS= read -r extra; do
			[[ -n ${extra} ]] || continue
			extra="$(normalize_lang "${extra}")"
			bare="${extra%%_*}"
			printf '%s\n%s\n' "${extra}" "${bare}"
			legacy="$(legacy_lang_name "${bare}")"
			[[ -n ${legacy} ]] && printf '%s\n' "${legacy}"
		done < <(printf '%s\n' "${EXTRA_KEEP}" | tr ',' '\n')
	fi
	return 0
}

# Ask the *user's* preferences.  This has to run before any sudo re-exec: under
# root `defaults read -g` returns root's settings, not the user's.
detect_system_language() {
	local raw

	raw="$(defaults read -g AppleLanguages 2>/dev/null |
		tr -d '(),"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
		grep -v '^$' | head -1)"

	[[ -z ${raw} ]] && raw="$(defaults read -g AppleLocale 2>/dev/null || true)"
	[[ -z ${raw} ]] && raw="en"

	normalize_lang "${raw}"
}

#*****************************************************************************************
# seal classification
#
# This is the whole safety argument of the script, so it is worth stating plainly.
#
# A universal Mach-O carries a separate, complete code signature inside every slice.
# Dropping the x86_64 slice leaves the arm64 slice byte for byte identical, so its
# CDHash is unchanged.  Whether that matters to the enclosing bundle depends only on
# how the bundle's _CodeSignature/CodeResources seals the file:
#
#   own      the bundle's own main executable.  It is not listed in the seal at all -
#            it is covered by its own signature, which the untouched slice still
#            carries.  Safe.
#   cdhash   nested code (MacOS/, Frameworks/, SharedFrameworks/, PlugIns/,
#            XPCServices/, Helpers/, Library/{Automator,Spotlight,LoginItems}/ and
#            top level names).  The seal records the native slice's CDHash, which the
#            thin does not change.  Safe.
#   content  everything else, in practice anything under Resources/.  The seal records
#            a hash of the whole file, which the thin does change.  Fatal.
#
# A bundle may be sealed by its parent as plain content even when it carries a
# _CodeSignature of its own - AirBuddy's DeviceGlyphs.bundle, inside AirUI.framework's
# Resources, is exactly that.  So classification consults *every* ancestor seal and
# takes the most restrictive answer, rather than stopping at the innermost one.
#*****************************************************************************************

# Flatten one seal's files2 dictionary to "class<TAB>relative-path" lines.
#
# shellcheck disable=SC2016  # the perl program is single quoted on purpose
parse_seal() {
	local root="$1" plist

	plist="$(plutil -extract files2 xml1 -o - "${root}/_CodeSignature/CodeResources" 2>/dev/null)" ||
		plist="$(plutil -extract files xml1 -o - "${root}/_CodeSignature/CodeResources" 2>/dev/null)" ||
		{
			printf '!unparsed\n'
			return 0
		}

	printf '%s' "${plist}" | perl -ne '
		BEGIN { $depth = 0; $key = undef; $cdhash = 0 }
		if (m{<key>(.*)</key>} && $depth == 1) { $key = $1 }
		if (m{<dict/>}) { print "content\t$key\n" if $depth == 1 && defined $key; next }
		if (m{<dict>}) { $depth++; $cdhash = 0 if $depth == 2; next }
		if (m{</dict>}) {
			print(($cdhash ? "cdhash" : "content"), "\t$key\n") if $depth == 2 && defined $key;
			$depth--;
			next;
		}
		$cdhash = 1 if $depth == 2 && m{<key>cdhash</key>};
		print "content\t$key\n" if $depth == 1 && defined $key && m{<data>};
	'
}

# Parse each seal root once; a bundle the size of Xcode has hundreds of them.
seal_cache_file() {
	local root="$1" index="${WORK_DIR}/seal-index" line

	mkdir -p "${WORK_DIR}/seals"
	touch "${index}"

	line="$(grep -n -F -x -- "${root}" "${index}" 2>/dev/null | head -1 | cut -d: -f1)" || true
	if [[ -z ${line} ]]; then
		printf '%s\n' "${root}" >>"${index}"
		line="$(wc -l <"${index}" | tr -d ' ')"
		parse_seal "${root}" >"${WORK_DIR}/seals/${line}"
	fi

	printf '%s' "${WORK_DIR}/seals/${line}"
}

# How one seal records one relative path: cdhash, content, or absent.
seal_lookup() {
	local root="$1" rel="$2" cache class

	cache="$(seal_cache_file "${root}")"
	if [[ "$(head -1 "${cache}")" == '!unparsed' ]]; then
		printf 'content'
		return 0
	fi

	class="$(awk -F'\t' -v r="${rel}" '$2 == r { print $1; exit }' "${cache}")"
	printf '%s' "${class:-absent}"
}

# The nearest seal root at or above a directory, still inside the app.
enclosing_seal_root() {
	local app="${1%/}" dir="$2"

	while [[ ${dir} == "${app}"/* || ${dir} == "${app}" ]]; do
		if [[ -f "${dir}/_CodeSignature/CodeResources" ]]; then
			printf '%s' "${dir}"
			return 0
		fi
		dir="$(dirname "${dir}")"
	done
	return 1
}

# Does this seal look inside the given subtree at all?  A seal that records a nested
# bundle by cdhash has no entries below it and does not care what it contains; a seal
# that records the interior file by file does.
seal_covers_subtree() {
	local root="$1" rel="$2" cache

	cache="$(seal_cache_file "${root}")"
	[[ "$(head -1 "${cache}")" == '!unparsed' ]] && return 0

	awk -F'\t' -v r="${rel}" '
		$2 == r || index($2, r "/") == 1 { found = 1; exit }
		END { exit(found ? 0 : 1) }
	' "${cache}"
}

# own | cdhash | content, for a file somewhere inside an app bundle.
seal_class() {
	local app="${1%/}" file="$2"
	local dir rel class result="own"

	dir="$(dirname "${file}")"
	while [[ ${dir} == "${app}"/* || ${dir} == "${app}" ]]; do
		if [[ -f "${dir}/_CodeSignature/CodeResources" ]]; then
			rel="${file#"${dir}"/}"
			class="$(seal_lookup "${dir}" "${rel}")"
			case "${class}" in
				content)
					printf 'content'
					return 0
					;;
				cdhash) result="cdhash" ;;
			esac
		fi
		dir="$(dirname "${dir}")"
	done

	printf '%s' "${result}"
}

#*****************************************************************************************
# Intel slice removal
#*****************************************************************************************

readonly DEAD_ARCHES="i386 x86_64 x86_64h ppc ppc64 ppc7400 ppc970"

# The dead slices actually present in a file, or nothing when there is no live arm
# slice to keep.  A binary that is Intel only must be left alone - thinning it would
# destroy it.
dead_arches_of() {
	local file="$1" archs arch dead=""

	archs="$(lipo -archs "${file}" 2>/dev/null)" || return 0
	case " ${archs} " in
		*" arm64 "* | *" arm64e "* | *" arm64_32 "*) ;;
		*) return 0 ;;
	esac

	for arch in ${DEAD_ARCHES}; do
		case " ${archs} " in
			*" ${arch} "*) dead="${dead} ${arch}" ;;
		esac
	done

	printf '%s' "${dead# }"
}

# The arm slices worth keeping, in the order lipo reports them.
live_arches_of() {
	local file="$1" archs arch live=""

	archs="$(lipo -archs "${file}" 2>/dev/null)" || return 0
	for arch in ${archs}; do
		case "${arch}" in
			arm64 | arm64e | arm64_32) live="${live} ${arch}" ;;
		esac
	done

	printf '%s' "${live# }"
}

# Every universal Mach-O carrying a dead slice, one NUL terminated "verdict<TAB>path"
# record each: `thin` when the seal permits it, `skip` when the seal records the file by
# content.  The rejects are reported rather than dropped so the caller can log them - a
# producer writing its data to stdout cannot also narrate on stdout, or the commentary
# lands in the middle of a path.
#
# Spawning lipo once per executable is unusable on a large bundle - Xcode alone holds
# tens of thousands.  A universal file always begins with the fat magic
# 0xcafebabe/0xcafebabf, so one perl pass reads four bytes from each candidate and
# only the handful of real matches reach lipo.  Java class files share the 0xcafebabe
# magic; lipo rejects them, which is the filter that catches it.
#
# -type f excludes symlinks, which matters: writing through a framework's
# Versions/Current stub would replace the link with a regular file.
#
# shellcheck disable=SC2016  # the perl program is single quoted on purpose
find_fat_binaries() {
	local app="$1" file

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
			[[ -n "$(dead_arches_of "${file}")" ]] || continue
			case "$(seal_class "${app}" "${file}")" in
				own | cdhash) printf 'thin\t%s\0' "${file}" ;;
				*) printf 'skip\t%s\0' "${file}" ;;
			esac
		done
}

# Remove the dead slices in place.
#
# The rewrite goes through the existing inode with `cat`, not `mv`: a replaced inode
# loses the file's extended attributes, and /Applications bundles carry com.apple.macl,
# which is where macOS records the privacy permissions the user already granted.
#
# `lipo -remove` keeps the fat wrapper and, with it, the alignment padding the removed
# slice used to sit in - on a small binary that reclaims nothing at all.  When a single
# arm slice is left there is no reason to keep a fat wrapper around it, so use -thin and
# get the padding back too.  Anything with both arm64 and arm64e still has to go through
# -remove, since -thin would throw one of them away.
#
# The reclaimed byte count comes back in THIN_BYTES rather than on stdout: the function
# also emits verbose output, and `$(thin_binary ...)` would capture the message along
# with the number and feed the pair to $(( )).
THIN_BYTES=0

thin_binary() {
	local file="$1"
	local dead live tmp before after arch args=()

	THIN_BYTES=0
	dead="$(dead_arches_of "${file}")"
	if [[ -z ${dead} ]]; then
		return 0
	fi

	live="$(live_arches_of "${file}")"
	if [[ ${live} == *" "* ]]; then
		for arch in ${dead}; do
			args+=(-remove "${arch}")
		done
	else
		args=(-thin "${live}")
	fi

	before="$(stat -f '%z' "${file}")"
	tmp="${WORK_DIR}/thin.$$"
	if ! lipo "${file}" "${args[@]}" -output "${tmp}" 2>/dev/null; then
		rm -f "${tmp}"
		return 1
	fi
	after="$(stat -f '%z' "${tmp}")"

	if [[ ${APPLY} == true ]]; then
		cat "${tmp}" >"${file}"
		verbose "thinned ${file#"${APP}"/} ($((before / 1024)) KB -> $((after / 1024)) KB, dropped ${dead})"
	else
		verbose "$(action_prefix)thin ${file#"${APP}"/} ($((before / 1024)) KB, dropping ${dead})"
	fi

	rm -f "${tmp}"
	THIN_BYTES=$((before - after))
	return 0
}

#*****************************************************************************************
# staging
#
# Everything this script touches is stashed first, so codesign gets the last word and
# any change it dislikes can be put back exactly.  Files are copied (the original inode
# stays in place and keeps its extended attributes); directories are moved, which is
# both the deletion and the backup in one step.
#*****************************************************************************************

# codesign reports physical paths - /private/tmp/... where the caller said /tmp/... - so
# the staging index has to be keyed on the physical path or a rollback will not find its
# own backup.
real_path() {
	local path="${1%/}" dir base

	dir="$(dirname "${path}")"
	base="$(basename "${path}")"
	if [[ -d ${dir} ]]; then
		dir="$(cd "${dir}" && pwd -P)"
		printf '%s/%s' "${dir%/}" "${base}"
	else
		printf '%s' "${path}"
	fi
}

stage_reset() {
	rm -rf "${WORK_DIR}/stage" "${WORK_DIR}/stage.index"
	mkdir -p "${WORK_DIR}/stage"
	: >"${WORK_DIR}/stage.index"
}

stage_slot() {
	local path slot

	path="$(real_path "$1")"
	mkdir -p "${WORK_DIR}/stage"
	printf '%s\n' "${path}" >>"${WORK_DIR}/stage.index"
	slot="$(wc -l <"${WORK_DIR}/stage.index" | tr -d ' ')"
	printf '%s' "${slot}"
}

stage_file() {
	local path="$1" slot

	slot="$(stage_slot "${path}")"
	cp -p "${path}" "${WORK_DIR}/stage/${slot}"
}

stage_move() {
	local path="$1" slot

	slot="$(stage_slot "${path}")"
	mv "${path}" "${WORK_DIR}/stage/${slot}"
}

# Put one staged path back where it came from.  Regular files go back through the
# existing inode so the extended attributes survive a rollback too.
#
# A staged symlink needs -L everywhere -e appears: its target is relative to the place it
# came from, so inside the staging directory it dangles, and every -e test on it answers
# no.  Untreated, a rollback silently drops the one thing it was asked to put back.
stage_restore() {
	local path slot backup

	path="$(real_path "$1")"
	slot="$(grep -n -F -x -- "${path}" "${WORK_DIR}/stage.index" 2>/dev/null | tail -1 | cut -d: -f1)" || true
	[[ -n ${slot} ]] || return 1

	backup="${WORK_DIR}/stage/${slot}"
	[[ -e ${backup} || -L ${backup} ]] || return 1

	if [[ -L ${backup} || -d ${backup} ]]; then
		rm -rf "${path}"
		mv "${backup}" "${path}"
	elif [[ -e ${path} ]]; then
		cat "${backup}" >"${path}"
		rm -f "${backup}"
	else
		cp -p "${backup}" "${path}"
		rm -f "${backup}"
	fi
	return 0
}

stage_restore_all() {
	local path

	[[ -f "${WORK_DIR}/stage.index" ]] || return 0
	while IFS= read -r path; do
		[[ -n ${path} ]] && stage_restore "${path}" || true
	done < <(tail -r "${WORK_DIR}/stage.index")
	return 0
}

#*****************************************************************************************
# symlink pinning
#
# A symlink is sealed as an entry in its own right and carries no optional flag, so no
# symlink is ever removable and every one of them outlives the strip.  codesign resolves
# the links it walks, and a surviving link whose target has been deleted stops the verify
# with ENOENT - which fails the whole bundle, not the one resource.  So anything a link
# points at is pinned in place along with the link.
#
# Typora's Sparkle.framework is the case in point: fr_CA.lproj -> fr.lproj and
# pt.lproj -> pt_BR.lproj pin two of the 34 localizations that would otherwise all go.
#
# The targets are resolved before anything is deleted, in one perl pass rather than a
# readlink per link - a bundle the size of Xcode holds tens of thousands.  abs_path
# resolves every symlinked component, not just the last one, so the answers can be
# compared against the physical paths real_path hands back.
#
# shellcheck disable=SC2016  # the perl program is single quoted on purpose
#*****************************************************************************************

index_symlink_targets() {
	local app="${1%/}"

	find "${app}" -type l -print0 |
		perl -0 -MCwd=abs_path -ne '
			chomp;
			my $target = readlink $_;
			next unless defined $target;
			unless ($target =~ m{^/}) {
				(my $dir = $_) =~ s{/[^/]*$}{};
				$target = "$dir/$target";
			}
			my $real = abs_path($target);
			print "$real\n" if defined $real;
		' 2>/dev/null | sort -u >"${WORK_DIR}/pinned"
	return 0
}

# Is this path a symlink target, or does it hold one?
is_pinned() {
	local path

	[[ -s "${WORK_DIR}/pinned" ]] || return 1
	path="$(real_path "$1")"

	awk -v p="${path}" '
		$0 == p || index($0, p "/") == 1 { found = 1; exit }
		END { exit(found ? 0 : 1) }
	' "${WORK_DIR}/pinned"
}

#*****************************************************************************************
# localization pruning
#
# Deleting a localization is safe for exactly one reason: codesign's default resource
# rules declare it optional.  From any bundle's _CodeSignature/CodeResources:
#
#   ^Resources/.*\.lproj/            optional = true, weight 1000
#   ^Resources/Base\.lproj/          weight 1010, and NOT optional
#
# A missing optional resource does not invalidate the seal, which is why a stripped
# bundle keeps its original Developer ID with no re-signing.  Base.lproj carries more
# weight and no optional flag, so it is mandatory and never removed.
#*****************************************************************************************

# Does this seal really declare .lproj optional?  The rules are per bundle and a bundle
# is free to ship its own, so ask rather than assume.
#
# shellcheck disable=SC2016  # the perl program is single quoted on purpose
seal_lproj_optional() {
	local root="$1"

	plutil -extract rules2 xml1 -o - "${root}/_CodeSignature/CodeResources" 2>/dev/null |
		perl -0777 -ne '
			my $ok = 0;
			while (m{<key>([^<]*\.lproj/)</key>\s*<dict>(.*?)</dict>}gs) {
				my ($key, $body) = ($1, $2);
				next if $key =~ /Base/;
				$ok = 1 if $body =~ m{<key>optional</key>\s*<true/>};
			}
			exit($ok ? 0 : 1);
		'
}

# A localization may go only when every seal that actually inspects it agrees: the path
# has to sit under that bundle's Resources/, which is what the optional rule is anchored
# to, and that bundle's own rules have to mark it optional.
#
# The climb stops at the first seal that does not look inside the localization at all.
# A parent that records the enclosing bundle by cdhash has no entries below it and does
# not care what it holds - which is exactly how Sparkle's 34 localizations can be deleted
# from inside a framework the app seals as nested code.  A parent that lists the interior
# file by file does care, and there the optional rule has to hold as well.
#
# A .lproj is not always a directory.  Sparkle ships fr_CA.lproj -> fr.lproj and
# pt.lproj -> pt_BR.lproj, and the seal records a symlink as an entry of its own:
#
#   <key>Resources/fr_CA.lproj</key>
#   <dict><key>symlink</key><string>fr.lproj</string></dict>
#
# The optional rule is anchored at ^Resources/.*\.lproj/ - with the trailing slash - so
# it reaches the files inside a localization directory but never the symlink itself, and
# a symlink entry carries no optional flag of its own.  Deleting one is therefore fatal,
# which is exactly what Typora's Sparkle.framework was failing on.  A real localization
# directory has no entry for itself at all, only entries for the files beneath it, so
# demanding that the path be absent from the seal separates the two cases without having
# to ask what is on disk.
lproj_removable() {
	local app="${1%/}" lproj="$2"
	local dir rel

	dir="$(dirname "${lproj}")"
	while [[ ${dir} == "${app}"/* || ${dir} == "${app}" ]]; do
		if [[ -f "${dir}/_CodeSignature/CodeResources" ]]; then
			rel="${lproj#"${dir}"/}"
			seal_covers_subtree "${dir}" "${rel}" || return 0
			[[ ${rel} == Resources/*.lproj ]] || return 1
			[[ "$(seal_lookup "${dir}" "${rel}")" == absent ]] || return 1
			seal_lproj_optional "${dir}" || return 1
		fi
		dir="$(dirname "${dir}")"
	done
	return 0
}

# Decide, for one directory of sibling .lproj folders, which to keep.
#
#   * a sibling matching the system language wins
#   * otherwise Base.lproj is the development-region fallback and is sufficient
#   * otherwise keep English
#   * otherwise keep everything - we cannot prove a fallback exists
#
# The decision is per directory because a bundle can hold several independent
# localization sets: Ghostty's Sparkle resources have Base plus 35 languages and no
# en.lproj at all, while two of AirBuddy's nested bundles ship only pt-BR.
strip_lproj_dir() {
	local parent="$1"
	shift
	local candidates=("$@")
	local child name norm size freed keep_mode
	local matched=false has_base=false has_english=false

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
		if is_pinned "${child}"; then
			verbose "kept ${child#"${APP}"/} (a symlink elsewhere in the bundle points into it)"
			continue
		fi

		if ! lproj_removable "${APP}" "${child}"; then
			verbose "kept ${child#"${APP}"/} (not covered by an optional seal rule)"
			continue
		fi

		size="$(du -sk "${child}" | cut -f1)"
		freed=$((freed + size * 1024))
		n_lang_removed=$((n_lang_removed + 1))
		verbose "$(action_prefix)remove ${child#"${APP}"/} (${size} KB)"
		[[ ${APPLY} == true ]] && stage_move "${child}"
	done

	bytes_lang=$((bytes_lang + freed))
	return 0
}

# A gettext catalogue is not a .lproj, so the optional rule the localization pruner
# leans on - ^Resources/.*\.lproj/ - does not reach it, and a bundle is free to seal
# Resources/locale/<lang>/LC_MESSAGES/*.mo by content.  Ghostty does exactly that.
# Missing the catalogue costs gettext nothing; missing it costs the seal everything.
gettext_removable() {
	local dir="$1" file

	# A symlinked catalogue directory is sealed as a symlink entry in its own right, and
	# such an entry is never optional.  `find` does not descend into it either, so the
	# file walk below would find nothing to object to and wave it through.
	[[ "$(seal_class "${APP}" "${dir}")" == own ]] || return 1

	while IFS= read -r -d '' file; do
		if [[ "$(seal_class "${APP}" "${file}")" == content ]]; then
			return 1
		fi
	done < <(find "${dir}" -type f -print0)
	return 0
}

# gettext catalogues: <root>/<lang>/LC_MESSAGES/*.mo
#
# Unlike .lproj there is no Base directory, and a missing catalogue is not a failure:
# gettext falls back to the msgid text compiled into the binary, which is the source
# language.  So when nothing matches, every catalogue is dead weight and all of them go.
strip_gettext_root() {
	local root="$1"
	shift
	local candidates=("$@")
	local child name norm size freed matched=false

	for child in "${root}"/*; do
		[[ -d "${child}/LC_MESSAGES" ]] || continue
		norm="$(normalize_lang "${child##*/}")"
		in_list "${norm}" "${candidates[@]}" && matched=true
	done

	freed=0
	for child in "${root}"/*; do
		[[ -d "${child}/LC_MESSAGES" ]] || continue
		name="${child##*/}"
		norm="$(normalize_lang "${name}")"

		[[ ${matched} == true ]] && in_list "${norm}" "${candidates[@]}" && continue

		if is_pinned "${child}"; then
			verbose "kept ${child#"${APP}"/} (a symlink elsewhere in the bundle points into it)"
			continue
		fi

		if ! gettext_removable "${child}"; then
			verbose "kept ${child#"${APP}"/} (sealed as a mandatory resource)"
			continue
		fi

		size="$(du -sk "${child}" | cut -f1)"
		freed=$((freed + size * 1024))
		n_lang_removed=$((n_lang_removed + 1))
		verbose "$(action_prefix)remove ${child#"${APP}"/} (${size} KB)"
		[[ ${APPLY} == true ]] && stage_move "${child}"
	done

	bytes_lang=$((bytes_lang + freed))
	return 0
}

strip_languages() {
	local app="${1%/}"
	local candidates=()
	local parent root line

	while IFS= read -r line; do
		[[ -n ${line} ]] && candidates+=("${line}")
	done < <(language_candidates "${SYS_LANG}")

	index_symlink_targets "${app}"

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

	return 0
}

#*****************************************************************************************
# verification
#
# seal_class is meant to be exhaustive, but codesign is the only authority that counts,
# so it gets the last word on every bundle.  Verifying once per bundle rather than once
# per file matters: a deep verify of Xcode is not something to run ten thousand times.
#*****************************************************************************************

verify_bundle() {
	codesign --verify --deep --strict "$1" >/dev/null 2>&1
}

# Ask codesign, put back exactly what it names, ask again.  Three rounds is generous -
# one is the normal case - and anything still unhappy after that gets a full rollback.
verify_and_rollback() {
	local app="$1" output path restored

	for _ in 1 2 3; do
		if output="$(codesign --verify --deep --strict --verbose=4 "${app}" 2>&1)"; then
			return 0
		fi

		restored=0
		while IFS= read -r path; do
			[[ -n ${path} ]] || continue
			if stage_restore "${path}"; then
				restored=$((restored + 1))
				n_thinned=$((n_thinned > 0 ? n_thinned - 1 : 0))
				n_thin_skipped=$((n_thin_skipped + 1))
				info "kept as it was: ${path#"${app}"/} (codesign seals it by content)"
			fi
		done < <(printf '%s\n' "${output}" |
			sed -n -E 's/^(file|resource) (modified|added|missing): //p')

		[[ ${restored} -gt 0 ]] || break
	done

	warn "${app##*/}: rolling back every change - codesign still refuses the bundle"
	stage_restore_all
	verify_bundle "${app}"
}

#*****************************************************************************************
# pre-flight guards
#*****************************************************************************************

# Apple's own apps are signed by the Software Signing authority and live behind SIP or in
# a cryptex.  Nothing can be changed about them, which matters once a directory scan
# starts handing us /Applications/Safari.app and friends.
#
# Both spellings are in use: apps shipped inside the OS say "macOS Software Signing",
# ones Apple ships separately - SF Symbols, Xcode's satellites - just "Software Signing".
#
# The output is captured rather than piped: `grep -q` stops reading at the first match,
# codesign takes a SIGPIPE for it, and under `set -o pipefail` a match would then read as
# a failure.
is_apple_signed() {
	local described

	described="$(codesign -dv --verbose=2 "$1" 2>&1 || true)"
	grep -qE '^Authority=(macOS )?Software Signing$' <<<"${described}"
}

is_restricted() {
	local listing

	[[ -L $1 ]] && return 0
	listing="$(ls -ldO "$1" 2>/dev/null || true)"
	grep -q 'restricted' <<<"${listing}"
}

# Rewriting a live executable fails outright with ETXTBSY, and a half rewritten one is a
# crash waiting to happen.  Leave running apps for the next run.
is_running() {
	pgrep -f "^${1%/}/Contents/MacOS/" >/dev/null 2>&1
}

# Why this bundle is being left alone, on stdout; non-zero when there is no reason to.
skip_reason() {
	local app="${1%/}"

	[[ -d "${app}/Contents" ]] || {
		printf 'not an app bundle'
		return 0
	}
	is_restricted "${app}" && {
		printf 'system protected'
		return 0
	}
	is_apple_signed "${app}" && {
		printf 'an Apple system app'
		return 0
	}
	is_running "${app}" && {
		printf 'currently running'
		return 0
	}

	# Anything already broken has to be left as it is: with a failing baseline there is
	# no way to tell our own damage from damage that was there first, so rollback would
	# have nothing to aim at.
	verify_bundle "${app}" || {
		printf 'seal already broken - run --check'
		return 0
	}

	return 1
}

#*****************************************************************************************
# per-app driver
#*****************************************************************************************

process_app() {
	local app before after reason record file

	app="$(real_path "${1%/}")"
	APP="${app}"

	n_thinned=0
	n_thin_skipped=0
	n_lang_removed=0
	n_lang_kept_intact=0
	bytes_thin=0
	bytes_lang=0

	before="$(du -sk "${app}" | cut -f1)"
	log ""
	log "${app##*/}  (${before} KB)"

	if reason="$(skip_reason "${app}")"; then
		info "skipped: ${reason}"
		return 0
	fi

	stage_reset

	if [[ ${DO_THIN} == true ]]; then
		while IFS= read -r -d '' record; do
			file="${record#*$'\t'}"
			if [[ ${record} == skip$'\t'* ]]; then
				verbose "left fat: ${file#"${APP}"/} (sealed as a resource)"
				continue
			fi
			[[ ${APPLY} == true ]] && stage_file "${file}"
			thin_binary "${file}" || true
			bytes_thin=$((bytes_thin + THIN_BYTES))
			n_thinned=$((n_thinned + 1))
		done < <(find_fat_binaries "${app}")
	fi

	[[ ${DO_LANG} == true ]] && strip_languages "${app}"

	if [[ ${APPLY} == true && $((n_thinned + n_lang_removed)) -gt 0 ]]; then
		if ! verify_and_rollback "${app}"; then
			err "${app##*/}: could not be returned to a verifying state - restore it from a backup"
			return 1
		fi
	fi

	after="$(du -sk "${app}" | cut -f1)"

	info "binaries thinned      : ${n_thinned}"
	[[ ${n_thin_skipped} -gt 0 ]] && info "binaries left fat     : ${n_thin_skipped} (sealed by content)"
	info "localizations removed : ${n_lang_removed}"
	[[ ${n_lang_kept_intact} -gt 0 ]] && info "localizations kept    : ${n_lang_kept_intact} set(s) with no safe fallback"
	if [[ ${APPLY} == true ]]; then
		info "size                  : ${before} KB -> ${after} KB"
	else
		info "reclaimable           : $(((bytes_thin + bytes_lang) / 1024)) KB (intel $((bytes_thin / 1024)) KB, lang $((bytes_lang / 1024)) KB)"
	fi

	total_apps=$((total_apps + 1))
	total_bytes=$((total_bytes + bytes_thin + bytes_lang))
	return 0
}

#*****************************************************************************************
# the damage report
#
# A stripping tool that thins whatever it finds, rather than only what the seal permits,
# leaves a bundle that no longer verifies.  Three apps on this machine arrived that way.
# --check names them and says which kind of damage it is; --repair says what to do,
# which for an App Store app is always a reinstall - an ad-hoc re-sign would drop
# com.apple.application-identifier and take the sandbox container, keychain and iCloud
# access with it.
#*****************************************************************************************

is_mach_o() {
	local kind

	kind="$(file -b "$1" 2>/dev/null || true)"
	[[ ${kind} == Mach-O* ]]
}

# What codesign objects to, one "verb<TAB>path" line each.  The verb has to survive:
# a path codesign calls missing is not on disk any more, so asking `file` what kind it
# was answers "not Mach-O" for every one of them - which is how a localization deleted
# out from under its seal gets filed as damage of some other kind entirely.
damaged_paths() {
	local app="$1" output

	output="$(codesign --verify --deep --strict --verbose=4 "${app}" 2>&1)" && return 1
	printf '%s\n' "${output}" | sed -n -E 's/^(file|resource) (modified|added|missing): /\2\t/p'
}

# Non-zero when the bundle is healthy.
damage_report() {
	local app="${1%/}" line verb path
	local count=0 machos=0 gone=0 first=""

	while IFS= read -r line; do
		[[ -n ${line} ]] || continue
		verb="${line%%$'\t'*}"
		path="${line#*$'\t'}"
		count=$((count + 1))
		[[ -z ${first} ]] && first="${path}"
		if [[ ${verb} == missing ]]; then
			gone=$((gone + 1))
		elif is_mach_o "${path}"; then
			machos=$((machos + 1))
		fi
	done < <(damaged_paths "${app}")

	[[ ${count} -gt 0 ]] || return 1

	if [[ ${gone} -eq ${count} ]]; then
		info "${count} sealed resource(s) deleted - a localization strip that ignored"
		info "the seal"
	elif [[ ${machos} -eq ${count} ]]; then
		info "${count} Mach-O file(s) were thinned despite being sealed by content"
	elif [[ $((gone + machos)) -gt 0 ]]; then
		info "${count} sealed item(s) altered: ${machos} Mach-O thinned, ${gone} deleted,"
		info "$((count - gone - machos)) otherwise rewritten - part of this is a strip"
		info "that ignored the seal"
	else
		info "${count} sealed file(s) altered, none of them Mach-O - this is not"
		info "stripping damage; something else rewrote them"
	fi

	info "first: ${first#"${app}"/}"
	if [[ ${VERBOSE} == true ]]; then
		while IFS= read -r line; do
			[[ -n ${line} ]] || continue
			verb="${line%%$'\t'*}"
			path="${line#*$'\t'}"
			verbose "${verb}: ${path#"${app}"/}"
		done < <(damaged_paths "${app}")
	fi

	return 0
}

repair_advice() {
	local app="${1%/}" adam

	if [[ ! -d "${app}/Contents/_MASReceipt" ]]; then
		info "repair: reinstall from the vendor - re-download and replace the bundle"
		return 0
	fi

	adam="$(mdls -raw -name kMDItemAppStoreAdamID "${app}" 2>/dev/null || true)"
	info "repair: App Store app - delete it and reinstall.  Re-signing is not an option;"
	info "        an ad-hoc signature drops the identifiers the sandbox depends on."
	if [[ -n ${adam} && ${adam} != "(null)" ]]; then
		if command -v mas >/dev/null 2>&1; then
			info "        mas install ${adam}"
		else
			info "        open \"macappstore://apps.apple.com/app/id${adam}\""
			info "        (or brew install mas, then mas install ${adam})"
		fi
	else
		info "        no App Store id recorded - reinstall from the Purchased list"
	fi
	return 0
}

check_app() {
	local app="${1%/}" report

	[[ -d "${app}/Contents" ]] || return 0
	is_restricted "${app}" && return 0
	is_apple_signed "${app}" && return 0

	report="$(damage_report "${app}")" || return 0

	log ""
	log "${app##*/}"
	printf '%s\n' "${report}"
	[[ ${MODE} == "repair" ]] && repair_advice "${app}"

	total_apps=$((total_apps + 1))
	return 0
}

#*****************************************************************************************
# entry point
#*****************************************************************************************

# With no bundle named, sweep the applications directory.  -prune stops find descending
# into a bundle it has already matched, so a helper app nested inside another app is not
# reported as a target of its own; it is handled as part of its container.
collect_default_targets() {
	find "${DEFAULT_SCAN_ROOT}" -maxdepth 2 -name '*.app' -prune -print 2>/dev/null | sort
}

# Bundles under /Applications are usually root owned, but one that arrived by drag
# install is not, and one in a user directory never is.  Only escalate when something
# actually needs it.
needs_root() {
	local app

	for app in "${TARGETS[@]}"; do
		app="${app%/}"
		[[ -d ${app} ]] || continue
		[[ -w ${app} && -w "${app}/Contents" ]] || return 0
	done
	return 1
}

# Warm sudo's credential timestamp so the re-exec below never has to prompt.
#
# get_sudo_password returns an empty string when sudo is already validated, and otherwise
# the password from the login keychain, falling back to a prompt.  It does not validate a
# keychain sourced password itself, so feed it to sudo here.  Priming this way also means
# the script works with no controlling terminal, where a bare `sudo` would just fail.
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

parse_args() {
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
			--check)
				MODE="check"
				shift
				;;
			--repair)
				MODE="repair"
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
}

main() {
	local orig_args=("$@")
	local rc=0 app scanned=false

	parse_args "$@"

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

	# Resolve the language while still running as the invoking user - root has different
	# preferences - and carry the answer across the sudo boundary explicitly.
	[[ -z ${STRIP_APP_LANG:-} ]] && STRIP_APP_LANG="$(detect_system_language)"
	SYS_LANG="${STRIP_APP_LANG}"
	export STRIP_APP_LANG

	if [[ ${MODE} == "strip" && ${APPLY} == true && ${EUID} -ne 0 ]] && needs_root; then
		log "re-running under sudo to modify root-owned bundles..."
		if ! prime_sudo; then
			err "could not obtain sudo privileges"
			exit 1
		fi
		exec sudo --preserve-env=STRIP_APP_LANG -- "$0" "${orig_args[@]}"
	fi

	trap cleanup EXIT
	WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/strip-app.XXXXXX")"

	if [[ ${MODE} != "strip" ]]; then
		log "checking ${#TARGETS[@]} bundle(s) for a broken seal"
		for app in "${TARGETS[@]}"; do
			check_app "${app}" || rc=1
		done
		log ""
		if [[ ${total_apps} -eq 0 ]]; then
			log "every bundle verifies"
		else
			log "${total_apps} damaged bundle(s)"
			[[ ${MODE} == "check" ]] && log "run again with --repair for the remedy"
		fi
		return "${rc}"
	fi

	log "system language: ${SYS_LANG}"
	[[ ${scanned} == true ]] &&
		log "scanning ${DEFAULT_SCAN_ROOT}: ${#TARGETS[@]} app bundles"
	[[ ${APPLY} == true ]] || log "DRY RUN - nothing will be modified"

	for app in "${TARGETS[@]}"; do
		process_app "${app}" || rc=1
	done

	if [[ ${#TARGETS[@]} -gt 1 ]]; then
		log ""
		if [[ ${APPLY} == true ]]; then
			log "total: ${total_apps} apps processed, $((total_bytes / 1024)) KB reclaimed"
		else
			log "total: ${total_apps} apps scanned, $((total_bytes / 1024)) KB reclaimable"
		fi
	fi

	[[ ${APPLY} == true ]] &&
		log "note: an app update replaces the bundle - re-run this afterwards."

	return "${rc}"
}

if [[ -z ${STRIP_APP_LIB_ONLY:-} ]]; then
	main "$@"
fi
