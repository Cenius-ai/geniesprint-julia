# ---------------------------------------------------------------------------
# Task pages
# ---------------------------------------------------------------------------

"""Assignee display name from maps (nil-safe)."""
function assignee_name(assignee_id, mmap::Dict{Int,TeamMember})::String
    assignee_id === nothing && return "Unassigned"
    m = get(mmap, assignee_id, nothing)
    m === nothing ? "Unassigned" : m.name
end

"""Project display name from maps (nil-safe)."""
function project_name(project_id, pmap::Dict{Int,Project})::String
    p = get(pmap, project_id, nothing)
    p === nothing ? "Unknown project" : p.name
end

const STATUS_FILTERS = [
    ("", "All"),
    ("todo", "To do"),
    ("in_progress", "In progress"),
    ("done", "Done"),
]

function status_filter_html(current_status::AbstractString, counts::Dict{String,Int}, extra_query::String = "")
    path = current_path()
    chips = String[]
    for (value, label) in STATUS_FILTERS
        n = isempty(value) ? sum(values(counts)) : get(counts, value, 0)
        href = isempty(value) ? path : path * "?status=" * value * extra_query
        active = current_status == value
        cls = active ? "chip chip--active" : "chip"
        aria = active ? " aria-current='true'" : ""
        push!(chips, "<a class='$(cls)' href='$(href)'$(aria)><span>$(label)</span><span class='chip__count'>$(n)</span></a>")
    end
    "<div class='chips' role='group' aria-label='Filter tasks by status'>$(join(chips, ""))</div>"
end

"""
    page_tasks_index(tasks, current_status, counts, pmap, mmap, project_filter) -> String

Task list with status filter chips. Every row links to its detail page.
"""
function page_tasks_index(tasks::Vector{Task}, current_status::AbstractString, counts::Dict{String,Int}, pmap::Dict{Int,Project}, mmap::Dict{Int,TeamMember}, project_filter::Union{Int,Nothing})::String
    projects_exist = !isempty(pmap)
    extra_query = project_filter === nothing ? "" : "&project_id=$(project_filter)"

    if !projects_exist
        return empty_state(
            "Tasks",
            "Create a project first",
            "Tasks belong to projects. Add your first project and you'll be able to plan tasks inside it.",
            "<div class='empty__actions'>" * btn("/projects/new", "New project", icon_name = "plus") * "</div>",
        )
    end

    if isempty(tasks)
        add_action = btn("/tasks/new", "New task", icon_name = "plus")
        return status_filter_html(current_status, counts, extra_query) *
            empty_state(
                "Tasks",
                project_filter === nothing ? "No tasks yet" : "No tasks match this filter",
                project_filter === nothing ? "Create the first task and assign it to someone on the team." : "Try a different status filter, or add a new task.",
                "<div class='empty__actions'>" * add_action * "</div>",
            )
    end

    rows = String[]
    for t in tasks
        due = t.due_at === nothing ? "<span class='due due--none'>—</span>" : due_chip(t.due_at, t.status == "done")
        push!(rows, """
        <tr>
          <td data-label="Task">
            <a class="row-title" href="/tasks/$(t.id)">$(esc(t.title))</a>
            <span class="row-meta">$(status_pill(t.status))</span>
          </td>
          <td data-label="Project"><a class="table-link" href="/projects/$(t.project_id)">$(esc(project_name(t.project_id, pmap)))</a></td>
          <td data-label="Assignee">$(esc(assignee_name(t.assignee_id, mmap)))</td>
          <td data-label="Due date">$(due)</td>
          <td class="row-actions">
            <a class="btn btn--ghost btn--sm" href="/tasks/$(t.id)">View</a>
            <a class="btn btn--ghost btn--sm" href="/tasks/$(t.id)/edit">$(icon("edit", size = 14))<span>Edit</span></a>
          </td>
        </tr>""")
    end

    filter_label = project_filter === nothing ? "All projects" : "in “$(esc(project_name(project_filter, pmap)))”"
    """
    $(status_filter_html(current_status, counts, extra_query))
    <div class="panel">
      <div class="panel__head">
        <div><h2 class="panel__title">$(project_filter === nothing ? "All tasks" : "Project tasks")</h2><p class="panel__sub">$(length(tasks)) task$(length(tasks) == 1 ? "" : "s") · $(filter_label)</p></div>
        $(btn("/tasks/new", "New task", icon_name = "plus"))
      </div>
      <div class="table-scroll">
        <table class="table">
          <thead><tr><th>Task</th><th>Project</th><th>Assignee</th><th>Due date</th><th class="th-actions"><span class="visually-hidden">Actions</span></th></tr></thead>
          <tbody>$(join(rows, ""))</tbody>
        </table>
      </div>
    </div>"""
end

