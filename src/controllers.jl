# ---------------------------------------------------------------------------
# Controllers: request handlers for every route. All reads are GET handlers;
# every state change is a POST handled behind the CSRF wrapper (see routes.jl).
# ---------------------------------------------------------------------------

import HTTP

# --- response helpers -------------------------------------------------------

"""Attaches the pending session cookie (or clears it after logout) to a response."""
function attach_session_cookie!(resp::HTTP.Response)::HTTP.Response
    if session_logout_pending()
        Genie.Cookies.set!(resp, SESSION_COOKIE, "",
            Dict{String,Any}("path" => "/", "httponly" => true, "samesite" => "lax", "maxage" => 0);
            encrypted = false)
    else
        value = session_cookie_to_attach()
        value !== nothing && Genie.Cookies.set!(resp, SESSION_COOKIE, value,
            Dict{String,Any}("path" => "/", "httponly" => true, "samesite" => "lax", "maxage" => SESSION_TTL_SECONDS);
            encrypted = false)
    end
    resp
end

"""HTML page response (200 by default) with session cookie applied."""
function page_response(body::String; status::Int = 200)::HTTP.Response
    resp = Genie.Renderer.respond(body, :html, status)
    attach_session_cookie!(resp)
    resp
end

"""Redirect response with session cookie applied."""
function redirect_response(location::AbstractString; status::Int = 302)::HTTP.Response
    resp = Genie.Renderer.redirect(String(location), status)
    attach_session_cookie!(resp)
    resp
end

"""403 page used when the CSRF token is missing or invalid."""
function csrf_denied_response()::HTTP.Response
    body = layout_standalone(
        status = 403,
        title = "This action could not be verified",
        message = "Your security token is missing or has expired. Go back, reload the page, and try again — this protects your session from cross-site request forgery.",
        action_html = btn("/login", "Sign in again", icon_name = "lock"),
    )
    page_response(body; status = 403)
end

"""Styled 404 page (logged-in and anonymous visitors both get a useful page)."""
function not_found_response(resource::String)::HTTP.Response
    body = layout_standalone(
        status = 404,
        title = "Page not found",
        message = "We couldn't find “$(resource)”. It may have been moved or deleted.",
    )
    page_response(body; status = 404)
end

"""Sanitizes a post-login redirect target (open-redirect safe)."""
function safe_redirect_target(raw)::String
    s = raw === nothing ? "" : strip(String(raw))
    (isempty(s) || length(s) > 512) && return "/dashboard"
    (startswith(s, "//") || occursin("://", s)) && return "/dashboard"
    path = split(s, "?")[1]
    for prefix in ("/dashboard", "/projects", "/tasks", "/team", "/login")
        (path == prefix || startswith(path, prefix * "/")) && return s
    end
    "/dashboard"
end

"""Reads an integer route/query param; nothing when absent or unparseable."""
function param_int(name::AbstractString)::Union{Int,Nothing}
    raw = Genie.Router.params(Symbol(name), nothing)
    raw === nothing && return nothing
    s = strip(String(raw))
    isempty(s) && return nothing
    tryparse(Int, s)
end

"""Reads a form/query parameter as a String; `default` when absent."""
function pstr(key::Symbol, default::String = "")
    v = Genie.Router.params(key, nothing)
    v === nothing ? default : string(v)
end

"""Builds project/member lookup maps used by every view."""
function build_lookups(projects::Vector{Project}, members::Vector{TeamMember})
    (pmap = Dict{Int,Project}(p.id => p for p in projects),
     mmap = Dict{Int,TeamMember}(m.id => m for m in members))
end

# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

function login_get_action()
    is_authenticated() && return redirect_response("/dashboard")

    next = Genie.Router.params(:next, "")
    content = layout_auth(content = page_login(Dict{String,String}(), "", next, false))
    page_response(content)
end

function login_post_action()
    email = normalize_email(pstr(:email))
    password = string(pstr(:password))
    next = safe_redirect_target(Genie.Router.params(:next, ""))

    errors = Dict{String,String}()

    if login_locked_out()
        content = layout_auth(content = page_login(errors, email, next, true))
        return page_response(content)
    end

    user = isempty(email) ? nothing : user_by_email(email)
    if user === nothing || !PasswordHasher.verify_password(password, user.password_hash, user.password_salt)
        register_failed_login!()
        errors["__form__"] = "Email or password is incorrect."
        content = layout_auth(content = page_login(errors, email, next, false))
        return page_response(content)
    end

    login_user!(user)
    clear_login_failures!()
    flash_success("Welcome back, $(split(user.email, "@")[1])!")
    redirect_response(next)
