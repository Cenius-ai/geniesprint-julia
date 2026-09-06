-- 0003: projects table
CREATE TABLE IF NOT EXISTS projects (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL COLLATE NOCASE UNIQUE,
    description TEXT,
    due_at      TEXT,
    created_at  TEXT,
    updated_at  TEXT
);
CREATE INDEX IF NOT EXISTS idx_projects_name ON projects (name);
