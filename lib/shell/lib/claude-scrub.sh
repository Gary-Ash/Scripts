#!/usr/bin/env bash
#*****************************************************************************************
# claude-scrub.sh
#
# The lists of Claude Code state that ocd.sh and update-dots.sh strip, kept in one place
# so the two cannot drift apart.  Three groups are exported:
#
#   CLAUDE_JUNK_PATHS           caches, logs and transcripts under $HOME, named relative
#                               to it so a caller can delete them or exclude them from a
#                               copy.  ocd.sh removes them, update-dots.sh keeps them out
#                               of the dotfiles repository.
#
#   CLAUDE_SCRUB_KEYS           .claude.json keys holding usage history, counters and
#                               account-scoped caches.  Safe to drop from a live install -
#                               Claude Code refetches or recreates every one of them.
#
#   CLAUDE_SCRUB_KEYS_IDENTITY  keys naming the machine or the person using it, plus the
#                               onboarding and migration flags.  Only ever stripped from a
#                               copy leaving the machine - deleting these from a live
#                               install logs the user out and replays onboarding.
#
# claude_scrub_filter builds the matching jq program.  Called with no argument it scrubs
# in place; called with "identity" it also removes the identifying keys.
#
# This file is sourced, so it deliberately does not set shell options - doing so would
# change the behaviour of whatever script pulled it in.
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Sep-2026  4:42pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# transcripts, caches and logs written under $HOME, relative to it
#*****************************************************************************************
# shellcheck disable=SC2034  # consumed by the scripts that source this file
readonly CLAUDE_JUNK_PATHS=(
	".claude/cache"
	".claude/data"
	".claude/backups"
	".claude/image-cache"
	".claude/session-env"
	".claude/plans"
	".claude/projects"
	".claude/tasks"
	".claude/todos"
	".claude/debug"
	".claude/statsig"
	".claude/downloads"
	".claude/telemetry"
	".claude/plugins/blocklist.json"
	".claude/shell-snapshots"
	".claude/file-history"
	".claude/history.jsonl"
	".claude/stats-cache.json"
	".claude/mcp-needs-auth-cache.json"
	".claude/paste-cache"
	".claude/sessions"
	".claude/.last-cleanup"
	".claude/.last-update-result.json"
	".claude/plugins/cache"
	".claude/plugins/data"
	".claude/plugins/.last_inuse_sweep"
)

#*****************************************************************************************
# .claude.json keys safe to drop from a live install
#*****************************************************************************************
readonly CLAUDE_SCRUB_KEYS=(
	"projects"
	"githubRepoPaths"
	"replBridgePlaceholders"
	"opusProMigrationTimestamp"
	"changelogLastFetched"
	"numStartups"
	"btwUseCount"
	"promptQueueUseCount"
	"fullscreenUpsellSeenCount"
	"passesUpsellSeenCount"
	"pushNotifUpsellSeenCount"
	"remoteControlUpsellSeenCount"
	"rcLongTurnNudgeSeenCount"
	"rcLongTurnNudgeSeenKey"
	"lspRecommendationIgnoredCount"
	"birthdayHatAnimationCount"
	"tipsHistory"
	"tipLifetimeShownCounts"
	"lastShownEmergencyTip"
	"seenNotifications"
	"announcementImpressions"
	"feedbackSurveyState"
	"closedIssuesLastChecked"
	"routineFiredWatermark"
	"pluginUsage"
	"pluginUsageLspGraceAppliedIds"
	"clientDataCacheSlots"
	"cachedExperimentData"
	"cachedExperimentFeatures"
	"cachedGrowthBookFeatures"
	"cachedGrowthBookFeaturesAt"
	"autoCompactWindowsCache"
	"modelAccessCache"
	"orgModelDefaultCache"
	"additionalModelOptionsCache"
	"additionalModelCostsCache"
	"overageCreditGrantCache"
	"passesEligibilityCache"
	"passesLastSeenRemaining"
	"cachedChromeExtensionInstalled"
	"cachedExtraUsageDisabledReason"
)

#*****************************************************************************************
# .claude.json keys stripped only from a copy that leaves the machine
#*****************************************************************************************
readonly CLAUDE_SCRUB_KEYS_IDENTITY=(
	"userID"
	"oauthAccount"
	"anonymousId"
	"machineID"
	"firstStartTime"
	"claudeCodeFirstTokenDate"
	"lastOnboardingVersion"
	"lastReleaseNotesSeen"
	"lastClawdEntranceVersion"
	"hasCompletedOnboarding"
	"hasShownOpus45Notice"
	"hasShownOpus46Notice"
	"hasSeenAutoDefaultNotice"
	"hasSeenAutoModeEntryWarning"
	"hasVisitedExtraUsage"
	"hasVisitedPasses"
	"claudeAiMcpEverConnected"
	"effortCalloutDismissed"
	"effortCalloutV2Dismissed"
	"showSpinnerTree"
	"penguinModeOrgEnabled"
	"officialMarketplaceAutoInstallAttempted"
	"officialMarketplaceAutoInstalled"
	"autoUpdatesProtectedForNative"
	"deepLinkTerminal"
	"migrationVersion"
	"sonnet45MigrationComplete"
	"opus45MigrationComplete"
	"opusProMigrationComplete"
	"thinkingMigrationComplete"
	"sonnet1m45MigrationComplete"
)

#*****************************************************************************************
# object-valued caches emptied rather than deleted so the key keeps its type
#*****************************************************************************************
readonly CLAUDE_SCRUB_EMPTY_KEYS=(
	"s1mAccessCache"
	"groveConfigCache"
	"skillUsage"
)

#*****************************************************************************************
# build the jq program that scrubs .claude.json - pass "identity" to also strip the keys
# naming the machine and its owner
#*****************************************************************************************
claude_scrub_filter() {
	local keys=("${CLAUDE_SCRUB_KEYS[@]}")
	local filter=""
	local key

	if [[ ${1:-} == "identity" ]]; then
		keys+=("${CLAUDE_SCRUB_KEYS_IDENTITY[@]}")
	fi

	for key in "${keys[@]}"; do
		filter+="${filter:+, }.$key"
	done
	filter="del($filter)"

	for key in "${CLAUDE_SCRUB_EMPTY_KEYS[@]}"; do
		filter+=" | .$key = {}"
	done

	echo "$filter"
}