end

function logout_post_action()
    logout_user!()
    redirect_response("/login")
end

function root_action()
    is_authenticated() ? redirect_response("/dashboard") : redirect_response("/login")
end

# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------

function dashboard_action()
    projects = projects_all()
    members = members_all()
    lookups = build_lookups(projects, members)
    pmap = lookups.pmap
    mmap = lookups.mmap

    task_counts = Dict{Int,Int}(p.id => project_task_count(p.id) for p in projects)
    status_counts = status_totals()
    today = today_local()

    all_tasks = tasks_all()
    overdue = [t for t in all_tasks if is_open_status(t.status) && (d = parse_stored_date(t.due_at); d !== nothing && d < today)]
    upcoming = [t for t in all_tasks if is_open_status(t.status) && (d = parse_stored_date(t.due_at); d !== nothing && today <= d <= today + Dates.Day(14))]

    content = page_dashboard(
        projects = projects,
        project_task_counts = task_counts,
        status_counts = status_counts,
        overdue = overdue,
        upcoming = upcoming,
        pmap = pmap,
        mmap = mmap,
        members_count = length(members),
    )

    actions = btn("/tasks/new", "New task", icon_name = "plus") * btn("/projects/new", "New project", kind = "secondary", icon_name = "plus")
    page_response(layout_app(
        section = "dashboard",
        title = "Dashboard",
        subtitle = "A live view of projects, tasks and the team.",
        actions = actions,
        content = content,
    ))
end

# ---------------------------------------------------------------------------
# Projects
# ---------------------------------------------------------------------------

function projects_index_action()
    projects = projects_all()
    counts = Dict{Int,Int}(p.id => project_task_count(p.id) for p in projects)
    content = page_projects_index(projects, counts)
    actions = btn("/projects/new", "New project", icon_name = "plus")
    page_response(layout_app(section = "projects", title = "Projects", subtitle = "Everything ships through a project.", actions = actions, content = content))
end

function projects_new_action()
    content = page_project_form(mode = :new, project = nothing, errors = Dict{String,String}(), values = Dict{String,String}())
    page_response(layout_app(section = "projects", title = "New project", content = content))
end

function projects_create_action()
    name = String(strip(pstr(:name)))
    description = string(pstr(:description))
    due_raw = string(pstr(:due_at))

    errors = Dict{String,String}()
    isempty(name) && (errors["name"] = "Project name is required.")
    length(name) > 120 && (errors["name"] = "Project name must be 120 characters or fewer.")
    project_name_taken(name) && (errors["name"] = "A project named “$(name)” already exists.")

    due_at = nothing
    if !isempty(due_raw)
        try
            due_at = normalize_iso_date(due_raw)
        catch
            errors["due_at"] = "Enter a valid date (YYYY-MM-DD)."
        end
    end

    if !isempty(errors)
        values = Dict("name" => name, "description" => description, "due_at" => due_raw)
        content = page_project_form(mode = :new, project = nothing, errors = errors, values = values)
        return page_response(layout_app(section = "projects", title = "New project", content = content))
    end

    project = create_project!(name, description, due_at)
    flash_success("Project “$(project.name)” was created.")
    redirect_response("/projects/$(project.id)")
end

function projects_show_action()
    id = param_int("id")
    id === nothing && return not_found_response("/projects/…")
    project = project_by_id(id)
    project === nothing && return not_found_response("/projects/$id")

    projects = projects_all()
    members = members_all()
    lookups = build_lookups(projects, members)
    tasks = tasks_for_project(project.id)
    content = page_project_show(project, tasks, lookups.pmap, lookups.mmap)
    page_response(layout_app(section = "projects", title = project.name, content = content))
end

function projects_edit_action()
    id = param_int("id")
    id === nothing && return not_found_response("/projects/…")
    project = project_by_id(id)
    project === nothing && return not_found_response("/projects/$id")

    content = page_project_form(mode = :edit, project = project, errors = Dict{String,String}(), values = Dict{String,String}())
    page_response(layout_app(section = "projects", title = "Edit project", content = content))
end