"""
    page_task_form(; mode, task, errors, values, pmap, mmap) -> String

New/edit task form with project + assignee pickers, status select (edit only
keeps creating defaults to todo) and due-date validation.
"""
function page_task_form(; mode::Symbol, task::Union{Task,Nothing}, errors::Dict{String,String}, values::Dict{String,String}, pmap::Dict{Int,Project}, mmap::Dict{Int,TeamMember})
    is_edit = mode == :edit
    action = is_edit ? "/tasks/$(task.id)/update" : "/tasks"

    if isempty(pmap)
        return empty_state(
            "Task setup",
            "No project to add this task to",
            "Every task lives inside a project. Create a project first, then come back to plan tasks.",
            "<div class='empty__actions'>" * btn("/projects/new", "Create a project", icon_name = "folder") * "</div>",
        )
    end

    title = is_edit ? "Edit task" : "New task"
    subtitle = is_edit ? "Update the task details — including its status." : "Plan a piece of work and assign it."

    # Values: prefer re-submitted values; fall back to the persisted model.
    title_val = get(values, "title", is_edit ? task.title : "")
    desc_val = get(values, "description", is_edit ? something(task.description, "") : "")
    status_val = get(values, "status", is_edit ? task.status : "todo")
    due_val = get(values, "due_at", is_edit ? something(task.due_at, "") : "")
    project_id_val = get(values, "project_id", is_edit ? string(task.project_id) : "")
    assignee_id_val = get(values, "assignee_id", is_edit && task.assignee_id !== nothing ? string(task.assignee_id) : "")

    project_options = [string(p.id) => p.name for p in sort(collect(Base.values(pmap)); by = p -> p.name)]
    member_options = [string(m.id) => m.name for m in sort(collect(Base.values(mmap)); by = m -> m.name)]

    status_select = is_edit ? select_field("status", "Status", [s => status_label(s) for s in TASK_STATUSES], status_val; errors = errors, required = true) : ""

    """
    <div class="panel panel--form">
      <div class="panel__head">
        <div><h2 class="panel__title">$(title)</h2><p class="panel__sub">$(subtitle)</p></div>
      </div>
      $(error_summary(errors))
      <form method="post" action="$(action)" class="form" data-submit-guard novalidate>
        $(csrf_input())
        $(text_field("title", "Title", title_val; errors = errors, placeholder = "e.g. Finalize push notification copy", required = true, maxlength = "160"))
        $(select_field("project_id", "Project", project_options, project_id_val; errors = errors, placeholder = "Choose a project…", required = true))
        $(select_field("assignee_id", "Assignee", member_options, assignee_id_val; errors = errors, placeholder = "Unassigned"))
        $(status_select)
        $(date_field("due_at", "Due date", isempty(due_val) ? nothing : due_val; errors = errors))
        $(textarea_field("description", "Description", isempty(desc_val) ? nothing : desc_val; errors = errors, rows = 5, placeholder = "Add context, acceptance criteria, or links."))
        $(REQUIRED_HINT)
        <div class="form__actions">
          $(btn_submit(is_edit ? "Save changes" : "Create task", icon_name = "check"))
          <a class="btn btn--ghost" href="$(is_edit ? "/tasks/$(task.id)" : "/tasks")">Cancel</a>
        </div>
      </form>
    </div>"""
end

"""
    page_task_show(task, pmap, mmap, can_edit_projects::Bool = true) -> String

Task detail with project/assignee/status/due/description plus delete form.
"""
function page_task_show(task::Task, pmap::Dict{Int,Project}, mmap::Dict{Int,TeamMember})::String
    proj = get(pmap, task.project_id, nothing)
    proj_name = proj === nothing ? "Unknown project" : proj.name
    assignee = task.assignee_id === nothing ? nothing : get(mmap, task.assignee_id, nothing)

    due_html = task.due_at === nothing ? "<span class='due due--none'>No due date</span>" : due_chip(task.due_at, task.status == "done")
    assignee_html = if assignee === nothing
        "<span class='muted-inline'>Unassigned — no one owns this yet.</span>"
    else
        "<span class='avatar avatar--sm' aria-hidden='true'>$(esc(uppercase(first(assignee.name))))</span> $(esc(assignee.name))"
    end

    description = (task.description === nothing || isempty(task.description)) ? "" :
        "<section class='panel'><div class='panel__head'><h2 class='panel__title'>Description</h2></div><p class='prose'>$(esc(task.description))</p></section>"

    meta = """
    <div class="meta-grid meta-grid--task">
      <div class="meta-cell"><span class="meta-cell__label">Status</span><span class="meta-cell__value">$(status_pill(task.status))</span></div>
      <div class="meta-cell"><span class="meta-cell__label">Project</span><span class="meta-cell__value">$(proj === nothing ? esc(proj_name) : "<a class='table-link' href='/projects/$(proj.id)'>" * esc(proj_name) * "</a>")</span></div>
      <div class="meta-cell"><span class="meta-cell__label">Assignee</span><span class="meta-cell__value">$(assignee_html)</span></div>
      <div class="meta-cell"><span class="meta-cell__label">Due date</span><span class="meta-cell__value">$(due_html)</span></div>
      <div class="meta-cell"><span class="meta-cell__label">Created</span><span class="meta-cell__value">$(esc(pretty_dt(task.created_at)))</span></div>
    </div>"""

    """
    <div class="detail-stack">
      <section class="panel">
        <div class="panel__head">
          <div>
            <p class="eyebrow"><a class="table-link" href="/projects/$(task.project_id)">$(esc(proj_name))</a></p>
            <h2 class="panel__title panel__title--xl">$(esc(task.title))</h2>
            <p class="panel__sub">Task #$(task.id) · created $(esc(pretty_dt(task.created_at)))</p>
          </div>
          <div class="row-actions">
            $(btn("/tasks/$(task.id)/edit", "Edit", kind = "ghost", icon_name = "edit"))
          </div>
        </div>
        $(meta)
      </section>
      $(description)
      <div class="panel panel--danger">
        <div class="panel__head"><div><h2 class="panel__title">Delete task</h2><p class="panel__sub">Removing the task leaves its project and team intact.</p></div></div>
        <form method="post" action="/tasks/$(task.id)/delete" class="form form--danger" data-submit-guard novalidate>
          $(csrf_input())
          $(confirm_checkbox("confirm", "Yes, permanently delete “$(esc(task.title))”. This cannot be undone."))
          $(btn_submit("Delete task", kind = "destructive", icon_name = "trash", data_state = "Deleting…"))
        </form>
      </div>
    </div>"""
end
