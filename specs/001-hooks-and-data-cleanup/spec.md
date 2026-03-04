# Feature Specification: Hooks Alignment & Data Cleanup

**Feature Branch**: `001-hooks-and-data-cleanup`
**Created**: 2026-03-04
**Status**: Draft
**Input**: Gap analysis comparing current hooks implementation against official GitHub Copilot CLI hooks documentation and constitution Principle III (Signal Over Noise)

## User Scenarios & Testing

### User Story 1 - Clean Data in Dashboard (Priority: P1)

As a user viewing the dashboard, I only see meaningful task entries — no auto-generated noise like "1 files changed (+0/-0)".

**Why this priority**: The dashboard is currently unusable because 16 of 27 entries are garbage. This is the most visible problem and directly violates Constitution Principle III.

**Independent Test**: Open the dashboard, every task entry should have a descriptive task_name and a non-trivial description.

**Acceptance Scenarios**:

1. **Given** the progress DB contains auto-logged entries with task_name matching "N files changed", **When** the cleanup runs, **Then** those rows are deleted from the tasks table.
2. **Given** the progress DB after cleanup, **When** I view the dashboard, **Then** every task has a human-readable task_name and meaningful description.

---

### User Story 2 - Hooks Use Official Event Names (Priority: P2)

As a developer maintaining the hooks, the hooks.json uses only documented event names (`sessionStart`, `sessionEnd`, `postToolUse`) so they won't break on CLI updates.

**Why this priority**: Using undocumented `agentStop` is a time bomb. Fixing this is essential for reliability but less urgent than cleaning visible data.

**Independent Test**: Validate hooks.json only contains event names listed in the official docs. Start a new session and confirm hooks fire.

**Acceptance Scenarios**:

1. **Given** the hooks.json file, **When** I inspect the event names, **Then** they are `sessionStart`, `sessionEnd`, and `postToolUse` only.
2. **Given** a new Copilot CLI session in this repo, **When** the session starts, **Then** `sessionStart` hook fires and records the timestamp (no more `/tmp` marker file hack).
3. **Given** a Copilot CLI session ends, **When** `sessionEnd` fires, **Then** progress-logger.sh runs and inserts a summary task.

---

### User Story 3 - Auto-Logger Produces Useful Data (Priority: P3)

As a user reviewing auto-logged entries, the entries have correct file change counts and the description tells me what actually happened.

**Why this priority**: Even with clean hooks, the activity-logger.sh fails to parse Copilot CLI's double-encoded `toolArgs` JSON. Without this fix, new auto-logged entries will continue to be garbage.

**Independent Test**: Pipe a sample Copilot CLI postToolUse JSON into activity-logger.sh and verify the JSONL output has correct `add`/`del` counts and a meaningful `summary`.

**Acceptance Scenarios**:

1. **Given** a Copilot CLI postToolUse JSON with `toolArgs` as a JSON string, **When** activity-logger.sh processes it, **Then** the JSONL entry has correct line counts from `old_str`/`new_str`.
2. **Given** a Claude Code postToolUse JSON with `tool_input` as an object, **When** activity-logger.sh processes it, **Then** the JSONL entry still works (backward compatible).

---

### Edge Cases

- What happens if progress.db doesn't exist when hooks fire? Scripts should exit silently (already handled).
- What if `sessionEnd` doesn't fire (e.g., user kills terminal)? Data from that session is lost — acceptable, same as current behavior.
- What about Claude Code's `Stop` hook? Claude Code hooks live in `~/.claude/settings.json` — this spec only covers Copilot CLI hooks in `.github/hooks/hooks.json`.

## Requirements

### Functional Requirements

- **FR-001**: System MUST delete all auto-logged tasks where `task_name` matches the pattern `N files changed` and description contains only filenames with `(+0/-0)`.
- **FR-002**: System MUST update `hooks.json` to use `sessionStart` instead of faking it via `postToolUse` first-call marker.
- **FR-003**: System MUST update `hooks.json` to use `sessionEnd` instead of `agentStop`.
- **FR-004**: System MUST update `session-start-marker.sh` to read from `sessionStart` hook input JSON (timestamp, cwd, source).
- **FR-005**: System MUST update `progress-logger.sh` to be triggered by `sessionEnd` and read the `reason` field.
- **FR-006**: System MUST fix `activity-logger.sh` to handle double-encoded `toolArgs` JSON from Copilot CLI.
- **FR-007**: System MUST remain backward-compatible with Claude Code's `tool_input` format.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Zero tasks in progress.db with task_name matching `N files changed (+0/-0)`.
- **SC-002**: `hooks.json` contains only officially documented event names.
- **SC-003**: `echo '{"toolArgs":"{\"path\":\"test.py\",\"old_str\":\"a\\nb\",\"new_str\":\"c\\nd\\ne\"}","toolName":"edit"}' | bash activity-logger.sh` produces JSONL with correct add/del counts.
- **SC-004**: All existing manually-logged tasks (11 entries) remain untouched.
