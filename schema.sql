-- AI Progress Tracker Schema
-- Run: sqlite3 ~/.ai/progress.db < ~/.ai/schema.sql

CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  goal TEXT,
  folder TEXT,
  github_remote TEXT,
  branch TEXT,
  created_at TIMESTAMP DEFAULT (datetime('now', '-8 hours'))
);

CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id TEXT NOT NULL,
  timestamp TIMESTAMP DEFAULT (datetime('now', '-8 hours')),
  task_name TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'not_started' CHECK (status IN ('not_started', 'in_progress', 'done')),
  takeaways TEXT,
  gotchas TEXT,
  notes TEXT,
  FOREIGN KEY (project_id) REFERENCES projects(id)
);

CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks(project_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_timestamp ON tasks(timestamp DESC);
