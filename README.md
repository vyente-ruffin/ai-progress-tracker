# AI Progress Tracker

A tool-agnostic progress tracking system for AI-assisted development. One SQLite database, accessible by any AI CLI (GitHub Copilot, Claude Code, Codex, Gemini, Cursor, etc.).

## What This Is

A global SQLite database at `~/.ai/progress.db` that tracks projects and tasks across all your repositories. Any AI assistant can read/write it — no vendor lock-in.

Each project repo gets a generated `progress.md` snapshot committed to git so collaborators and AI sessions see current status without needing the DB.

## Setup

```bash
# Clone to ~/.ai
git clone git@github.com:405network/ai-progress-tracker.git ~/.ai

# Initialize the database
sqlite3 ~/.ai/progress.db < ~/.ai/schema.sql
```

## Schema

### `projects` table

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Short slug, e.g. `open-memory` |
| name | TEXT NOT NULL | Human-readable name |
| goal | TEXT | North star — the what and why |
| folder | TEXT | Local path, e.g. `/Users/sudo/GIT/405network/open-memory` |
| github_remote | TEXT | e.g. `405network/open-memory` |
| branch | TEXT | Default working branch |
| created_at | TIMESTAMP | Auto-set on creation |

### `tasks` table

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| project_id | TEXT FK | Links to projects.id |
| timestamp | TIMESTAMP | When the task was logged (PST) |
| task_name | TEXT NOT NULL | Short label |
| description | TEXT | What was done |
| status | TEXT | `not_started`, `in_progress`, `done` |
| takeaways | TEXT | What we learned |
| gotchas | TEXT | What went wrong or was unexpected |
| notes | TEXT | Anything else |

## Usage

### Init a new project

```sql
INSERT INTO projects (id, name, goal, folder, github_remote, branch)
VALUES (
  'open-memory',
  'Open Memory',
  'A database-backed AI-accessible knowledge system. One brain that every AI can plug into.',
  '/Users/sudo/GIT/405network/open-memory',
  '405network/open-memory',
  'main'
);
```

### Log a task

```sql
INSERT INTO tasks (project_id, timestamp, task_name, description, status, takeaways, gotchas, notes)
VALUES (
  'open-memory',
  datetime('now', '-8 hours'),
  'Create #capture channel',
  'Created private #capture channel in 405network.com Slack workspace',
  'done',
  'Channel ID is C0AJ5SWCZNZ',
  'Previous session created it in the wrong workspace (405Network instead of 405network.com)',
  NULL
);
```

### Query tasks for a project

```sql
SELECT timestamp, task_name, status, takeaways, gotchas
FROM tasks
WHERE project_id = 'open-memory'
ORDER BY timestamp DESC;
```

### Generate progress.md for a repo

Query the DB and write the output to `progress.md` in the project repo. The file should contain:
1. The project goal (from `projects.goal`)
2. A task log table (from `tasks` ordered by timestamp desc)

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
├── README.md          # This file
├── schema.sql         # Database schema
├── progress.db        # The SQLite database (created on init, gitignored)
└── .gitignore         # Ignores progress.db (local data)
```

## License

MIT
