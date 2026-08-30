#!/usr/bin/env bash
#*****************************************************************************************
# log.sh
#
# Diagnostic output routines shared by the scripts in /opt/geedbla/scripts.  Sourcing this
# file gives a script a severity ladder - log_line, log_info, log_verbose, log_warn,
# log_error and log_die - plus log_color for output whose colour carries the meaning.
#
# The caller decides the shape of a line by assigning the LOG_* variables below; nothing
# here reads the environment or guesses.  Warnings, errors and fatals always go to stderr;
# everything else goes to the descriptor named by LOG_STREAM.
#
# This file is sourced, so it deliberately does not set shell options - doing so would
# change the behaviour of whatever script pulled it in.  Every assignment is conditional,
# so sourcing it more than once is harmless.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Sep-2026  4:42pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# caller configuration - assign after sourcing to suit the script
#*****************************************************************************************
LOG_PREFIX="${LOG_PREFIX:-}"                 # leading "<name>: " stamped on every line
LOG_STREAM="${LOG_STREAM:-1}"                # descriptor for log_line/log_info/log_verbose
LOG_VERBOSE="${LOG_VERBOSE:-false}"          # log_verbose stays silent until this is true
LOG_HOOK="${LOG_HOOK:-}"                     # function run before each severity line
LOG_INDENT="${LOG_INDENT:-}"                 # indent applied to log_info
LOG_INDENT_VERBOSE="${LOG_INDENT_VERBOSE:-}" # indent applied to log_verbose
LOG_FAILURES="${LOG_FAILURES:-0}"            # running count of log_error calls

LOG_GREEN=$'\033[0;32m'
LOG_YELLOW=$'\033[0;33m'
LOG_RED=$'\033[0;31m'
LOG_RESET=$'\033[0m'

#*****************************************************************************************
# compose and print one line - the single place that knows the shape of a message
#
# Colour is passed in rather than baked into the message so that this routine can drop it
# when the destination is not a terminal; a redirected or piped run gets clean text
# instead of embedded escape sequences.
#*****************************************************************************************
_log_emit() {
	local stream="$1" indent="$2" label="$3" color="$4"
	shift 4

	if [[ -n ${color} && -t ${stream} ]]; then
		printf '%s%s%s%s%s%s\n' "${indent}" "${LOG_PREFIX:+${LOG_PREFIX}: }" "${label}" "${color}" "$*" "${LOG_RESET}" >&"${stream}"
	else
		printf '%s%s%s%s\n' "${indent}" "${LOG_PREFIX:+${LOG_PREFIX}: }" "${label}" "$*" >&"${stream}"
	fi
}

#*****************************************************************************************
# run the caller's pre-output hook, if it set one
#
# strip-app.sh holds its banner back until an app actually has news to report, and uses
# this to flush it.  The explicit success keeps a script running under 'set -e' alive when
# no hook is installed.
#*****************************************************************************************
_log_hook() {
	[[ -n ${LOG_HOOK} ]] && "${LOG_HOOK}"
	return 0
}

#*****************************************************************************************
# a bare line, carrying no severity and firing no hook
#*****************************************************************************************
log_line() {
	_log_emit "${LOG_STREAM}" "" "" "" "$@"
}

#*****************************************************************************************
# an informational line
#*****************************************************************************************
log_info() {
	_log_hook
	_log_emit "${LOG_STREAM}" "${LOG_INDENT}" "" "" "$@"
}

#*****************************************************************************************
# a line printed only when the caller has asked for detail
#*****************************************************************************************
log_verbose() {
	[[ ${LOG_VERBOSE} == true ]] || return 0
	_log_hook
	_log_emit "${LOG_STREAM}" "${LOG_INDENT_VERBOSE}" "" "" "$@"
}

#*****************************************************************************************
# a warning - the run continues
#*****************************************************************************************
log_warn() {
	_log_hook
	_log_emit 2 "" "warning: " "" "$@"
}

#*****************************************************************************************
# an error - the run continues, but the failure is counted in LOG_FAILURES
#*****************************************************************************************
log_error() {
	LOG_FAILURES=$((LOG_FAILURES + 1))
	_log_hook
	_log_emit 2 "" "error: " "" "$@"
}

#*****************************************************************************************
# an unrecoverable error - reports and leaves
#*****************************************************************************************
log_die() {
	_log_hook
	_log_emit 2 "" "fatal: " "" "$@"
	exit 1
}

#*****************************************************************************************
# a line whose colour is the message - progress, good news, bad news
#
# The colour survives only as far as a terminal; see _log_emit.
#*****************************************************************************************
log_color() {
	local color="$1"
	shift

	_log_emit "${LOG_STREAM}" "" "" "${color}" "$@"
}
