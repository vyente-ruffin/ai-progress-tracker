# Implementation Plan: Hooks Alignment & Data Cleanup

**Branch**: `001-hooks-and-data-cleanup` | **Date**: 2026-03-04 | **Spec**: `specs/001-hooks-and-data-cleanup/spec.md`

## Summary

Fix three related issues: purge 16 garbage auto-logged tasks from progress.db, migrate hooks.json from undocumented event names to official ones, and fix the activity-logger's JSON parser to handle Copilot CLI's double-encoded toolArgs.

## Technical Context

**Language/Version**: Bash (hooks scripts), Python 3.x (Flask dashboard — no changes needed), SQLite
**Primary Dependencies**: jq, python3, sqlite3
**Storage**: `~/.ai/progress.db` (SQLite)
**Testing**: Manual verification via piped JSON + DB queries
**Target Platform**: macOS (local dev machine)
**Constraints**: Must remain backward-compatible with Claude Code hook format

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Every Session Learns | ✅ Fix enables this | Broken parser means no learning happens |
| II. Tool-Agnostic | ✅ Maintained | Both Claude Code and Copilot CLI formats supported |
| III. Signal Over Noise | ✅ This is the fix | Purge garbage, prevent future garbage |
| IV. Read-Only Dashboard | ✅ No dashboard changes | Data layer fix only |
| V. Local-First | ✅ No change | Still local SQLite |
| VI. Schema Versioned | ✅ No schema change | Data cleanup only |
| VII. Context7 First | ✅ Used for hook docs | Official docs consulted |
| VIII. Comment Every Step | ✅ Will apply | All script changes fully commented |
| IX. Best Practices | ✅ Will apply | Proper JSON parsing, error handling |

## Project Structure

### Files Modified

```text
~/.ai/hooks/
├── session-start-marker.sh    # Rewrite: read sessionStart JSON input instead of /tmp hack
├── activity-logger.sh         # Fix: handle double-encoded toolArgs from Copilot CLI
└── progress-logger.sh         # Update: triggered by sessionEnd, read reason field

.github/hooks/hooks.json       # Update: sessionStart/sessionEnd instead of postToolUse hack/agentStop
```

### No Changes Needed

```text
dashboard/                     # Read-only, auto-reflects DB changes
schema.sql                     # No schema changes
```

## Research: Hook Input Formats

### Copilot CLI postToolUse input:
```json
{
  "timestamp": 1704614700000,
  "cwd": "/path/to/project",
  "toolName": "edit",
  "toolArgs": "{\"path\":\"/file.py\",\"old_str\":\"a\",\"new_str\":\"b\"}",
  "toolResult": {"resultType": "success", "textResultForLlm": "done"}
}
```
Note: `toolArgs` is a **JSON string**, not an object. Must be parsed twice.

### Claude Code PostToolUse input:
```json
{
  "tool_name": "Edit",
  "tool_input": {"file_path": "/file.py", "old_string": "a", "new_string": "b"}
}
```
Note: `tool_input` is a proper object. Different field names (`old_string` vs `old_str`).

### Copilot CLI sessionStart input:
```json
{
  "timestamp": 1704614400000,
  "cwd": "/path/to/project",
  "source": "new",
  "initialPrompt": "Fix the bug"
}
```

### Copilot CLI sessionEnd input:
```json
{
  "timestamp": 1704618000000,
  "cwd": "/path/to/project",
  "reason": "complete"
}
```
