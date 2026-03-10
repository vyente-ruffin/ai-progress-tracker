#!/bin/bash
# ================================================================
# progress-logger.sh — Automatic Progress DB Logger
# ================================================================
# On session end, reads session state (summary, checkpoints) and
# activity log to build a rich task entry in progress.db.
#
# The hook is the ONLY writer to the DB. Agents never INSERT directly.
# This ensures deterministic project_id resolution (cwd → folder match)
# and prevents misattribution.
#
# Data sources (in priority order):
#   1. Copilot CLI session state (~/.copilot/session-state/{id}/)
#      - workspace.yaml → summary field
#      - checkpoints/*.md → overview block with full context
#   2. Activity log (~/.ai/hooks/activity-log.jsonl)
#      - File change details (supplementary)
#
# TRIGGER: sessionEnd (Copilot CLI), Stop (Claude Code)
# INPUT: JSON with timestamp, cwd, reason
# OUTPUT: One row inserted into tasks table in progress.db
# ================================================================

ACTIVITY_LOG="$HOME/.ai/hooks/activity-log.jsonl"
DB_FILE="$HOME/.ai/progress.db"
SESSION_STATE_DIR="$HOME/.copilot/session-state"

# -- Read hook input JSON from stdin --
INPUT=$(cat)

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
# This is the registration gate: unregistered folders produce no output
PROJECT_ID=$(sqlite3 "$DB_FILE" "SELECT id FROM projects WHERE '$CWD' LIKE folder || '%' ORDER BY length(folder) DESC LIMIT 1;" 2>/dev/null)

# -- Skip if project not registered in progress.db --
if [[ -z "$PROJECT_ID" ]]; then
    rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true
    exit 0
fi

