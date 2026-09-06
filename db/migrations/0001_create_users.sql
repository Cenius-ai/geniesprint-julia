-- 0001: admin users table
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    email         TEXT NOT NULL COLLATE NOCASE UNIQUE,
    password_hash TEXT NOT NULL,
    password_salt TEXT NOT NULL,
    created_at    TEXT,
    updated_at    TEXT
);
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
