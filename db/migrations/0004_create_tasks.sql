-- 0004: tasks table with foreign keys and status/priority constraints.
-- Delete protection lives in the app (friendly messages), with the FK
-- RESTRICT actions as the database-level backstop.
CREATE TABLE IF NOT EXISTS tasks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id  INTEGER NOT NULL REFERENCES projects (id) ON DELETE RESTRICT,
    assignee_id INTEGER REFERENCES team_members (id) ON DELETE RESTRICT,
    title       TEXT NOT NULL COLLATE NOCASE,
    description TEXT,
    status      TEXT NOT NULL DEFAULT 'todo'
                CHECK (status IN ('todo', 'in_progress', 'done')),
    priority    TEXT NOT NULL DEFAULT 'medium'
                CHECK (priority IN ('low', 'medium', 'high')),
    due_at      TEXT,
    created_at  TEXT,
    updated_at  TEXT,
    UNIQUE (project_id, title)
);
CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks (project_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee ON tasks (assignee_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks (status);