# -- Extract rich context from Copilot CLI session state --
# Find the most recently updated session whose cwd matches ours
RESULT=$(python3 - "$SESSION_STATE_DIR" "$CWD" "$ACTIVITY_LOG" "$SESSION_START_EPOCH" 2>/dev/null <<'PY'
import json, sys, os, glob
from datetime import datetime
import time
import re

session_dir = sys.argv[1]
target_cwd = sys.argv[2]
activity_log = sys.argv[3]
session_start = int(sys.argv[4])

task_name = ""
description = ""
takeaways = ""
gotchas = ""

# ---------------------------------------------------------------
# Step 1: Find matching Copilot CLI session by cwd
# Look for the most recently modified workspace.yaml that matches
# ---------------------------------------------------------------
best_session = None
best_mtime = 0

if os.path.isdir(session_dir):
    for sid in os.listdir(session_dir):
        ws_path = os.path.join(session_dir, sid, "workspace.yaml")
        if os.path.isfile(ws_path):
            try:
                with open(ws_path, 'r') as f:
                    content = f.read()
                # Parse cwd from workspace.yaml (simple YAML — just grep)
                for line in content.splitlines():
                    if line.startswith("cwd:"):
                        session_cwd = line.split("cwd:", 1)[1].strip()
                        if session_cwd == target_cwd:
                            mtime = os.path.getmtime(ws_path)
                            if mtime > best_mtime:
                                best_mtime = mtime
                                best_session = os.path.join(session_dir, sid)
                        break
            except Exception:
                pass

# ---------------------------------------------------------------
# Step 2: Extract summary and checkpoint data from best session
# ---------------------------------------------------------------
if best_session:
    ws_path = os.path.join(best_session, "workspace.yaml")
    try:
        with open(ws_path, 'r') as f:
            for line in f:
                if line.startswith("summary:"):
                    task_name = line.split("summary:", 1)[1].strip()
                    # Remove quotes if present
                    task_name = task_name.strip('"').strip("'")
                    break
    except Exception:
        pass

    # Find the latest numbered checkpoint for the overview
    # Skip index.md — it's a table of contents, not a checkpoint
    cp_dir = os.path.join(best_session, "checkpoints")
    if os.path.isdir(cp_dir):
        checkpoints = sorted([
            f for f in glob.glob(os.path.join(cp_dir, "*.md"))
            if os.path.basename(f) != "index.md"
        ])
        if checkpoints:
            latest_cp = checkpoints[-1]
            try:
                with open(latest_cp, 'r') as f:
                    cp_content = f.read()

                # Extract <overview> block
                overview_match = re.search(r'<overview>(.*?)</overview>', cp_content, re.DOTALL)
                if overview_match:
                    description = overview_match.group(1).strip()
                    # Truncate to 500 chars for DB
                    if len(description) > 500:
                        description = description[:497] + "..."

                # Look for takeaways/gotchas patterns in checkpoint
                # Common patterns: "learned", "discovered", "gotcha", "issue", "bug"
                lines = cp_content.split('\n')
                takeaway_lines = []
                gotcha_lines = []
                for line in lines:
                    lower = line.lower().strip()
                    if any(w in lower for w in ['learned', 'takeaway', 'discovered', 'key insight']):
                        takeaway_lines.append(line.strip().lstrip('- '))
                    if any(w in lower for w in ['gotcha', 'bug', 'broke', 'wrong', 'issue', 'root cause']):
                        gotcha_lines.append(line.strip().lstrip('- '))

                if takeaway_lines:
                    takeaways = "; ".join(takeaway_lines[:3])
                    if len(takeaways) > 500:
                        takeaways = takeaways[:497] + "..."
                if gotcha_lines:
                    gotchas = "; ".join(gotcha_lines[:3])
                    if len(gotchas) > 500:
                        gotchas = gotchas[:497] + "..."

            except Exception:
                pass

# ---------------------------------------------------------------
# Step 3: Supplement with activity log file changes
# ---------------------------------------------------------------
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
                        else:
                            files_changed[path] = {'add': add, 'del': dele, 'name': basename}
                        total_add += add
                        total_del += dele
            except (json.JSONDecodeError, ValueError):
                pass
except FileNotFoundError:
    pass

# ---------------------------------------------------------------
# Step 4: Build the output
# ---------------------------------------------------------------

# If we got a session summary, use it as task_name
# If not, fall back to file change summary
if not task_name and files_changed:
    task_name = f"{len(files_changed)} files changed (+{total_add}/-{total_del})"

# If we got a checkpoint overview, use it as description
# Append file changes as supplementary detail
if not description and files_changed:
    parts = []
    items = sorted(files_changed.items(), key=lambda x: x[1]['add'] + x[1]['del'], reverse=True)[:5]
    for path, info in items:
        parts.append(f"{info['name']} (+{info['add']}/-{info['del']})")
    description = ", ".join(parts)
elif description and files_changed:
    # Append brief file summary to the checkpoint overview
    file_summary = f" [{len(files_changed)} files, +{total_add}/-{total_del}]"
    if len(description) + len(file_summary) <= 500:
        description += file_summary

# Skip if we have nothing to log
if not task_name:
    sys.exit(0)

# Escape single quotes for SQL
task_name = task_name.replace("'", "''")
description = description.replace("'", "''")
takeaways = takeaways.replace("'", "''")
gotchas = gotchas.replace("'", "''")

# Output: task_name|||description|||takeaways|||gotchas
print(f"{task_name}|||{description}|||{takeaways}|||{gotchas}")
PY
) || RESULT=""

# -- Skip if nothing to log --
if [[ -z "$RESULT" ]]; then
    rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true
    : > "$ACTIVITY_LOG" 2>/dev/null || true
    exit 0
fi

# -- Parse the 4-field output --
TASK_NAME=$(echo "$RESULT" | awk -F'\\|\\|\\|' '{print $1}')
DESCRIPTION=$(echo "$RESULT" | awk -F'\\|\\|\\|' '{print $2}')
TAKEAWAYS=$(echo "$RESULT" | awk -F'\\|\\|\\|' '{print $3}')
GOTCHAS=$(echo "$RESULT" | awk -F'\\|\\|\\|' '{print $4}')

# -- Format timestamp as MM/DD/YYYY hh:mm AM/PM PST (project convention) --
TIMESTAMP=$(TZ='America/Los_Angeles' date '+%m/%d/%Y %I:%M %p PST')

# -- Insert summary task into progress.db --
sqlite3 "$DB_FILE" "INSERT INTO tasks (project_id, timestamp, task_name, description, status, takeaways, gotchas)
VALUES ('$PROJECT_ID', '$TIMESTAMP', '$TASK_NAME', '$DESCRIPTION', 'done', '$TAKEAWAYS', '$GOTCHAS');" 2>/dev/null || true

# -- Cleanup: remove session marker and clear processed activity log --
rm -f "$SESSION_START_FILE" >/dev/null 2>&1 || true
: > "$ACTIVITY_LOG" 2>/dev/null || true

exit 0
