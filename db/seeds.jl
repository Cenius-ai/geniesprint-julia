# ---------------------------------------------------------------------------
# Idempotent demo seed. Invoked automatically after migrations on every boot
# (and by the standalone `seed.jl` entrypoint). Safe to run any number of
# times: every insert is guarded by a check-before-insert and parents are
# created before children. All due dates are computed relative to today so the
# dashboard always shows overdue, upcoming, in-progress and completed states.
# ---------------------------------------------------------------------------

"""
    seed_demo_data!() -> NamedTuple

Upserts the demo workspace:
  * one primary demo admin   cenius@cenius.ai  / cenius
  * one plan-specified admin demo@example.com / password123
  * four team members
  * three projects
  * eight tasks (statuses spread over todo / in_progress / done)

Returns a NamedTuple of counts so the boot log can confirm readiness.
"""
function seed_demo_data!()
    ts = now_sql()

    # --- Admin users (hashed through the same path login verifies) ---------
    admin_creds = [
        ("cenius@cenius.ai", "cenius"),
        ("demo@example.com", "password123"),
    ]
    for (email, password) in admin_creds
        if user_by_email(email) === nothing
            creds = PasswordHasher.hash_password(password)
            qexec(
                "INSERT INTO users (email, password_hash, password_salt, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                email, creds.hash, creds.salt, ts, ts,
            )
            @info "Seeded admin user $email"
        end
    end

    # --- Team members (parents before tasks) --------------------------------
    members = [
        (name = "Amara Okafor",  email = "amara@genieteam.dev",  role = "Product designer"),
        (name = "Mateo Ruiz",    email = "mateo@genieteam.dev",  role = "Frontend engineer"),
        (name = "Priya Nair",    email = "priya@genieteam.dev",  role = "Backend engineer"),
        (name = "Jonas Weber",   email = "jonas@genieteam.dev",  role = "QA analyst"),
    ]
    member_ids = Dict{String,Int}()
    for m in members
        existing = member_by_email(m.email)
        if existing === nothing
            qexec(
                "INSERT INTO team_members (name, email, role, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                m.name, m.email, m.role, ts, ts,
            )
            existing = member_by_id(last_insert_id())
        end
        member_ids[m.email] = existing.id::Int
    end

    # --- Projects (parents before tasks) ------------------------------------
    projects = [
        (name = "Atlas Website Redesign",  due = 12,  desc = "Refresh the public marketing site: new information architecture, a modern component library, and a launch-ready homepage. Success is measured by demo signups and task-completion speed."),
        (name = "Mobile App Q3 Release",   due = 21,  desc = "Ship the Q3 mobile release: onboarding flow, push notifications, and OAuth login. Freeze scope two weeks before the store submission date."),
        (name = "Internal Design System",  due = -3,  desc = "Codify the shared design tokens and component patterns every product team consumes. The source of truth for color, type, and spacing."),
    ]
    project_ids = Dict{String,Int}()
    for p in projects
        existing = qrow("SELECT * FROM projects WHERE name = ? COLLATE NOCASE LIMIT 1", p.name)
        if existing === nothing
            qexec(
                "INSERT INTO projects (name, description, due_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                p.name, p.desc, iso_offset(p.due), ts, ts,
            )
            existing = qrow("SELECT * FROM projects WHERE id = ? LIMIT 1", last_insert_id())
        end
        project_ids[p.name] = Int(existing[:id])
    end

    # --- Tasks ---------------------------------------------------------------
    tasks = [
        (project = "Atlas Website Redesign", assignee = "amara@genieteam.dev", title = "Audit current homepage content",            desc = "Inventory every existing page section, note what stays, what is cut, and where the new narrative begins.", status = "todo",         due = 5),
        (project = "Atlas Website Redesign", assignee = "mateo@genieteam.dev", title = "Build the new component library",           desc = "Implement the approved design tokens as reusable components: buttons, forms, tables, and status pills.", status = "in_progress", due = 9),
        (project = "Atlas Website Redesign", assignee = "amara@genieteam.dev", title = "Homepage hero wireframes",                   desc = "Three hero directions tested against the new value proposition; annotate for the copywriter.",          status = "done",        due = -2),
        (project = "Mobile App Q3 Release",  assignee = "amara@genieteam.dev", title = "Finalize push notification copy",            desc = "Write the opt-in prompt and the first three notification templates; keep tone consistent with onboarding.", status = "todo",         due = 2),
        (project = "Mobile App Q3 Release",  assignee = "mateo@genieteam.dev", title = "Wire up the OAuth login screen",             desc = "Connect the login screen to the auth provider; handle the callback and error states.",                  status = "in_progress", due = 13),
        (project = "Mobile App Q3 Release",  assignee = nothing,               title = "Load-test the release candidate",            desc = "Run the release candidate through a 10k-user soak test and publish the latency report.",               status = "todo",         due = 20),
        (project = "Internal Design System", assignee = "priya@genieteam.dev", title = "Tokenize the border-radius scale",           desc = "Replace hardcoded radii across the web app with the new 4-step radius scale.",                         status = "in_progress", due = -1),
        (project = "Internal Design System", assignee = "priya@genieteam.dev", title = "Document color tokens",                      desc = "Publish the token reference page with contrast ratios for every foreground/background pair.",          status = "done",        due = -7),
    ]
    for t in tasks
        pid = project_ids[t.project]
        exists = qrow("SELECT COUNT(*) AS n FROM tasks WHERE project_id = ? AND title = ? COLLATE NOCASE", pid, t.title)
        (exists !== nothing && Int(exists[:n]) > 0) && continue
        assignee = t.assignee === nothing ? nothing : member_ids[t.assignee]
        desc = t.desc
        qexec(
            "INSERT INTO tasks (project_id, assignee_id, title, description, status, due_at, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            pid, assignee, t.title, desc, t.status, iso_offset(t.due), ts, ts,
        )
    end

    (admins = length(admin_creds), members = length(members), projects = length(projects), tasks = length(tasks))
end

"""
    seed_if_empty!() -> Bool

Runs the seed when the database holds no admin user yet. Returns true when it
seeded. Idempotent: safe to call on every boot path.
"""
function seed_if_empty!()::Bool
    repo_has_users() && return false
    counts = seed_demo_data!()
    @info "Demo data ready: $(counts.admins) admins, $(counts.members) team members, $(counts.projects) projects, $(counts.tasks) tasks."
    @info "Demo login: cenius@cenius.ai / cenius"
    true
end
