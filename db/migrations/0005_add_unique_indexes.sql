-- 0005: additional indexes for the list/dashboard queries.
CREATE INDEX IF NOT EXISTS idx_tasks_due ON tasks (due_at);
CREATE INDEX IF NOT EXISTS idx_projects_due ON projects (due_at);
CREATE INDEX IF NOT EXISTS idx_team_members_name ON team_members (name);
CREATE INDEX IF NOT EXISTS idx_users_created ON users (created_at);
