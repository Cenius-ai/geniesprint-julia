# ---------------------------------------------------------------------------
# Repo layer: SQLite connection (through SearchLight's SQLite adapter),
# migrations, and every read/write the app performs. All queries use bound
# parameters (`?` placeholders) — never string-built SQL.
# ---------------------------------------------------------------------------

using SearchLight
using SearchLightSQLite
using SQLite
using DBInterface
using DataFrames
using Dates

const _conn = Ref{Any}(nothing)

"""
    repo_connect!(path::String = db_path()) -> Nothing

Opens the embedded SQLite database through SearchLightSQLite (SearchLight's
SQLite adapter) and applies per-connection pragmas. Creates parent directories
and the file itself when missing, so a fresh clone boots with zero setup.
"""
function repo_connect!(path::String = db_path())
    if _conn[] !== nothing
        return nothing
    end
    db = SearchLight.connect(Dict("database" => path))
    _conn[] = db

    # Foreign keys must be enabled per-connection in SQLite.
    DBInterface.execute(db, "PRAGMA foreign_keys = ON")
    # WAL keeps reads concurrent with writes and survives restarts.
    DBInterface.execute(db, "PRAGMA journal_mode = WAL")
    DBInterface.execute(db, "PRAGMA busy_timeout = 5000")

    @info "Connected to SQLite database at $(path)"
    nothing
end

"""Internal handle for SQL statements (tests that need raw access can use it too)."""
connection() = _conn[]::SQLite.DB

"""Close the connection (mainly used by the test harness between cases)."""
function repo_disconnect!()
    if _conn[] !== nothing
        try
            close(_conn[])
        catch
        end
        _conn[] = nothing
    end
    nothing
end

"""True when a database connection is open."""
repo_connected() = _conn[] !== nothing

"""
    exec_sql(conn, sql, params=()) -> Nothing

Executes a single statement and immediately finalizes its result so the
connection never holds an open statement (SQLite forbids COMMIT while another
statement is still in progress).
"""
function exec_sql(conn, sql::AbstractString, params = ())
    q = DBInterface.execute(conn, sql, params)
    try
        if q isa SQLite.Query
            DBInterface.close!(q)
        end
    catch
    end
    nothing
end

"""
    qdf(sql::String, params...) -> DataFrame

Runs a SELECT and returns all rows as a DataFrame (result finalized after).
"""
function qdf(sql::AbstractString, params...)
    conn = connection()
    q = DBInterface.execute(conn, sql, collect(params))
    try
        df = DataFrame(q)
        df
    finally
        try
            q isa SQLite.Query && DBInterface.close!(q)
        catch
        end
    end
end

"""
    qrow(sql::String, params...) -> Union{NamedTuple,Nothing}

Runs a SELECT expecting zero or one row.
"""
function qrow(sql::AbstractString, params...)
    df = qdf(sql, params...)
    for row in eachrow(df)
        return NamedTuple(row)
    end
    nothing
end

"""Runs a non-SELECT statement (INSERT/UPDATE/DELETE) for its side effect."""
function qexec(sql::AbstractString, params...)
    exec_sql(connection(), sql, collect(params))
    nothing
end

"""Id of the last auto-increment insert on this connection."""
function last_insert_id()::Int
    Int(SQLite.last_insert_rowid(connection()))
end

"""A UTC timestamp string used for created_at/updated_at columns."""
now_sql() = Dates.format(Dates.now(Dates.UTC), "yyyy-mm-dd HH:MM:SS")

# ---------------------------------------------------------------------------
# Migrations
# ---------------------------------------------------------------------------

const MIGRATIONS_DIR = abspath(joinpath(PROJECT_ROOT, "db", "migrations"))

function migration_files()::Vector{String}
    isdir(MIGRATIONS_DIR) || return String[]
    sort(filter(f -> endswith(f, ".sql"), readdir(MIGRATIONS_DIR)))
end

"""Splits a migration file into individual statements on ';' boundaries."""
function split_sql_statements(sql::AbstractString)::Vector{String}
    out = String[]
    for part in split(sql, ";")
        stmt = strip(part)
        isempty(stmt) && continue
        push!(out, stmt)
    end
    out
end

