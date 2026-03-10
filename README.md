# AI Progress Tracker

A tool-agnostic progress tracking system for AI-assisted development. One SQLite database, accessible by any AI CLI (GitHub Copilot, Claude Code, Codex, Gemini, Cursor, etc.).

## Why This Exists

AI assistants are stateless. Every session starts from zero. When you're working across multiple projects with multiple AI tools, there's no shared record of what was done, what was learned, or what went wrong. Context is lost between sessions.

This system solves that with a single local SQLite database that any AI CLI can read and write. It answers three questions:
1. **What are we building and why?** (project goal — the north star)
2. **What has been done?** (task log with timestamps)
3. **What did we learn?** (takeaways and gotchas captured per task)

## Origin Story

This project started from two things coming together:

1. **A Reddit post on r/GithubCopilot** — [u/Left-Driver5549](https://www.reddit.com/r/GithubCopilot/) asked about hooks and multi-agent orchestration in the CLI. A GitHub Copilot team member ([u/ryanhecht_github](https://www.reddit.com/r/GithubCopilot/)) revealed that hooks were already supported via `.github/hooks/*.json` — just not yet documented. That unlocked the idea of automated logging at the agent level.

2. **The flywheel problem** — across multiple projects and AI tools, we kept rediscovering the same things. Wrong Slack workspace, wrong embedding dimensions, wrong API endpoint. Every session started from zero and burned tokens re-learning what a previous session already figured out. The original idea was a "learnings-skeptic" agent — a hook that reviews every output and asks *"what can we learn from this?"* — to build a flywheel of knowledge that compounds over time instead of resetting.

The takeaways and gotchas columns in the `tasks` table are a direct result of that thinking: every task captures not just what was done, but what was learned and what went wrong. The goal is that no AI session ever wastes time rediscovering something a previous session already paid for.

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

## Onboarding a Project (New or Existing)

Same process for both. Run once per repo.

1. Start an AI session (Copilot CLI or Claude Code) in the project folder
2. Run `/init-tracker`
3. Provide the project goal (mandatory)
4. The skill auto-detects folder, git remote, branch; registers in the DB
5. For Copilot CLI: creates `.github/hooks/hooks.json` pointing to `~/.ai/hooks/`
6. From that point forward, all tasks in that project are tracked automatically

### Manual registration (SQL)

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

## Task Logging

**Hooks are the ONLY writer to the database.** Agents never INSERT into the tasks table directly — this prevents wrong project_id attribution. The hook pipeline is deterministic: it matches `pwd` against registered project folders and skips unregistered folders entirely.

### How it works

On session end, `progress-logger.sh` builds a task entry from two data sources:

1. **Copilot CLI session state** (primary) — reads `workspace.yaml` for the session summary, and the latest checkpoint for the overview, takeaways, and gotchas. This is the rich context: *why* the change was made and *what was learned*.
2. **Activity log** (supplementary) — file change details logged during the session by `activity-logger.sh`. This is the *what*: which files changed and by how many lines.

If session state is unavailable (e.g., Claude Code sessions), it falls back to the activity log only.

### Hook scripts

Four shell scripts at `~/.ai/hooks/` (adapted from [yurukusa/claude-code-hooks](https://github.com/yurukusa/claude-code-hooks)):

| Script | Trigger | What it does |
|--------|---------|-------------|
| `session-start-marker.sh` | sessionStart | Records session start timestamp from hook input JSON |
| `activity-logger.sh` | postToolUse (edit/create/write) | Logs file changes to `~/.ai/hooks/activity-log.jsonl` |
| `progress-logger.sh` | sessionEnd / Stop | Reads session state + activity log, INSERTs summary into progress.db |
| `health-check.sh` | cron (every 5 min) | Checks dashboard, activity log, DB, and hooks staleness |

All hook scripts are silent — the user sees nothing.

### Canonical hooks template

The single source of truth for hooks configuration is `~/.ai/hooks/hooks-template.json`. The `init-tracker` skill copies this file to `.github/hooks/hooks.json` in each project. When the hooks format changes, update the template once — the next `/init-tracker` run on any project picks up the latest.

### Hook configuration

**Claude Code** — user-level, all projects automatically:
- Hooks configured in `~/.claude/settings.json`
- PostToolUse → session-start-marker.sh + activity-logger.sh
- Stop → progress-logger.sh
- Note: Claude Code sessions get the activity log fallback (file diffs) since Claude Code does not store session state in the same format as Copilot CLI.

**Copilot CLI** — repo-level, per project:
- Hooks configured in `.github/hooks/hooks.json` (copied from `~/.ai/hooks/hooks-template.json` by `init-tracker`)
- sessionStart → session-start-marker.sh
- postToolUse → activity-logger.sh
- sessionEnd → progress-logger.sh
- Copilot CLI sessions get full context: session summary + checkpoint overview + takeaways + gotchas.

### Display format

When asked to "show the project tracker" or "show progress", display as a markdown table with columns: Timestamp, Task, Description, Status, Takeaways, Gotchas, Notes. Group by project with the goal at the top.

## init-tracker Skill

To register a project (new or existing), run the `init-tracker` skill in any session:

```
/init-tracker
```

This skill:
1. Auto-detects folder, git remote, branch
2. Asks you for the project goal (mandatory)
3. Registers the project in `~/.ai/progress.db`
4. Creates `.github/hooks/hooks.json` for Copilot CLI (if it doesn't exist)

The skill is installed at:
- `~/.copilot/skills/init-tracker/SKILL.md` (Copilot CLI)
- `~/.claude/skills/init-tracker/SKILL.md` (Claude Code)

## AI Instruction File Reference

Add this to your project's AI instruction files so every tool knows where to find it:

```
# Progress Tracking
Global progress DB at ~/.ai/progress.db (SQLite).
Project ID: YOUR_PROJECT_ID
See ~/.ai/README.md for schema and usage.
Do NOT manually INSERT into the tasks table. Task logging is handled automatically by hooks.
```

**Files to add it to:**
- `.github/copilot-instructions.md` (GitHub Copilot)
- `CLAUDE.md` (Claude Code / OpenCode)
- `AGENTS.md` (Codex / Jules)
- `.cursorrules` or `.cursor/rules/` (Cursor)
- `.windsurfrules` (Windsurf)

## Dashboard

A read-only web UI for browsing projects, tasks, and notes from any device on your local network.

### Quick Start

```bash
bash ~/.ai/dashboard/run.sh
```

This will:
1. Create a Python virtual environment (first run only)
2. Install Flask (first run only)
3. Start the dashboard on port **9847**

### Access

- **This machine:** http://localhost:9847
- **Any device on your network:** http://YOUR_LAN_IP:9847

The dashboard reads `~/.ai/progress.db` in read-only mode. All data entry still happens through AI sessions.

### Pages

| Page | URL | What it shows |
|------|-----|---------------|
| Home | `/` | All projects with task counts |
| Project | `/project/<id>` | Full task log, notes, metadata |
| Search | `/search?q=<term>` | Cross-project task search |

## File Structure

```
~/.ai/
├── README.md              # This file — design decisions, schema docs, usage
├── schema.sql             # Database schema (version controlled)
├── progress.db            # The SQLite database (local data, gitignored)
├── hooks/                 # Shared hook scripts (both tools use these)
│   ├── session-start-marker.sh
│   ├── activity-logger.sh
│   ├── progress-logger.sh
│   ├── health-check.sh    # Cron job (every 5 min) — checks dashboard, hooks, DB
│   └── hooks-template.json # Canonical hooks.json — single source of truth
├── dashboard/             # Web dashboard (read-only)
│   ├── app.py             # Flask server (port 9847)
│   ├── run.sh             # One-command launcher
│   ├── requirements.txt   # Python dependencies
│   ├── static/style.css   # Dark theme styling
│   └── templates/         # Jinja2 templates
└── .gitignore             # Ignores progress.db, .venv
```

## License

MIT
