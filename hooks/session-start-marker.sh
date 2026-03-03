#!/bin/bash
# ================================================================
# session-start-marker.sh — Session Start Time Recorder
# ================================================================
# Records timestamp on first tool invocation of a session.
# Used by progress-logger.sh to calculate session duration
# and filter activity logs to the current session.
#
# TRIGGER: PostToolUse (all tools)
# MATCHER: "" (every tool invocation)
#
# Adapted from yurukusa/claude-code-hooks (MIT)
# ================================================================

SESSION_ID="${PPID:-$$}"
START_FILE="/tmp/ai-session-start-ts-${SESSION_ID}"

if [[ -f "$START_FILE" ]]; then
    exit 0
fi

date +%s > "$START_FILE"
exit 0