function projects_update_action()
    id = param_int("id")
    id === nothing && return not_found_response("/projects/…")
    project = project_by_id(id)
    project === nothing && return not_found_response("/projects/$id")

    name = String(strip(pstr(:name)))
    description = string(pstr(:description))
    due_raw = string(pstr(:due_at))

    errors = Dict{String,String}()
    isempty(name) && (errors["name"] = "Project name is required.")
    length(name) > 120 && (errors["name"] = "Project name must be 120 characters or fewer.")
    project_name_taken(name, project.id) && (errors["name"] = "A project named “$(name)” already exists.")

    due_at = nothing
    if !isempty(due_raw)
        try
            due_at = normalize_iso_date(due_raw)
        catch
            errors["due_at"] = "Enter a valid date (YYYY-MM-DD)."
        end
    end

    if !isempty(errors)
        values = Dict("name" => name, "description" => description, "due_at" => due_raw)
        content = page_project_form(mode = :edit, project = project, errors = errors, values = values)
        return page_response(layout_app(section = "projects", title = "Edit project", content = content))
    end

    updated = update_project!(project, name, description, due_at)
    flash_success("Project “$(updated.name)” was updated.")
    redirect_response("/projects/$(updated.id)")
end

function projects_delete_action()
    id = param_int("id")
    id === nothing && return not_found_response("/projects/…")
    project = project_by_id(id)
    project === nothing && return not_found_response("/projects/$id")

    confirmed = string(pstr(:confirm)) == "yes"
    if !confirmed
        flash_error("Deletion cancelled — please confirm to delete the project.")
        return redirect_response("/projects/$(project.id)")
    end

    task_count = project_task_count(project.id)
    if task_count > 0
        flash_error("Project “$(project.name)” can't be deleted while it still has $task_count task$(task_count == 1 ? "" : "s").")
        return redirect_response("/projects/$(project.id)")
    end

    delete_project!(project.id)
    flash_success("Project “$(project.name)” was deleted.")
    redirect_response("/projects")
end

# ---------------------------------------------------------------------------
# Tasks
# ---------------------------------------------------------------------------

function tasks_index_action()
    status = string(pstr(:status))
    valid_status(status) || (status = "")
    project_filter = param_int("project_id")

    projects = projects_all()
    members = members_all()
    lookups = build_lookups(projects, members)

    all_by_status = tasks_all(status)
    tasks = if project_filter === nothing
        all_by_status
    else
        [t for t in all_by_status if t.project_id == project_filter]
    end

    counts = status_totals()
    content = page_tasks_index(tasks, status, counts, lookups.pmap, lookups.mmap, project_filter)
    title = project_filter === nothing ? "Tasks" : "Project tasks"
    subtitle = project_filter === nothing ? "Every piece of work across the workspace." : ""
    page_response(layout_app(section = "tasks", title = title, subtitle = subtitle, content = content))
end

function _task_form_values(; task::Union{Task,Nothing}, mode::Symbol)
    values = Dict{String,String}()
    # Pre-select the project when arriving from a project page (?project_id=).
    if mode == :new
        preselect = param_int("project_id")
        preselect !== nothing && (values["project_id"] = string(preselect))
    end
    values
end

function tasks_new_action()
    values = _task_form_values(task = nothing, mode = :new)
    projects = projects_all()
    members = members_all()
    lookups = build_lookups(projects, members)
    content = page_task_form(mode = :new, task = nothing, errors = Dict{String,String}(), values = values, pmap = lookups.pmap, mmap = lookups.mmap)
    page_response(layout_app(section = "tasks", title = "New task", content = content))
end

function tasks_create_action()
    title = String(strip(pstr(:title)))
    description = string(pstr(:description))
    status = pstr(:status, "todo")
    due_raw = string(pstr(:due_at))
    project_id = param_int("project_id")
    assignee_id = param_int("assignee_id")

    errors = Dict{String,String}()
    isempty(title) && (errors["title"] = "Task title is required.")
    length(title) > 160 && (errors["title"] = "Task title must be 160 characters or fewer.")
    project_id === nothing && (errors["project_id"] = "Choose a project for this task.")
    if project_id !== nothing && project_by_id(project_id) === nothing
        errors["project_id"] = "That project no longer exists."
    end
    if assignee_id !== nothing && member_by_id(assignee_id) === nothing
        errors["assignee_id"] = "That team member no longer exists."
    end
    if !valid_status(status)
        errors["status"] = "Status must be one of: todo, in_progress, done."
    end
    due_at = nothing
    if !isempty(due_raw)
        try
            due_at = normalize_iso_date(due_raw)
        catch
            errors["due_at"] = "Enter a valid date (YYYY-MM-DD)."
        end
    end

    if !isempty(errors)
        projects = projects_all()
        members = members_all()
        lookups = build_lookups(projects, members)
        values = Dict{String,String}(
            "title" => title,
            "description" => description,
            "status" => status,
            "due_at" => due_raw,
            "project_id" => project_id === nothing ? "" : string(project_id),
            "assignee_id" => assignee_id === nothing ? "" : string(assignee_id),
        )
        content = page_task_form(mode = :new, task = nothing, errors = errors, values = values, pmap = lookups.pmap, mmap = lookups.mmap)
        return page_response(layout_app(section = "tasks", title = "New task", content = content))
    end

    task = create_task!(project_id, assignee_id, title, description, status, due_at)
    flash_success("Task “$(task.title)” was created.")
    redirect_response("/tasks/$(task.id)")
