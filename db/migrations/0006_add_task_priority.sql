-- 0006: add task priority for databases created before priority support.
-- Fresh databases already get this column from 0004. The migration runner
-- applies this ALTER only when the column is missing (SQLite cannot express
-- "ALTER ... IF NOT EXISTS", so the runner guards it).
ALTER TABLE tasks ADD COLUMN priority TEXT NOT NULL DEFAULT 'medium'
    CHECK (priority IN ('low', 'medium', 'high'));
