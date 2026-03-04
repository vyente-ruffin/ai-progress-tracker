#!/bin/bash
# ================================================================
# activity-logger.sh — Automatic File Change Logger
# ================================================================
# Records every file edit/create to a JSONL log file.
# Handles both Copilot CLI and Claude Code input formats.
#
# TRIGGER: postToolUse
# INPUT: JSON with toolName/tool_name, toolArgs/tool_input, toolResult
#
# Copilot CLI format:
#   toolArgs is a JSON STRING (double-encoded): '{"path":"/file.py","old_str":"a"}'
#   Field names: path, old_str, new_str, content
#
# Claude Code format:
#   tool_input is a JSON OBJECT (not double-encoded)
#   Field names: file_path, old_string, new_string, content
#
# Per official GitHub Copilot CLI hooks docs:
# https://docs.github.com/en/copilot/reference/hooks-configuration
#
# Adapted from yurukusa/claude-code-hooks (MIT)
# ================================================================

# -- Read hook input JSON from stdin --
INPUT=$(cat)

# -- Extract tool name (supports both Copilot CLI and Claude Code field names) --
TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName // .tool_name // empty' 2>/dev/null)

# -- Only log edit/create/write operations --
case "$TOOL_NAME" in
    edit|Edit|create|Create|write|Write) ;;
    *) exit 0 ;;
esac

# -- Parse file path and diff info using Python for robust JSON handling --
# Copilot CLI sends toolArgs as a dict (already parsed object).
# Claude Code sends tool_input as a dict with different field names.
RESULT=$(python3 -c "
import json, sys, os

raw = sys.stdin.read()
data = json.loads(raw)

file_path = ''
old_text = ''
new_text = ''
content = ''

# --- Copilot CLI format: toolArgs may be a dict OR a JSON string ---
tool_args_raw = data.get('toolArgs')
if tool_args_raw:
    if isinstance(tool_args_raw, dict):
        # Already a dict — Copilot CLI sends it pre-parsed
        args = tool_args_raw
    elif isinstance(tool_args_raw, str):
        # JSON string — parse it
        try:
            args = json.loads(tool_args_raw)
        except json.JSONDecodeError:
            args = {}
    else:
        args = {}

    file_path = args.get('path', '')
    old_text = args.get('old_str', '')
    new_text = args.get('new_str', '')
    content = args.get('file_text', args.get('content', ''))

# --- Claude Code format: tool_input is already a dict ---
if not file_path:
    tool_input = data.get('tool_input', {})
    if isinstance(tool_input, dict):
        file_path = tool_input.get('file_path', tool_input.get('path', ''))
        old_text = tool_input.get('old_string', tool_input.get('old_str', ''))
        new_text = tool_input.get('new_string', tool_input.get('new_str', ''))
        content = tool_input.get('content', tool_input.get('file_text', ''))

# --- Skip if we couldn't find a file path ---
if not file_path:
    sys.exit(0)

# --- Calculate line counts ---
old_lines = len(old_text.splitlines()) if old_text else 0
new_lines = len(new_text.splitlines()) if new_text else 0

if content:
    # File creation: all lines are additions
    add = len(content.splitlines())
    delete = 0
else:
    # Edit: diff between old and new
    add = max(0, new_lines - old_lines)
    delete = max(0, old_lines - new_lines)

basename = os.path.basename(file_path)

# Output as tab-separated for safe bash parsing
print(f'{file_path}\t{add}\t{delete}\t{basename}')
" <<< "$INPUT" 2>/dev/null) || exit 0

# -- Skip if Python returned nothing (no file path found) --
if [[ -z "$RESULT" ]]; then
    exit 0
fi

# -- Parse the tab-separated output from Python --
FILE_PATH=$(echo "$RESULT" | cut -f1)
ADD_LINES=$(echo "$RESULT" | cut -f2)
DEL_LINES=$(echo "$RESULT" | cut -f3)
SUMMARY=$(echo "$RESULT" | cut -f4)

# -- Generate UTC timestamp for the log entry --
TS="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# -- Append structured JSONL entry to the activity log --
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