end

function tasks_show_action()
    id = param_int("id")
    id === nothing && return not_found_response("/tasks/…")
    task = task_by_id(id)
    task === nothing && return not_found_response("/tasks/$id")

    projects = projects_all()
    members = members_all()
    lookups = build_lookups(projects, members)
    content = page_task_show(task, lookups.pmap, lookups.mmap)
    page_response(layout_app(section = "tasks", title = task.title, content = content))
end

function tasks_edit_action()
    id = param_int("id")
    id === nothing && return not_found_response("/tasks/…")
    task = task_by_id(id)
    task === nothing && return not_found_response("/tasks/$id")

    projects = projects_all()
    members = members_all()
    lookups = build_lookups(projects, members)
    content = page_task_form(mode = :edit, task = task, errors = Dict{String,String}(), values = Dict{String,String}(), pmap = lookups.pmap, mmap = lookups.mmap)
    page_response(layout_app(section = "tasks", title = "Edit task", content = content))
end

function tasks_update_action()
    id = param_int("id")
    id === nothing && return not_found_response("/tasks/…")
    task = task_by_id(id)
    task === nothing && return not_found_response("/tasks/$id")

    title = String(strip(pstr(:title)))
    description = string(pstr(:description))
    status = pstr(:status, "todo")
    due_raw = string(pstr(:due_at))
    project_id = param_int("project_id")
    assignee_id = param_int("assignee_id")

    errors = Dict{String,String}()
    isempty(title) && (errors["title"] = "Task title is required.")
    length(title) > 160 && (errors["title"] = "Task title must be 160 characters or fewer.")
    project_id === nothing && (errors["project_id"] = "Choose a project for this task.")
    if project_id !== nothing && project_by_id(project_id) === nothing
        errors["project_id"] = "That project no longer exists."
    end
    if assignee_id !== nothing && member_by_id(assignee_id) === nothing
        errors["assignee_id"] = "That team member no longer exists."
    end
    if !valid_status(status)
        errors["status"] = "Status must be one of: todo, in_progress, done."
    end
    due_at = nothing
    if !isempty(due_raw)
        try
            due_at = normalize_iso_date(due_raw)
        catch
            errors["due_at"] = "Enter a valid date (YYYY-MM-DD)."
        end
    end

    if !isempty(errors)
        projects = projects_all()
        members = members_all()
        lookups = build_lookups(projects, members)
        values = Dict{String,String}(
            "title" => title,
            "description" => description,
            "status" => status,
            "due_at" => due_raw,
            "project_id" => project_id === nothing ? "" : string(project_id),
            "assignee_id" => assignee_id === nothing ? "" : string(assignee_id),
        )
        content = page_task_form(mode = :edit, task = task, errors = errors, values = values, pmap = lookups.pmap, mmap = lookups.mmap)
        return page_response(layout_app(section = "tasks", title = "Edit task", content = content))
    end

    updated = update_task!(task, project_id, assignee_id, title, description, status, due_at)
    flash_success("Task “$(updated.title)” was updated.")
    redirect_response("/tasks/$(updated.id)")
end

function tasks_delete_action()
    id = param_int("id")
    id === nothing && return not_found_response("/tasks/…")
    task = task_by_id(id)
    task === nothing && return not_found_response("/tasks/$id")

    confirmed = string(pstr(:confirm)) == "yes"
    if !confirmed
        flash_error("Deletion cancelled — please confirm to delete the task.")
        return redirect_response("/tasks/$(task.id)")
    end

    delete_task!(task.id)
    flash_success("Task “$(task.title)” was deleted.")
    redirect_response("/tasks")
