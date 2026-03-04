# Tasks: Hooks Alignment & Data Cleanup

**Input**: `specs/001-hooks-and-data-cleanup/spec.md`, `plan.md`

## Phase 1: Data Cleanup (US1 — P1) 🎯 MVP

**Goal**: Remove garbage auto-logged entries from progress.db

- [ ] T001 [US1] Query and review all auto-logged tasks matching pattern `N files changed` to confirm they're garbage
- [ ] T002 [US1] Delete garbage rows from tasks table, verify manually-logged tasks (11 entries) are untouched
- [ ] T003 [US1] Verify dashboard reflects clean data

---

## Phase 2: Hooks Alignment (US2 — P2)

**Goal**: Migrate hooks.json to official documented event names

- [ ] T004 [US2] Rewrite `session-start-marker.sh` to read `sessionStart` JSON input (timestamp, cwd, source) instead of /tmp marker hack
- [ ] T005 [US2] Update `progress-logger.sh` to be triggered by `sessionEnd` and read the `reason` field from input JSON
- [ ] T006 [US2] Update `.github/hooks/hooks.json` to use `sessionStart` and `sessionEnd` events, remove postToolUse session-start-marker
- [ ] T007 [US2] Validate hooks.json is valid JSON and only uses documented event names

---

## Phase 3: Parser Fix (US3 — P3)

**Goal**: Fix activity-logger.sh to parse Copilot CLI's double-encoded toolArgs

- [ ] T008 [US3] Rewrite `activity-logger.sh` JSON parsing to handle both Copilot CLI format (toolArgs as JSON string) and Claude Code format (tool_input as object)
- [ ] T009 [US3] Test with sample Copilot CLI postToolUse JSON — verify correct add/del line counts
- [ ] T010 [US3] Test with sample Claude Code PostToolUse JSON — verify backward compatibility

---

## Phase 4: Commit & Push

- [ ] T011 Commit all changes with descriptive message, push to main
- [ ] T012 Log task in progress.db

---

## Dependencies

- T001 → T002 → T003 (sequential — review before delete)
- T004, T005 can run in parallel (different files)
- T006 depends on T004 + T005
- T008 independent of T004–T006
- T011 depends on all prior tasks
