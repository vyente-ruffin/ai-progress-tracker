# AI Progress Tracker Constitution

## Core Principles

### I. Every Session Learns From the Last (NON-NEGOTIABLE)
No AI session should ever waste tokens rediscovering what a previous session already figured out. Takeaways and gotchas are first-class data — not optional afterthoughts. The system exists to build a flywheel of knowledge that compounds, not resets.

### II. Tool-Agnostic (NON-NEGOTIABLE)
Not owned by any vendor. Works with GitHub Copilot CLI, Claude Code, Codex, Gemini, Cursor — any AI CLI that can read SQLite. Lives at `~/.ai/`, not `~/.copilot/` or `~/.claude/`. If a tool disappears tomorrow, the data and the system survive.

### III. Signal Over Noise
Every logged entry must be useful to a future session. Auto-logged entries with no context ("1 files changed (+0/-0)") are worse than no entry — they bury real signal. If data can't answer "what happened and what did we learn?", it doesn't belong in the database.

### IV. Read-Only Dashboard, Write-Only Hooks
Humans and AI sessions write to the database. The dashboard is strictly read-only — a window into the data, not a form to fill out. This separation keeps the write path (hooks + AI sessions) authoritative and the read path (dashboard) simple.

### V. Local-First, Network-Accessible
The database lives on disk (`~/.ai/progress.db`). The dashboard binds to `0.0.0.0` on an obscure port for LAN access. No cloud, no auth, no deployment. If it can't run with `bash run.sh`, it's too complex.

### VI. Schema Versioned, Data Not
`schema.sql` is checked into git. `progress.db` is gitignored. Same pattern as shipping migrations without shipping the database. The schema is the contract; the data is local and personal.

## Stack Constraints

- **Database**: SQLite (`~/.ai/progress.db`)
- **Dashboard**: Python + Flask, single-file server, Jinja2 templates
- **Hooks**: Bash scripts at `~/.ai/hooks/`, triggered by AI CLI hook systems
- **Config**: `.github/hooks/hooks.json` (Copilot CLI), `~/.claude/settings.json` (Claude Code)
- **No build step**: No npm, no bundler, no transpiler. Plain HTML, CSS, Python.

## Hook Events (per official docs)

| Hook | Trigger | Use |
|------|---------|-----|
| `sessionStart` | Session begins | Record start timestamp, capture initial prompt |
| `sessionEnd` | Session completes | Aggregate changes, insert summary task into DB |
| `postToolUse` | After any tool runs | Log file changes to activity JSONL |
| `preToolUse` | Before any tool runs | Reserved for future policy enforcement |
| `errorOccurred` | Agent error | Reserved for future error tracking |

## Code Standards

### VII. Context7 First for All Code Changes (NON-NEGOTIABLE)
Always use the Context7 MCP server for documentation and code lookups before writing or modifying code. Never use web search for code recommendations — search results may be outdated, deprecated, or wrong. Context7 is kept current and returns verified, version-accurate documentation.

### VIII. Comment Every Step (NON-NEGOTIABLE)
Every block of code must be commented using best practices so any person or agent can follow the logic without guessing. Comments explain the **why**, not just the **what**. If a future session reads this code, it should know exactly what you were thinking and why you made that choice.

### IX. Best Practices Always
Follow established best practices for every language and framework used. No shortcuts, no "good enough for now." Code should be correct, readable, and maintainable from the first commit.

## Governance

This constitution supersedes all implementation decisions. Any change that violates these principles requires an explicit amendment with documented rationale. Noise must be justified against Principle III.

**Version**: 1.1.0 | **Ratified**: 2026-03-04 | **Last Amended**: 2026-03-04
