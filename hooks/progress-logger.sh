#!/bin/bash
# ================================================================
# progress-logger.sh — Automatic Progress DB Logger
# ================================================================
# On agent stop, reads the activity JSONL, aggregates what was done,
# and INSERTs a summary row into ~/.ai/progress.db.
#
# TRIGGER: Stop (Claude Code), agentStop (Copilot CLI)
# MATCHER: "" (empty)
#
# Adapted from yurukusa/claude-code-hooks proof-log-session.sh (MIT)
# Modified to write to SQLite instead of markdown.
# ================================================================

ACTIVITY_LOG="$HOME/.ai/hooks/activity-log.jsonl"
DB_FILE="$HOME/.ai/progress.db"

# Resolve session start timestamp
SESSION_ID="${PPID:-$$}"
SESSION_START_FILE="/tmp/ai-session-start-ts-${SESSION_ID}"

SESSION_START_EPOCH=0
if [[ -f "$SESSION_START_FILE" ]]; then
    SESSION_START_EPOCH=$(cat "$SESSION_START_FILE" 2>/dev/null || echo 0)
fi

NOW_EPOCH=$(date +%s)

# Skip if no start marker or 0-minute session
if [[ "$SESSION_START_EPOCH" -le 0 ]]; then
    exit 0
fi
DURATION_MIN=$(( (NOW_EPOCH - SESSION_START_EPOCH) / 60 ))
if [[ "$DURATION_MIN" -eq 0 ]]; then
    rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true
    exit 0
fi

# Skip if DB doesn't exist
if [[ ! -f "$DB_FILE" ]]; then
    rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true
    exit 0
fi

CWD="$(pwd)"

# Find project_id from cwd
PROJECT_ID=$(sqlite3 "$DB_FILE" "SELECT id FROM projects WHERE '$CWD' LIKE folder || '%' ORDER BY length(folder) DESC LIMIT 1;" 2>/dev/null)

# Skip if project not registered
if [[ -z "$PROJECT_ID" ]]; then
    rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true
    exit 0
fi

# Aggregate activity log for this session
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

if not files_changed:
    sys.exit(0)

parts = []
items = sorted(files_changed.items(), key=lambda x: x[1]['add'] + x[1]['del'], reverse=True)[:5]
for path, info in items:
    parts.append(f"{info['name']} (+{info['add']}/-{info['del']})")

task_name = f"{len(files_changed)} files changed (+{total_add}/-{total_del})"
description = ", ".join(parts)

print(f"{task_name}|||{description}")
PY
) || SUMMARY=""

# Skip if no changes
if [[ -z "$SUMMARY" ]]; then
    rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true
    exit 0
fi

TASK_NAME=$(echo "$SUMMARY" | cut -d'|' -f1)
DESCRIPTION=$(echo "$SUMMARY" | cut -d'|' -f4)

# Format timestamp as MM/DD/YYYY hh:mm AM/PM PST
TIMESTAMP=$(TZ='America/Los_Angeles' date '+%m/%d/%Y %I:%M %p PST')

# Insert into progress.db
sqlite3 "$DB_FILE" "INSERT INTO tasks (project_id, timestamp, task_name, description, status, takeaways, gotchas)
VALUES ('$PROJECT_ID', '$TIMESTAMP', '$TASK_NAME', '$DESCRIPTION', 'done', '', '');" 2>/dev/null || true

# Cleanup
rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true

# Clear activity log entries that were processed
> "$ACTIVITY_LOG" 2>/dev/null || true

exit 0
