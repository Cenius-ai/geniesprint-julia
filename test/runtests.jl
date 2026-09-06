# ---------------------------------------------------------------------------
# GenieTeam test suite (Pkg.test). No network, no external services:
# everything runs against a throwaway SQLite file + an in-process Genie server.
#
#   julia --project=. -e 'using Pkg; Pkg.test()'
# ---------------------------------------------------------------------------

using Test
using GenieTeam
using GenieTeam: PasswordHasher
using HTTP
using Sockets

const TEST_DIR = mktempdir()
const TEST_DB = joinpath(TEST_DIR, "test.db")

# Point the app at the throwaway DB BEFORE any connection is opened.
ENV["GENIETEAM_DB_PATH"] = TEST_DB

@testset "GenieTeam" begin

# ---------------------------------------------------------------------------
# 1. Password hasher (auth primitive)
# ---------------------------------------------------------------------------
@testset "PasswordHasher" begin
    creds = PasswordHasher.hash_password("cenius")
    @test creds.hash != "cenius"
    @test length(creds.salt) == 32                 # 16 bytes hex
    @test length(creds.hash) == 64                 # 32 bytes hex
    @test PasswordHasher.verify_password("cenius", creds.hash, creds.salt)
    @test !PasswordHasher.verify_password("wrong", creds.hash, creds.salt)
    @test !PasswordHasher.verify_password("cenius", "zz", creds.salt)

    again = PasswordHasher.hash_password("cenius")
    @test again.salt != creds.salt                 # salts are random
    @test PasswordHasher.verify_password("cenius", again.hash, again.salt)
    @test PasswordHasher.secure_equals("abc123", "abc123")
    @test !PasswordHasher.secure_equals("abc123", "abc124")
end

# ---------------------------------------------------------------------------
# 2. Migrations + idempotent seed on a clean database
# ---------------------------------------------------------------------------
@testset "seed + migrations" begin
    GenieTeam.repo_connect!(TEST_DB)
    GenieTeam.repo_migrate!()
    GenieTeam.repo_migrate!()   # re-running is a no-op (no duplicate errors)

    GenieTeam.seed_demo_data!()
    @test GenieTeam.count_team_members() == 4
    @test GenieTeam.count_projects() == 3
    @test GenieTeam.count_open_tasks() + GenieTeam.count_done_tasks() == 8

    admin = GenieTeam.user_by_email("cenius@cenius.ai")
    @test admin !== nothing
    @test admin.password_hash != "cenius"           # salted hash, never plaintext
    @test admin.password_salt != ""
    @test PasswordHasher.verify_password("cenius", admin.password_hash, admin.password_salt)
    @test GenieTeam.user_by_email("demo@example.com") !== nothing

    # Idempotency: a second seed run changes nothing.
    GenieTeam.seed_demo_data!()
    @test GenieTeam.count_team_members() == 4
    @test GenieTeam.count_projects() == 3
    @test GenieTeam.count_open_tasks() + GenieTeam.count_done_tasks() == 8

    p = first(GenieTeam.projects_all())
    @test p.due_at !== nothing
    @test GenieTeam.project_task_count(p.id) > 0
end

# ---------------------------------------------------------------------------
# 3. Core CRUD + relationships (repository contract)
# ---------------------------------------------------------------------------
@testset "CRUD repository" begin
    project = GenieTeam.create_project!("Launch Week", "Ship the launch week site", nothing)
    @test project.id !== nothing
    @test project.name == "Launch Week"

    @test GenieTeam.project_name_taken("Launch Week")
    @test !GenieTeam.project_name_taken("launch week", project.id) # same project excluded

    member = GenieTeam.create_member!("Lena Vogel", "lena@genieteam.dev", "DevRel")
    @test GenieTeam.member_by_email("lena@genieteam.dev").id == member.id
    @test GenieTeam.member_email_taken("lena@genieteam.dev")
    @test !GenieTeam.member_email_taken("lena@genieteam.dev", member.id)

    task = GenieTeam.create_task!(project.id, member.id, "Write the launch post",
        "Draft for review", "todo", GenieTeam.iso_offset(3))
    @test task.id !== nothing
    @test task.project_id == project.id

    # Relationships: project -> tasks and member -> tasks resolve correctly.
    @test length(GenieTeam.tasks_for_project(project.id)) == 1
    @test length(GenieTeam.tasks_for_member(member.id)) == 1
    @test GenieTeam.tasks_for_project(project.id)[1].title == "Write the launch post"

    # Update persists (including status transitions).
    updated = GenieTeam.update_task!(task, project.id, member.id, "Write the launch post",
        "Approved draft", "done", GenieTeam.iso_offset(3))
    @test updated.status == "done"
    @test GenieTeam.task_by_id(task.id).status == "done"

    # FK-safe delete: a project holding tasks is protected at the DB level
    # (the app rejects first with a friendly message — this is the backstop).
    @test_throws Exception GenieTeam.delete_project!(project.id)
    @test GenieTeam.project_by_id(project.id) !== nothing

    # Children first, then parents.
    GenieTeam.delete_task!(task.id)
    GenieTeam.delete_project!(project.id)
    GenieTeam.delete_member!(member.id)
    @test GenieTeam.project_by_id(project.id) === nothing
    @test GenieTeam.member_by_id(member.id) === nothing
end

# ---------------------------------------------------------------------------
# 4. Session cookie signing + CSRF token comparison
# ---------------------------------------------------------------------------
@testset "session primitives" begin
    value = GenieTeam.signed_session_value("0123456789abcdef0123456789abcdef")
    @test startswith(value, "0123456789abcdef0123456789abcdef.")
    @test GenieTeam.verify_signed_session(value) == "0123456789abcdef0123456789abcdef"
    @test GenieTeam.verify_signed_session(value * "x") === nothing
    @test GenieTeam.verify_signed_session("0123456789abcdef0123456789abcdef.deadbeef") === nothing