"""True when the tasks table already has the priority column."""
function tasks_has_priority_column(conn)::Bool
    df = qdf("PRAGMA table_info(tasks)")
    any(row -> _as_str(row[:name]) == "priority", eachrow(df))
end

"""
    repo_migrate!() -> Nothing

Applies every migration file in db/migrations in order. Every migration is
written idempotently (`CREATE TABLE IF NOT EXISTS`, `CREATE ... IF NOT EXISTS`),
so re-running on every boot is safe and never reports duplicate-migration
errors. A `schema_migrations` journal records what has been applied.
"""
function repo_migrate!()
    conn = connection()
    exec_sql(conn, """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version TEXT PRIMARY KEY,
            applied_at TEXT NOT NULL
        )
    """)

    for file in migration_files()
        sql = read(joinpath(MIGRATIONS_DIR, file), String)
        isempty(strip(sql)) && continue
        if file == "0006_add_task_priority.sql" && tasks_has_priority_column(conn)
            continue # priority column already present (fresh DBs get it from 0004)
        end
        exec_sql(conn, "BEGIN")
        try
            for stmt in split_sql_statements(sql)
                exec_sql(conn, stmt)
            end
            exec_sql(conn, "INSERT OR IGNORE INTO schema_migrations (version, applied_at) VALUES (?, ?)", (file, now_sql()))
            exec_sql(conn, "COMMIT")
        catch ex
            try
                exec_sql(conn, "ROLLBACK")
            catch
            end
            rethrow(ex)
        end
        @info "Applied migration $file"
    end
    nothing
end

# ---------------------------------------------------------------------------
# Generic lookups
# ---------------------------------------------------------------------------

"""True when the database has been seeded (any admin user present)."""
function repo_has_users()::Bool
    r = qrow("SELECT COUNT(*) AS n FROM users")
    r === nothing ? false : Int(r[:n]) > 0
end

# ---------------------------------------------------------------------------
# Users (authentication)
# ---------------------------------------------------------------------------

function user_by_email(email::AbstractString)::Union{User,Nothing}
    r = qrow("SELECT * FROM users WHERE email = ? COLLATE NOCASE LIMIT 1", String(email))
    r === nothing ? nothing : user_from_row(r)
end

function user_by_id(id::Int)::Union{User,Nothing}
    r = qrow("SELECT * FROM users WHERE id = ? LIMIT 1", id)
    r === nothing ? nothing : user_from_row(r)
end

"""
    create_user!(email, password) -> User

Persists a user with a freshly salted, iterated PBKDF2 hash. The plaintext
password never touches the database.
"""
function create_user!(email::AbstractString, password::AbstractString)::User
    ts = now_sql()
    creds = PasswordHasher.hash_password(password)
    qexec(
        "INSERT INTO users (email, password_hash, password_salt, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        String(email), creds.hash, creds.salt, ts, ts,
    )
    user_by_id(last_insert_id())
end

# ---------------------------------------------------------------------------
# Team members
# ---------------------------------------------------------------------------

function members_all()::Vector{TeamMember}
    df = qdf("SELECT * FROM team_members ORDER BY name COLLATE NOCASE ASC, id ASC")
    [member_from_row(row) for row in eachrow(df)]
end

function member_by_id(id::Int)::Union{TeamMember,Nothing}
    r = qrow("SELECT * FROM team_members WHERE id = ? LIMIT 1", id)
    r === nothing ? nothing : member_from_row(r)
end

function member_by_email(email::AbstractString)::Union{TeamMember,Nothing}
    r = qrow("SELECT * FROM team_members WHERE email = ? COLLATE NOCASE LIMIT 1", String(email))
    r === nothing ? nothing : member_from_row(r)
end

function member_email_taken(email::AbstractString, except_id::Union{Int,Nothing} = nothing)::Bool
    if except_id === nothing
        r = qrow("SELECT COUNT(*) AS n FROM team_members WHERE email = ? COLLATE NOCASE", String(email))
    else
        r = qrow("SELECT COUNT(*) AS n FROM team_members WHERE email = ? COLLATE NOCASE AND id <> ?", String(email), except_id)
    end
    r === nothing ? false : Int(r[:n]) > 0
end

