# ---------------------------------------------------------------------------
# Domain models (plain Julia structs mirroring the SQLite schema).
# Persistence is handled by the Repo layer in db.jl using bound parameters.
# ---------------------------------------------------------------------------

"""
    User

Administrator account used only for signing into the workspace.
"""
Base.@kwdef mutable struct User
    id::Union{Int,Nothing} = nothing
    email::String = ""
    password_hash::String = ""
    password_salt::String = ""
    created_at::Union{String,Nothing} = nothing
    updated_at::Union{String,Nothing} = nothing
end

"""
    TeamMember

A person on the roster who can be assigned to tasks. Not a login account.
"""
Base.@kwdef mutable struct TeamMember
    id::Union{Int,Nothing} = nothing
    name::String = ""
    email::String = ""
    role::Union{String,Nothing} = nothing
    created_at::Union{String,Nothing} = nothing
    updated_at::Union{String,Nothing} = nothing
end

"""
    Project

A workspace project that owns tasks.
"""
Base.@kwdef mutable struct Project
    id::Union{Int,Nothing} = nothing
    name::String = ""
    description::Union{String,Nothing} = nothing
    due_at::Union{String,Nothing} = nothing   # ISO date (YYYY-MM-DD) or nothing
    created_at::Union{String,Nothing} = nothing
    updated_at::Union{String,Nothing} = nothing
end

"""
    Task

A unit of work that belongs to a project and may be assigned to a team member.
"""
Base.@kwdef mutable struct Task
    id::Union{Int,Nothing} = nothing
    project_id::Union{Int,Nothing} = nothing
    assignee_id::Union{Int,Nothing} = nothing
    title::String = ""
    description::Union{String,Nothing} = nothing
    status::String = "todo"
    priority::String = "medium"
    due_at::Union{String,Nothing} = nothing
    created_at::Union{String,Nothing} = nothing
    updated_at::Union{String,Nothing} = nothing
end

# The only statuses the app accepts; enforced on every write server-side.
const TASK_STATUSES = ("todo", "in_progress", "done")

# The only priorities the app accepts; enforced on every write server-side.
const TASK_PRIORITIES = ("low", "medium", "high")

const STATUS_LABELS = Dict(
    "todo" => "To do",
    "in_progress" => "In progress",
    "done" => "Done",
)

const PRIORITY_LABELS = Dict(
    "low" => "Low",
    "medium" => "Medium",
    "high" => "High",
)

"""Human readable label for a status key (falls back to the key itself)."""
status_label(s::AbstractString) = get(STATUS_LABELS, s, s)

"""Human readable label for a priority key (falls back to the key itself)."""
priority_label(s::AbstractString) = get(PRIORITY_LABELS, s, s)

"""True when the status is one of the allowed task statuses."""
function valid_status(s::AbstractString)::Bool
    s in TASK_STATUSES
end

"""True when the priority is one of the allowed task priorities."""
function valid_priority(s::AbstractString)::Bool
    s in TASK_PRIORITIES
end

"""True when the task is considered "open" (not done)."""
is_open_status(s::AbstractString) = !isempty(s) && s != "done"

# ---------------------------------------------------------------------------
# Row-mapping helpers used by the Repo layer (DataFrame rows -> model objects)
# ---------------------------------------------------------------------------

function _as_int(v)
    v === nothing && return nothing
    v === missing && return nothing
    return Int(v)
end

function _as_str(v)
    v === nothing && return ""
    v === missing && return ""
    return String(v)
end

function _as_optstr(v)
    v === nothing && return nothing
    v === missing && return nothing
    s = String(v)
    isempty(s) ? nothing : s
end

user_from_row(r) = User(
    id = _as_int(r[:id]),
    email = _as_str(r[:email]),
    password_hash = _as_str(r[:password_hash]),
    password_salt = _as_str(r[:password_salt]),
    created_at = _as_optstr(r[:created_at]),
    updated_at = _as_optstr(r[:updated_at]),
)

member_from_row(r) = TeamMember(
    id = _as_int(r[:id]),
    name = _as_str(r[:name]),
    email = _as_str(r[:email]),
    role = _as_optstr(r[:role]),
    created_at = _as_optstr(r[:created_at]),
    updated_at = _as_optstr(r[:updated_at]),
)

project_from_row(r) = Project(
    id = _as_int(r[:id]),
    name = _as_str(r[:name]),
    description = _as_optstr(r[:description]),
    due_at = _as_optstr(r[:due_at]),
    created_at = _as_optstr(r[:created_at]),
    updated_at = _as_optstr(r[:updated_at]),
)

function task_from_row(r)
    Task(
        id = _as_int(r[:id]),
        project_id = _as_int(r[:project_id]),
        assignee_id = _as_int(r[:assignee_id]),
        title = _as_str(r[:title]),
        description = _as_optstr(r[:description]),
        status = _as_str(r[:status]),
        priority = (:priority in propertynames(r)) ? _as_str(r[:priority]) : "medium",
        due_at = _as_optstr(r[:due_at]),
        created_at = _as_optstr(r[:created_at]),
        updated_at = _as_optstr(r[:updated_at]),
    )
end