end

# ---------------------------------------------------------------------------
# 5. HTTP contract: auth wall, login flow, CSRF, dashboard, create form,
#    status filter, logout (against an in-process Genie server).
# ---------------------------------------------------------------------------
@testset "HTTP app contract" begin
    server_socket = listen(ip"127.0.0.1", 0)
    port = Int(getsockname(server_socket)[2])

    GenieTeam.install_web_hooks!()
    GenieTeam.register_routes!()
    GenieTeam.Genie.config.server_document_root = GenieTeam.static_document_root()
    GenieTeam.Genie.Secrets.secret_token!(GenieTeam.app_secret())
    GenieTeam.Genie.Server.up(port, "127.0.0.1"; async = true, server = server_socket)

    base = "http://127.0.0.1:$port"
    cookie_jar = String[]

    """Header lookup (HTTP headers are a vector of pairs, not a Dict)."""
    function hh(r, name)
        for (k, v) in r.headers
            lowercase(string(k)) == lowercase(name) && return String(v)
        end
        ""
    end

    function req(method, path, body = nothing; headers = Dict{String,String}())
        h = copy(headers)
        if !isempty(cookie_jar)
            h["cookie"] = join(cookie_jar, "; ")
        end
        r = if body === nothing
            HTTP.request(method, base * path; headers = h,
                status_exception = false, redirect = false, readtimeout = 120, retry = false)
        else
            h["Content-Type"] = "application/x-www-form-urlencoded"
            HTTP.request(method, base * path, h, body;
                status_exception = false, redirect = false, readtimeout = 120, retry = false)
        end
        sc = hh(r, "Set-Cookie")
        if !isempty(sc)
            cookie_jar = [String(first(split(c, ';'))) for c in split(sc, ",")]
        end
        r
    end

    function csrf_of(html)
        m = match(r"name='_csrf' value='([a-f0-9]+)'", html)
        m === nothing ? "" : m.captures[1]
    end

    # Anonymous wall: every protected screen redirects to /login?next=...
    r_root = req("GET", "/")
    @test r_root.status == 302
    @test startswith(hh(r_root, "Location"), "/login")
    r_dash_anon = req("GET", "/dashboard")
    @test r_dash_anon.status == 302
    @test occursin("/login?next=", hh(r_dash_anon, "Location"))

    # Login screen renders with the demo hint + a CSRF token.
    r_login = req("GET", "/login")
    @test r_login.status == 200
    login_html = String(copy(r_login.body))
    @test occursin("Demo: cenius@cenius.ai / cenius", login_html)
    token = csrf_of(login_html)
    @test length(token) == 32

    # Wrong credentials: 200 + single non-enumerating error.
    bad = req("POST", "/login", "_csrf=$token&email=wrong@example.com&password=nope&next=")
    @test bad.status == 200
    @test occursin("Email or password is incorrect.", String(copy(bad.body)))

    # Missing CSRF on a state-changing POST => 403 before any state change.
    no_csrf = req("POST", "/login", "email=wrong@example.com&password=nope&next=")
    @test no_csrf.status == 403

    # Valid demo credentials: 302 toward the requested next page.
    ok = req("POST", "/login", "_csrf=$token&email=cenius@cenius.ai&password=cenius&next=/dashboard")
    @test ok.status == 302
    @test endswith(hh(ok, "Location"), "/dashboard")
    @test any(startswith(c, "gt_sid=") for c in cookie_jar)

    # Dashboard renders seeded content once authenticated + security headers.
    dash = req("GET", "/dashboard")
    @test dash.status == 200
    dash_html = String(copy(dash.body))
    @test occursin("Atlas Website Redesign", dash_html)
    @test occursin("Task status", dash_html)
    @test occursin("Sign out", dash_html)
    header_str = join([string(k) for (k, _) in dash.headers], " ")
    @test occursin("X-Frame-Options", header_str)
    @test occursin("Content-Security-Policy", header_str)
    @test occursin("X-Content-Type-Options", header_str)

    # Status filter contract: only in-progress tasks on ?status=in_progress.
    ip = String(copy(req("GET", "/tasks?status=in_progress").body))
    @test occursin("Build the new component library", ip)     # seeded in_progress
    @test !occursin("Audit current homepage content", ip)      # seeded todo

    # End-user create form persists: POST a plain project name, follow the
    # redirect, reload the index, and see the row again (survives reloads).
    new_page = String(copy(req("GET", "/projects/new").body))
    ptoken = csrf_of(new_page)
    created = req("POST", "/projects",
        "_csrf=$ptoken&name=Winter Cleanup&due_at=&description=Repository hygiene week.")
    @test created.status == 302
    @test occursin("/projects/", hh(created, "Location"))
    index_html = String(copy(req("GET", "/projects").body))
    @test occursin("Winter Cleanup", index_html)

    # A second authenticated GET still shows the persisted row.
    index_again = String(copy(req("GET", "/projects").body))
    @test occursin("Winter Cleanup", index_again)

    # Logout clears the session; /dashboard is walled off again.
    dash2 = String(copy(req("GET", "/dashboard").body))
    ltoken = csrf_of(dash2)
    out = req("POST", "/logout", "_csrf=$ltoken")
    @test out.status == 302
    @test endswith(hh(out, "Location"), "/login")
    after = req("GET", "/dashboard")
    @test after.status == 302
end

end # top-level testset
