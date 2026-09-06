# ---------------------------------------------------------------------------
# Route registration + per-route guard wrappers (auth on protected routes,
# CSRF verification on every state-changing POST).
#
# Genie scans routes most-recently-registered first, so literal routes such as
# /projects/new MUST be registered after their parameterised siblings
# (/projects/:id) — otherwise "new" is captured as an id.
# ---------------------------------------------------------------------------

import HTTP

"""Redirects an unauthenticated visitor to /login?next=<original path>."""
function redirect_to_login_response()
    target = "/"
    req = Genie.Requests.request()
    if req !== nothing && !isempty(req.target)
        target = HTTP.URIs.unescapeuri(req.target)
    end
    dest = "/login"
    if !isempty(target)
        dest = "/login?next=" * HTTP.URIs.escapeuri(target)
    end
    redirect_response(dest)
end

"""Wraps a protected handler: redirect to login when not authenticated."""
function authed(f::Function)
    function ()
        if current_user() === nothing
            return redirect_to_login_response()
        end
        f()
    end
end

"""Wraps a POST handler: 403 unless a valid CSRF token accompanies the request."""
function csrf_guarded(f::Function)
    function ()
        if !csrf_valid()
            return csrf_denied_response()
        end
        f()
    end
end

const ROUTES_REGISTERED = Ref(false)

"""
    register_routes!() -> Nothing

Idempotent route registration (guarded so a process never double-registers).
"""
function register_routes!()
    ROUTES_REGISTERED[] && return nothing
    R = Genie.Router.route

    # --- Public ------------------------------------------------------------
    R("/", root_action; method = GET)
    R("/login", login_get_action; method = GET)
    R("/login", csrf_guarded(login_post_action); method = POST)

    # --- Authenticated shell ------------------------------------------------
    R("/dashboard", authed(dashboard_action); method = GET)

    # --- Logout (POST, CSRF-protected, authenticated) ------------------------
    R("/logout", csrf_guarded(authed(logout_post_action)); method = POST)

    # --- Projects -----------------------------------------------------------
    # Order matters: literal routes last so they are scanned first.
    R("/projects", authed(projects_index_action); method = GET)
    R("/projects/:id", authed(projects_show_action); method = GET)
    R("/projects/:id/edit", authed(projects_edit_action); method = GET)
    R("/projects/new", authed(projects_new_action); method = GET)
    R("/projects", csrf_guarded(authed(projects_create_action)); method = POST)
    R("/projects/:id/update", csrf_guarded(authed(projects_update_action)); method = POST)
    R("/projects/:id/delete", csrf_guarded(authed(projects_delete_action)); method = POST)

    # --- Tasks --------------------------------------------------------------
    R("/tasks", authed(tasks_index_action); method = GET)
    R("/tasks/:id", authed(tasks_show_action); method = GET)
    R("/tasks/:id/edit", authed(tasks_edit_action); method = GET)
    R("/tasks/new", authed(tasks_new_action); method = GET)
    R("/tasks", csrf_guarded(authed(tasks_create_action)); method = POST)
    R("/tasks/:id/update", csrf_guarded(authed(tasks_update_action)); method = POST)
    R("/tasks/:id/delete", csrf_guarded(authed(tasks_delete_action)); method = POST)

    # --- Team ----------------------------------------------------------------
    R("/team", authed(team_index_action); method = GET)
    R("/team/:id", authed(team_show_action); method = GET)
    R("/team/:id/edit", authed(team_edit_action); method = GET)
    R("/team/new", authed(team_new_action); method = GET)
    R("/team", csrf_guarded(authed(team_create_action)); method = POST)
    R("/team/:id/update", csrf_guarded(authed(team_update_action)); method = POST)
    R("/team/:id/delete", csrf_guarded(authed(team_delete_action)); method = POST)

    ROUTES_REGISTERED[] = true
    @info "Registered $(length(Genie.Router.routes())) routes."
    nothing
end

"""Standalone seed entrypoint used by install/seed scripts (never starts HTTP)."""
function seed_command()
    prepare_database!()
    counts = seed_demo_data!()
    @info "Seed complete: $(counts.admins) admins, $(counts.members) team members, $(counts.projects) projects, $(counts.tasks) tasks."
    nothing
end