function member_task_count(member_id::Int)::Int
    r = qrow("SELECT COUNT(*) AS n FROM tasks WHERE assignee_id = ?", member_id)
    r === nothing ? 0 : Int(r[:n])
end

function create_member!(name::AbstractString, email::AbstractString, role::Union{AbstractString,Nothing})::TeamMember
    ts = now_sql()
    role_val = (role === nothing || isempty(strip(role))) ? nothing : strip(role)
    qexec(
        "INSERT INTO team_members (name, email, role, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        String(name), String(email), role_val, ts, ts,
    )
    member_by_id(last_insert_id())
end

function update_member!(member::TeamMember, name::AbstractString, email::AbstractString, role::Union{AbstractString,Nothing})
    ts = now_sql()
    role_val = (role === nothing || isempty(strip(role))) ? nothing : strip(role)
    qexec(
        "UPDATE team_members SET name = ?, email = ?, role = ?, updated_at = ? WHERE id = ?",
        String(name), String(email), role_val, ts, member.id,
    )
    member_by_id(member.id)
end

"""Deletes the member. Throws on DB-level constraint violation (defence in depth)."""
function delete_member!(member_id::Int)
    qexec("DELETE FROM team_members WHERE id = ?", member_id)
    nothing
end

# ---------------------------------------------------------------------------
# Projects
# ---------------------------------------------------------------------------

function projects_all()::Vector{Project}
    df = qdf("SELECT * FROM projects ORDER BY due_at IS NULL ASC, due_at ASC, name COLLATE NOCASE ASC")
    [project_from_row(row) for row in eachrow(df)]
end

function project_by_id(id::Int)::Union{Project,Nothing}
    r = qrow("SELECT * FROM projects WHERE id = ? LIMIT 1", id)
    r === nothing ? nothing : project_from_row(r)
end

function project_name_taken(name::AbstractString, except_id::Union{Int,Nothing} = nothing)::Bool
    if except_id === nothing
        r = qrow("SELECT COUNT(*) AS n FROM projects WHERE name = ? COLLATE NOCASE", String(name))
    else
        r = qrow("SELECT COUNT(*) AS n FROM projects WHERE name = ? COLLATE NOCASE AND id <> ?", String(name), except_id)
    end
    r === nothing ? false : Int(r[:n]) > 0
end

function project_task_count(project_id::Int)::Int
    r = qrow("SELECT COUNT(*) AS n FROM tasks WHERE project_id = ?", project_id)
    r === nothing ? 0 : Int(r[:n])
end

function project_open_task_count(project_id::Int)::Int
    r = qrow("SELECT COUNT(*) AS n FROM tasks WHERE project_id = ? AND status <> 'done'", project_id)
    r === nothing ? 0 : Int(r[:n])
end

function create_project!(name::AbstractString, description::Union{AbstractString,Nothing}, due_at::Union{AbstractString,Nothing})::Project
    ts = now_sql()
    desc = (description === nothing || isempty(strip(description))) ? nothing : strip(description)
    due = (due_at === nothing || isempty(due_at)) ? nothing : due_at
    qexec(
        "INSERT INTO projects (name, description, due_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        String(name), desc, due, ts, ts,
    )
    project_by_id(last_insert_id())
end

function update_project!(project::Project, name::AbstractString, description::Union{AbstractString,Nothing}, due_at::Union{AbstractString,Nothing})
    ts = now_sql()
    desc = (description === nothing || isempty(strip(description))) ? nothing : strip(description)
    due = (due_at === nothing || isempty(due_at)) ? nothing : due_at
    qexec(
        "UPDATE projects SET name = ?, description = ?, due_at = ?, updated_at = ? WHERE id = ?",
        String(name), desc, due, ts, project.id,
    )
    project_by_id(project.id)
end

function delete_project!(project_id::Int)
    qexec("DELETE FROM projects WHERE id = ?", project_id)
    nothing
end

# ---------------------------------------------------------------------------
# Tasks
# ---------------------------------------------------------------------------

function tasks_all(status::Union{AbstractString,Nothing} = nothing)::Vector{Task}
    isempty_filter = (status === nothing || isempty(String(status)))
    df = if isempty_filter
        qdf("SELECT * FROM tasks ORDER BY status = 'done' ASC, due_at IS NULL ASC, due_at ASC, id ASC")
    else
        qdf("SELECT * FROM tasks WHERE status = ? ORDER BY due_at IS NULL ASC, due_at ASC, id ASC", String(status))
    end
    [task_from_row(row) for row in eachrow(df)]
