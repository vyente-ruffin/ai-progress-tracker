# AI Progress Tracker

A tool-agnostic progress tracking system for AI-assisted development. One SQLite database, accessible by any AI CLI (GitHub Copilot, Claude Code, Codex, Gemini, Cursor, etc.).

## Why This Exists

AI assistants are stateless. Every session starts from zero. When you're working across multiple projects with multiple AI tools, there's no shared record of what was done, what was learned, or what went wrong. Context is lost between sessions.

This system solves that with a single local SQLite database that any AI CLI can read and write. It answers three questions:
1. **What are we building and why?** (project goal — the north star)
2. **What has been done?** (task log with timestamps)
3. **What did we learn?** (takeaways and gotchas captured per task)

## Design Decisions

- **SQLite over markdown tables** — queryable, sortable, filterable, doesn't get unwieldy as it grows. A markdown table with 7+ columns breaks fast.
- **`~/.ai/` not `~/.copilot/`** — tool-agnostic location. Not owned by any vendor. Any AI CLI can be pointed here.
- **Schema is version controlled, data is not** — `schema.sql` lives in git. `progress.db` is gitignored (local machine data). Same pattern as shipping migrations without shipping the database.
- **`progress.md` in each repo** — generated snapshot from the DB, committed to git so collaborators and AI sessions see current status without needing the DB directly.
- **Goal is mandatory** — without knowing the what and why, the how doesn't make sense. No project can be created without a north star.
- **Folder is mandatory** — every project lives somewhere on disk.
- **Takeaways and gotchas default to empty string, not NULL** — the columns are always present and queryable. When there's nothing to report, leave empty. When there is, capture it. Query with `WHERE takeaways != ''` to find learnings.
- **Project notes are append-only** — freeform text, no length limit, timestamped. Add as many as you want over time. Captures evolving context, decisions, and observations.
- **Timestamps in AM/PM PST** — human-readable, consistent timezone.
- **Projects can be related** — optional `related_to` field links projects that depend on or connect to each other.

## Setup

```bash
# Clone to ~/.ai
git clone git@github.com:vyente-ruffin/ai-progress-tracker.git ~/.ai

# Initialize the database
sqlite3 ~/.ai/progress.db < ~/.ai/schema.sql
```

## Schema

### `projects` — One row per project

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | TEXT | ✅ Primary key | Short slug, e.g. `open-memory` |
| name | TEXT | ✅ | Human-readable name |
| goal | TEXT | ✅ | North star — the what and why. One project, one goal. |
| folder | TEXT | ✅ | Local path, e.g. `/Users/sudo/GIT/405network/open-memory` |
| github_remote | TEXT | ❌ | e.g. `405network/open-memory` |
| branch | TEXT | ❌ | Default working branch |
| related_to | TEXT | ❌ | FK → projects.id, if related to another project |
| created_at | TEXT | ✅ Auto-set | `MM/DD/YYYY hh:mm AM/PM PST` |

### `project_notes` — Append-only log of evolving context per project

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | INTEGER | ✅ Auto-increment | |
| project_id | TEXT | ✅ FK → projects.id | |
| note | TEXT | ✅ | Freeform text, no length limit |
| created_at | TEXT | ✅ Auto-set | `MM/DD/YYYY hh:mm AM/PM PST` |

### `tasks` — What was done, what was learned

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | INTEGER | ✅ Auto-increment | |
| project_id | TEXT | ✅ FK → projects.id | |
| timestamp | TEXT | ✅ Auto-set | `MM/DD/YYYY hh:mm AM/PM PST` |
| task_name | TEXT | ✅ | Short label |
| description | TEXT | ✅ | What was done — AI should always describe the work |
| status | TEXT | ✅ Default: `not_started` | `not_started`, `in_progress`, `done` |
| takeaways | TEXT | ✅ Default: `''` | What we learned. Empty if nothing notable. |
| gotchas | TEXT | ✅ Default: `''` | What went wrong or was unexpected. Empty if clean. |
| notes | TEXT | ❌ | Anything else |

## Usage

### Init a new project

```sql
INSERT INTO projects (id, name, goal, folder, github_remote, branch)
VALUES (
  'open-memory',
  'Open Memory',
  'A database-backed AI-accessible knowledge system you own outright. One brain that every AI you use can plug into. Capture thoughts via Slack, embed and classify them automatically, store in Supabase with vector search. An MCP server lets any AI assistant search your brain by meaning.',
  '/Users/sudo/GIT/405network/open-memory',
  '405network/open-memory',
  'main'
);
```

### Log a task

```sql
INSERT INTO tasks (project_id, task_name, description, status, takeaways, gotchas, notes)
VALUES (
  'open-memory',
  'Create #capture channel',
  'Created private #capture channel in 405network.com Slack workspace',
  'done',
  'Channel ID is C0AJ5SWCZNZ',
  'Previous session created it in the wrong workspace (405Network instead of 405network.com)',
  NULL
);
```

### Add a project note

```sql
INSERT INTO project_notes (project_id, note)
VALUES (
  'open-memory',
  'Decided to separate write path (Slack only) from read path (MCP only). Human writes, AI reads.'
);
```

### Query tasks for a project

```sql
SELECT timestamp, task_name, status, takeaways, gotchas
FROM tasks
WHERE project_id = 'open-memory'
ORDER BY timestamp DESC;
```

### Query learnings across all projects

```sql
SELECT p.name, t.task_name, t.takeaways, t.gotchas
FROM tasks t JOIN projects p ON t.project_id = p.id
WHERE t.takeaways != '' OR t.gotchas != ''
ORDER BY t.timestamp DESC;
```

### Generate progress.md for a repo

Query the DB and write the output to `progress.md` in the project repo:
1. Project goal (from `projects.goal`)
2. Project notes (from `project_notes` ordered by created_at)
3. Task log table (from `tasks` ordered by timestamp desc)

## AI Instruction File Reference

Add this to your project's AI instruction files so every tool knows where to find it:

```
# Progress Tracking
Global progress DB at ~/.ai/progress.db (SQLite).
Project ID: YOUR_PROJECT_ID
See ~/.ai/README.md for schema and usage.
```

**Files to add it to:**
- `.github/copilot-instructions.md` (GitHub Copilot)
- `CLAUDE.md` (Claude Code / OpenCode)
- `AGENTS.md` (Codex / Jules)
- `.cursorrules` or `.cursor/rules/` (Cursor)
- `.windsurfrules` (Windsurf)

## File Structure

```
~/.ai/
├── README.md          # This file — design decisions, schema docs, usage
├── schema.sql         # Database schema (version controlled)
├── progress.db        # The SQLite database (local data, gitignored)
└── .gitignore         # Ignores progress.db
```

## License

MIT
