#!/bin/bash
# ================================================================
# activity-logger.sh — Automatic File Change Logger
# ================================================================
# Records every file edit/write to a JSONL log file.
# Gives a complete audit trail of what was changed, when, and how much.
#
# TRIGGER: PostToolUse
# MATCHER: "Edit|Write"
#
# Adapted from yurukusa/claude-code-hooks (MIT)
# ================================================================

INPUT=$(cat)

# Support both Claude Code (tool_name/tool_input) and Copilot CLI (toolName/toolArgs) formats
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
if [[ -z "$FILE_PATH" ]]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.toolArgs' 2>/dev/null | jq -r '.path // .file_path // empty' 2>/dev/null)
fi

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

TOOL_INPUT_RAW=$(echo "$INPUT" | jq -r '.tool_input // empty' 2>/dev/null)
if [[ -z "$TOOL_INPUT_RAW" ]] || [[ "$TOOL_INPUT_RAW" == "null" ]]; then
    TOOL_INPUT_RAW=$(echo "$INPUT" | jq -r '.toolArgs' 2>/dev/null)
fi
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // .toolName // empty' 2>/dev/null)
TOOL_NAME="${TOOL_NAME:-Edit}"

TS="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

ADD_LINES=0
DEL_LINES=0
SUMMARY=""
if [[ -n "$TOOL_INPUT_RAW" ]]; then
    eval "$(echo "$TOOL_INPUT_RAW" | python3 -c "
import sys, json, os
d = json.load(sys.stdin)
old = d.get('old_string', '')
new = d.get('new_string', '')
content = d.get('content', '')
old_lines = len(old.splitlines()) if old else 0
new_lines = len(new.splitlines()) if new else 0
if content:
    new_lines = len(content.splitlines())
    old_lines = 0
add = max(0, new_lines - old_lines) if not content else new_lines
dele = max(0, old_lines - new_lines) if not content else 0
print(f'ADD_LINES={add}')
print(f'DEL_LINES={dele}')
print(f'SUMMARY=\"{os.path.basename(d.get(\"file_path\", d.get(\"path\", \"\")))}\"')
" 2>/dev/null || echo "")"
fi

LOG_FILE="$HOME/.ai/hooks/activity-log.jsonl"
mkdir -p "$(dirname "$LOG_FILE")"

python3 -c "
import json
entry = {
    'ts': '$TS',
    'tool': '$TOOL_NAME',
    'path': '$FILE_PATH',
    'add': $ADD_LINES,
    'del': $DEL_LINES,
    'summary': '$SUMMARY'
}
print(json.dumps(entry, ensure_ascii=False))
" >> "$LOG_FILE" 2>/dev/null || true

exit 0
