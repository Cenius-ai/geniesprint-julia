p = "src/db.jl"
s = read(p, String)

# 1) migration runner guard
old = raw"""    for file in migration_files()
        sql = read(joinpath(MIGRATIONS_DIR, file), String)
        isempty(strip(sql)) && continue
        exec_sql(conn, "BEGIN")"""
new = raw"""    for file in migration_files()
        sql = read(joinpath(MIGRATIONS_DIR, file), String)
        isempty(strip(sql)) && continue
        if file == "0006_add_task_priority.sql" && tasks_has_priority_column(conn)
            continue # column already present (fresh DBs get it from 0004)
        end
        exec_sql(conn, "BEGIN")"""
occursin(old, s) || error("migrate loop needle missing")
s = replace(s, old => new; count = 1)

# 2) helper definition inserted before the repo_migrate! docstring
marker = raw"""    repo_migrate!() -> Nothing"""
helper = "    \"\"\"True when the tasks table already has the priority column.\"\"\"\n" *
         "function tasks_has_priority_column(conn)::Bool\n" *
         "    df = qdf(\"PRAGMA table_info(tasks)\")\n" *
         "    any(row -> _as_str(row[:name]) == \"priority\", eachrow(df))\n" *
         "end\n\n"
occursin(marker, s) || error("doc marker missing")
# the docstring marker appears twice (header block + docstring). Use the docstring occurrence.
idx = findlast(marker, s)
s = s[1:idx-1] * helper * s[idx:end]

# 3) create_task! priority
old_ins = raw"""    status::AbstractString,
    due_at::Union{AbstractString,Nothing},
)::Task
    ts = now_sql()
    desc = (description === nothing || isempty(strip(description))) ? nothing : strip(description)
    due = (due_at === nothing || isempty(due_at)) ? nothing : due_at
    qexec(
        "INSERT INTO tasks (project_id, assignee_id, title, description, status, due_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        project_id, assignee_id, String(title), desc, String(status), due, ts, ts,
    )"""
new_ins = raw"""    status::AbstractString,
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
    )"""
occursin(old_ins, s) || error("create insert needle missing")
s = replace(s, old_ins => new_ins; count = 1)

# 4) update_task! priority
old_up = raw"""    status::AbstractString,
    due_at::Union{AbstractString,Nothing},
)
    ts = now_sql()
    desc = (description === nothing || isempty(strip(description))) ? nothing : strip(description)
    due = (due_at === nothing || isempty(due_at)) ? nothing : due_at
    qexec(
        "UPDATE tasks SET project_id = ?, assignee_id = ?, title = ?, description = ?, status = ?, due_at = ?, updated_at = ?
         WHERE id = ?",
        project_id, assignee_id, String(title), desc, String(status), due, ts, task.id,
    )"""
new_up = raw"""    status::AbstractString,
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
    )"""
occursin(old_up, s) || error("update needle missing")
s = replace(s, old_up => new_up; count = 1)

write(p, s)
println("db.jl patched")
