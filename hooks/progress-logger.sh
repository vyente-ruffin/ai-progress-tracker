#!/bin/bash
# ================================================================
# progress-logger.sh — Automatic Progress DB Logger
# ================================================================
# On session end, reads the activity JSONL, aggregates what was done,
# and INSERTs a summary row into ~/.ai/progress.db.
#
# TRIGGER: sessionEnd (Copilot CLI), Stop (Claude Code)
# INPUT: JSON with timestamp, cwd, reason (complete/error/abort/timeout/user_exit)
# OUTPUT: One row inserted into tasks table in progress.db
#
# Per official GitHub Copilot CLI hooks docs:
# https://docs.github.com/en/copilot/reference/hooks-configuration
#
# Adapted from yurukusa/claude-code-hooks proof-log-session.sh (MIT)
# Modified to write to SQLite instead of markdown.
# ================================================================

ACTIVITY_LOG="$HOME/.ai/hooks/activity-log.jsonl"
DB_FILE="$HOME/.ai/progress.db"

# -- Read hook input JSON from stdin --
INPUT=$(cat)

# -- Extract session end reason (complete, error, abort, etc.) --
SESSION_REASON=$(echo "$INPUT" | jq -r '.reason // "unknown"' 2>/dev/null)

# -- Resolve session start timestamp from marker file --
SESSION_ID="${PPID:-$$}"
SESSION_START_FILE="/tmp/ai-session-start-ts-${SESSION_ID}"

SESSION_START_EPOCH=0
if [[ -f "$SESSION_START_FILE" ]]; then
    SESSION_START_EPOCH=$(cat "$SESSION_START_FILE" 2>/dev/null || echo 0)
fi

NOW_EPOCH=$(date +%s)

# -- Skip if no start marker or session was under 1 minute --
if [[ "$SESSION_START_EPOCH" -le 0 ]]; then
    exit 0
fi
DURATION_MIN=$(( (NOW_EPOCH - SESSION_START_EPOCH) / 60 ))
if [[ "$DURATION_MIN" -eq 0 ]]; then
    rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true
    exit 0
fi

# -- Skip if DB doesn't exist --
if [[ ! -f "$DB_FILE" ]]; then
    rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true
    exit 0
fi

CWD="$(pwd)"

# -- Find project_id by matching cwd against registered project folders --
PROJECT_ID=$(sqlite3 "$DB_FILE" "SELECT id FROM projects WHERE '$CWD' LIKE folder || '%' ORDER BY length(folder) DESC LIMIT 1;" 2>/dev/null)

# -- Skip if project not registered in progress.db --
if [[ -z "$PROJECT_ID" ]]; then
    rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true
    exit 0
fi

# -- Aggregate activity log entries from this session --
# Allow a 5-minute buffer before session start to catch early writes
FILTER_START=$((SESSION_START_EPOCH > 300 ? SESSION_START_EPOCH - 300 : 0))

SUMMARY=$(python3 - "$ACTIVITY_LOG" "$FILTER_START" 2>/dev/null <<'PY'
import json, sys, os
from datetime import datetime
import time

activity_log = sys.argv[1]
session_start = int(sys.argv[2])

files_changed = {}
total_add = 0
total_del = 0

# Default to last 30 minutes if no start marker
if session_start <= 0:
    session_start = int(time.time()) - 1800

try:
    with open(activity_log, 'r') as f:
        for line in f:
            try:
                entry = json.loads(line.strip())
                ts_str = entry.get('ts', '')
                if ts_str:
                    dt = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
                    entry_epoch = int(dt.timestamp())
                else:
                    continue
                # Only include entries from this session
                if entry_epoch >= session_start:
                    path = entry.get('path', '')
                    add = entry.get('add', 0)
                    dele = entry.get('del', 0)
                    if path:
                        basename = os.path.basename(path)
                        if path in files_changed:
                            files_changed[path]['add'] += add
                            files_changed[path]['del'] += dele
                            files_changed[path]['count'] += 1
                        else:
                            files_changed[path] = {'add': add, 'del': dele, 'name': basename, 'count': 1}
                        total_add += add
                        total_del += dele
            except (json.JSONDecodeError, ValueError):
                pass
except FileNotFoundError:
    pass

# Exit with no output if nothing was changed — prevents empty task entries
if not files_changed:
    sys.exit(0)

# Build a human-readable summary from the top 5 most-changed files
parts = []
items = sorted(files_changed.items(), key=lambda x: x[1]['add'] + x[1]['del'], reverse=True)[:5]
for path, info in items:
    parts.append(f"{info['name']} (+{info['add']}/-{info['del']})")

task_name = f"{len(files_changed)} files changed (+{total_add}/-{total_del})"
description = ", ".join(parts)

# Output format: task_name|||description (parsed by the caller)
print(f"{task_name}|||{description}")
PY
) || SUMMARY=""

# -- Skip if no changes were logged this session --
if [[ -z "$SUMMARY" ]]; then
    rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true
    exit 0
fi

# -- Parse the summary into task_name and description --
TASK_NAME=$(echo "$SUMMARY" | sed 's/|||.*//')
DESCRIPTION=$(echo "$SUMMARY" | sed 's/.*|||//')

# -- Format timestamp as MM/DD/YYYY hh:mm AM/PM PST (project convention) --
TIMESTAMP=$(TZ='America/Los_Angeles' date '+%m/%d/%Y %I:%M %p PST')

# -- Insert summary task into progress.db --
sqlite3 "$DB_FILE" "INSERT INTO tasks (project_id, timestamp, task_name, description, status, takeaways, gotchas)
VALUES ('$PROJECT_ID', '$TIMESTAMP', '$TASK_NAME', '$DESCRIPTION', 'done', '', '');" 2>/dev/null || true

# -- Cleanup: remove session marker and clear processed activity log --
rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true
: > "$ACTIVITY_LOG" 2>/dev/null || true

exit 0
