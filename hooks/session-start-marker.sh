#!/bin/bash
# ================================================================
# session-start-marker.sh — Session Start Time Recorder
# ================================================================
# Records session start timestamp when triggered by the sessionStart
# hook event. Uses the timestamp from the hook input JSON rather than
# relying on a /tmp marker file.
#
# TRIGGER: sessionStart
# INPUT: JSON with timestamp, cwd, source, initialPrompt
# OUTPUT: Writes epoch timestamp to /tmp/ai-session-start-ts-{PID}
#
# Per official GitHub Copilot CLI hooks docs:
# https://docs.github.com/en/copilot/reference/hooks-configuration
#
# Adapted from yurukusa/claude-code-hooks (MIT)
# ================================================================

# -- Read the JSON input from stdin (Copilot CLI pipes hook context) --
INPUT=$(cat)

# -- Use a stable session ID based on parent process --
SESSION_ID="${PPID:-$$}"
START_FILE="/tmp/ai-session-start-ts-${SESSION_ID}"

# -- Skip if we already recorded a start for this session --
if [[ -f "$START_FILE" ]]; then
    exit 0
fi

# -- Extract timestamp from hook input JSON (milliseconds → seconds) --
# Falls back to current epoch if jq fails or input is empty
TIMESTAMP_MS=$(echo "$INPUT" | jq -r '.timestamp // empty' 2>/dev/null)
if [[ -n "$TIMESTAMP_MS" ]]; then
    # Convert milliseconds to seconds
    echo $(( TIMESTAMP_MS / 1000 )) > "$START_FILE"
else
    # Fallback: use current time if no timestamp in input
    date +%s > "$START_FILE"
fi

exit 0
