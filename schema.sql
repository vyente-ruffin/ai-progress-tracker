-- AI Progress Tracker Schema
-- Run: sqlite3 ~/.ai/progress.db < ~/.ai/schema.sql

CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  goal TEXT NOT NULL,
  folder TEXT NOT NULL,
  github_remote TEXT,
  branch TEXT,
  related_to TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%m/%d/%Y %I:%M %p PST', 'now', '-8 hours')),
  FOREIGN KEY (related_to) REFERENCES projects(id)
);

CREATE TABLE IF NOT EXISTS project_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id TEXT NOT NULL,
  note TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%m/%d/%Y %I:%M %p PST', 'now', '-8 hours')),
  FOREIGN KEY (project_id) REFERENCES projects(id)
);

CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id TEXT NOT NULL,
  timestamp TEXT NOT NULL DEFAULT (strftime('%m/%d/%Y %I:%M %p PST', 'now', '-8 hours')),
  task_name TEXT NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'not_started' CHECK (status IN ('not_started', 'in_progress', 'done')),
  takeaways TEXT NOT NULL DEFAULT '',
  gotchas TEXT NOT NULL DEFAULT '',
  notes TEXT,
  FOREIGN KEY (project_id) REFERENCES projects(id)
);

CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks(project_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_timestamp ON tasks(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_project_notes_project ON project_notes(project_id);