end

function task_by_id(id::Int)::Union{Task,Nothing}
    r = qrow("SELECT * FROM tasks WHERE id = ? LIMIT 1", id)
    r === nothing ? nothing : task_from_row(r)
end

function tasks_for_project(project_id::Int)::Vector{Task}
    df = qdf("SELECT * FROM tasks WHERE project_id = ? ORDER BY status = 'done' ASC, due_at IS NULL ASC, due_at ASC, id ASC", project_id)
    [task_from_row(row) for row in eachrow(df)]
end

function tasks_for_member(member_id::Int)::Vector{Task}
    df = qdf("SELECT * FROM tasks WHERE assignee_id = ? ORDER BY status = 'done' ASC, due_at IS NULL ASC, due_at ASC, id ASC", member_id)
    [task_from_row(row) for row in eachrow(df)]
end

function create_task!(
    project_id::Int,
    assignee_id::Union{Int,Nothing},
    title::AbstractString,
    description::Union{AbstractString,Nothing},
    status::AbstractString,
    due_at::Union{AbstractString,Nothing},
    priority::AbstractString = "medium",
)::Task
    ts = now_sql()
    desc = (description === nothing || isempty(strip(description))) ? nothing : strip(description)
    due = (due_at === nothing || isempty(due_at)) ? nothing : due_at
    qexec(
        "INSERT INTO tasks (project_id, assignee_id, title, description, status, priority, due_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        project_id, assignee_id, String(title), desc, String(status), String(priority), due, ts, ts,
    )
    task_by_id(last_insert_id())
end

function update_task!(
    task::Task,
    project_id::Int,
    assignee_id::Union{Int,Nothing},
    title::AbstractString,
    description::Union{AbstractString,Nothing},
    status::AbstractString,
    due_at::Union{AbstractString,Nothing},
    priority::AbstractString = "medium",
)
    ts = now_sql()
    desc = (description === nothing || isempty(strip(description))) ? nothing : strip(description)
    due = (due_at === nothing || isempty(due_at)) ? nothing : due_at
    qexec(
        "UPDATE tasks SET project_id = ?, assignee_id = ?, title = ?, description = ?, status = ?, priority = ?, due_at = ?, updated_at = ?
         WHERE id = ?",
        project_id, assignee_id, String(title), desc, String(status), String(priority), due, ts, task.id,
    )
    task_by_id(task.id)
end

function delete_task!(task_id::Int)
    qexec("DELETE FROM tasks WHERE id = ?", task_id)
    nothing
end

# ---------------------------------------------------------------------------
# Aggregates used by the dashboard
# ---------------------------------------------------------------------------

function count_projects()::Int
    r = qrow("SELECT COUNT(*) AS n FROM projects")
    r === nothing ? 0 : Int(r[:n])
end

function count_team_members()::Int
    r = qrow("SELECT COUNT(*) AS n FROM team_members")
    r === nothing ? 0 : Int(r[:n])
end

function count_open_tasks()::Int
    r = qrow("SELECT COUNT(*) AS n FROM tasks WHERE status <> 'done'")
    r === nothing ? 0 : Int(r[:n])
end

function count_done_tasks()::Int
    r = qrow("SELECT COUNT(*) AS n FROM tasks WHERE status = 'done'")
    r === nothing ? 0 : Int(r[:n])
end

function count_tasks_in_status(status::AbstractString)::Int
    r = qrow("SELECT COUNT(*) AS n FROM tasks WHERE status = ?", String(status))
    r === nothing ? 0 : Int(r[:n])
end

function status_totals()::Dict{String,Int}
    Dict(status => count_tasks_in_status(status) for status in TASK_STATUSES)
end

function member_task_counts()::Dict{Int,Int}
    df = qdf("SELECT assignee_id AS member_id, COUNT(*) AS n FROM tasks WHERE assignee_id IS NOT NULL GROUP BY assignee_id")
    Dict{Int,Int}(Int(row[:member_id]) => Int(row[:n]) for row in eachrow(df))
end