end

# ---------------------------------------------------------------------------
# Team
# ---------------------------------------------------------------------------

function team_index_action()
    members = members_all()
    counts = member_task_counts()
    content = page_team_index(members, counts)
    actions = btn("/team/new", "Add member", icon_name = "plus")
    page_response(layout_app(section = "team", title = "Team", subtitle = "The people doing the work.", actions = actions, content = content))
end

function team_new_action()
    content = page_team_form(mode = :new, member = nothing, errors = Dict{String,String}(), values = Dict{String,String}())
    page_response(layout_app(section = "team", title = "Add team member", content = content))
end

function _validate_member(name::AbstractString, email::AbstractString, role::AbstractString, member_id::Union{Int,Nothing})::Dict{String,String}
    errors = Dict{String,String}()
    isempty(name) && (errors["name"] = "Full name is required.")
    length(name) > 120 && (errors["name"] = "Name must be 120 characters or fewer.")
    isempty(email) && (errors["email"] = "Email address is required.")
    !valid_email(email) && (errors["email"] = "Enter a valid email address, e.g. amara@company.com.")
    length(email) > 190 && (errors["email"] = "Email must be 190 characters or fewer.")
    if !isempty(email) && valid_email(email) && member_email_taken(email, member_id)
        errors["email"] = "A team member with “$(email)” already exists."
    end
    length(role) > 120 && (errors["role"] = "Role must be 120 characters or fewer.")
    errors
end

function team_create_action()
    name = String(strip(pstr(:name)))
    email = normalize_email(string(pstr(:email)))
    role = String(strip(pstr(:role)))

    errors = _validate_member(name, email, role, nothing)
    if !isempty(errors)
        values = Dict("name" => name, "email" => email, "role" => role)
        content = page_team_form(mode = :new, member = nothing, errors = errors, values = values)
        return page_response(layout_app(section = "team", title = "Add team member", content = content))
    end

    member = create_member!(name, email, isempty(role) ? nothing : role)
    flash_success("$(member.name) was added to the team.")
    redirect_response("/team/$(member.id)")
end

function team_show_action()
    id = param_int("id")
    id === nothing && return not_found_response("/team/…")
    member = member_by_id(id)
    member === nothing && return not_found_response("/team/$id")

    projects = projects_all()
    lookups = build_lookups(projects, TeamMember[])
    tasks = tasks_for_member(member.id)
    content = page_team_show(member, tasks, lookups.pmap)
    page_response(layout_app(section = "team", title = member.name, content = content))
end

function team_edit_action()
    id = param_int("id")
    id === nothing && return not_found_response("/team/…")
    member = member_by_id(id)
    member === nothing && return not_found_response("/team/$id")

    content = page_team_form(mode = :edit, member = member, errors = Dict{String,String}(), values = Dict{String,String}())
    page_response(layout_app(section = "team", title = "Edit team member", content = content))
end

function team_update_action()
    id = param_int("id")
    id === nothing && return not_found_response("/team/…")
    member = member_by_id(id)
    member === nothing && return not_found_response("/team/$id")

    name = String(strip(pstr(:name)))
    email = normalize_email(string(pstr(:email)))
    role = String(strip(pstr(:role)))

    errors = _validate_member(name, email, role, member.id)
    if !isempty(errors)
        values = Dict("name" => name, "email" => email, "role" => role)
        content = page_team_form(mode = :edit, member = member, errors = errors, values = values)
        return page_response(layout_app(section = "team", title = "Edit team member", content = content))
    end

    updated = update_member!(member, name, email, isempty(role) ? nothing : role)
    flash_success("$(updated.name)'s profile was updated.")
    redirect_response("/team/$(updated.id)")
end

function team_delete_action()
    id = param_int("id")
    id === nothing && return not_found_response("/team/…")
    member = member_by_id(id)
    member === nothing && return not_found_response("/team/$id")

    confirmed = string(pstr(:confirm)) == "yes"
    if !confirmed
        flash_error("Removal cancelled — please confirm to remove the member.")
        return redirect_response("/team/$(member.id)")
    end

    assigned = member_task_count(member.id)
    if assigned > 0
        flash_error("$(member.name) can't be removed while they still have $assigned assigned task$(assigned == 1 ? "" : "s").")
        return redirect_response("/team/$(member.id)")
    end

    delete_member!(member.id)
    flash_success("$(member.name) was removed from the team.")
    redirect_response("/team")
end
