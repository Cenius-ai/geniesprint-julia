-- 0002: team members (the people who can be assigned to tasks)
CREATE TABLE IF NOT EXISTS team_members (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL,
    email      TEXT NOT NULL COLLATE NOCASE UNIQUE,
    role       TEXT,
    created_at TEXT,
    updated_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_team_members_email ON team_members (email);
