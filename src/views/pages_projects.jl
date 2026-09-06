# ---------------------------------------------------------------------------
# Project pages
# ---------------------------------------------------------------------------

"""
    page_projects_index(projects::Vector{Project}, task_counts::Dict{Int,Int}) -> String
"""
function page_projects_index(projects::Vector{Project}, task_counts::Dict{Int,Int})::String
    if isempty(projects)
        return empty_state(
            "Projects",
            "No projects yet",
            "Create your first project to give the workspace a shape — every task lives inside a project.",
            "<div class='empty__actions'>" * btn("/projects/new", "New project", icon_name = "plus") * "</div>",
        )
    end

    rows = String[]
    for p in projects
        due = p.due_at === nothing ? "<span class='due due--none'>No due date</span>" : due_chip(p.due_at)
        count = get(task_counts, p.id, 0)
        count_badge = count == 0 ? "<span class='count-pill count-pill--zero'>0 tasks</span>" : "<span class='count-pill'>$(count) task$(count == 1 ? "" : "s")</span>"
        desc = isempty(p.description === nothing ? "" : p.description) ? "<span class='muted-inline'>No description</span>" : "<span class='row-desc'>$(esc(truncate_text(p.description, 72)))</span>"
        push!(rows, """
        <tr>
          <td data-label="Project">
            <a class="row-title" href="/projects/$(p.id)">$(esc(p.name))</a>
            <span class="row-meta">$(desc)</span>
          </td>
          <td data-label="Due date">$(due)</td>
          <td data-label="Tasks">$(count_badge)</td>
          <td class="row-actions">
            <a class="btn btn--ghost btn--sm" href="/projects/$(p.id)">View</a>
            <a class="btn btn--ghost btn--sm" href="/projects/$(p.id)/edit">$(icon("edit", size = 14))<span>Edit</span></a>
          </td>
        </tr>""")
    end

    """
    <div class="panel">
      <div class="panel__head">
        <div><h2 class="panel__title">All projects</h2><p class="panel__sub">$(length(projects)) project$(length(projects) == 1 ? "" : "s") · sorted by due date</p></div>
        $(btn("/projects/new", "New project", icon_name = "plus"))
      </div>
      <div class="table-scroll">
        <table class="table">
          <thead><tr><th>Project</th><th>Due date</th><th>Progress</th><th class="th-actions"><span class="visually-hidden">Actions</span></th></tr></thead>
          <tbody>$(join(rows, ""))</tbody>
        </table>
      </div>
    </div>"""
end

function truncate_text(s::AbstractString, n::Int)::String
    length(s) <= n && return String(s)
    String(s[1:n]) * "…"
end

"""
    page_project_form(; mode, project, errors, values) -> String

Shared new/edit form body. `project` is the persisted model on edit,
`values` carries user-entered fields when re-rendering after validation.
"""
function page_project_form(; mode::Symbol, project::Union{Project,Nothing}, errors::Dict{String,String}, values::Dict{String,String})
    is_edit = mode == :edit
    post_url = is_edit ? "/projects/$(project.id)/update" : "/projects"
    title = is_edit ? "Edit project" : "New project"
    subtitle = is_edit ? "Update the project details below." : "Give the new project a name and, optionally, a target date."

    name_val = get(values, "name", is_edit ? project.name : "")
    desc_val = get(values, "description", is_edit ? something(project.description, "") : "")
    due_val = get(values, "due_at", is_edit ? something(project.due_at, "") : "")

    """
    <div class="panel panel--form">
      <div class="panel__head">
        <div><h2 class="panel__title">$(title)</h2><p class="panel__sub">$(subtitle)</p></div>
      </div>
      $(error_summary(errors))
      <form method="post" action="$(post_url)" class="form" data-submit-guard novalidate>
        $(csrf_input())
        $(text_field("name", "Project name", name_val; errors = errors, placeholder = "e.g. Atlas Website Redesign", required = true, maxlength = "120"))
        $(date_field("due_at", "Due date", isempty(due_val) ? nothing : due_val; errors = errors))
        $(textarea_field("description", "Description", isempty(desc_val) ? nothing : desc_val; errors = errors, rows = 5, placeholder = "What is this project trying to achieve?"))
        $(REQUIRED_HINT)
        <div class="form__actions">
          $(btn_submit(is_edit ? "Save changes" : "Create project", icon_name = "check"))
          <a class="btn btn--ghost" href="$(is_edit ? "/projects/$(project.id)" : "/projects")">Cancel</a>
        </div>
      </form>
    </div>"""
end

"""
    page_project_show(project, tasks, pmap, mmap) -> String

Project detail: metadata panel + task list + edit action and (when no tasks
exist) the delete confirmation form.
"""
function page_project_show(project::Project, tasks::Vector{Task}, pmap::Dict{Int,Project}, mmap::Dict{Int,TeamMember})::String
    open_count = count(t -> t.status != "done", tasks)
    due_html = project.due_at === nothing ? "<span class='due due--none'>No due date</span>" : due_chip(project.due_at)

    meta = """
    <div class="meta-grid">
      <div class="meta-cell"><span class="meta-cell__label">Status</span><span class="meta-cell__value"><span class="pill pill--in_progress"><span class="pill__dot"></span>Active</span></span></div>
      <div class="meta-cell"><span class="meta-cell__label">Due date</span><span class="meta-cell__value">$(due_html)</span></div>
      <div class="meta-cell"><span class="meta-cell__label">Created</span><span class="meta-cell__value">$(esc(pretty_dt(project.created_at)))</span></div>
      <div class="meta-cell"><span class="meta-cell__label">Tasks</span><span class="meta-cell__value"><strong>$(length(tasks))</strong> total · $(open_count) open</span></div>
    </div>"""

    description = (project.description === nothing || isempty(project.description)) ? "" :
        "<section class='panel'><div class='panel__head'><h2 class='panel__title'>About this project</h2></div><p class='prose'>$(esc(project.description))</p></section>"

    # Task list section
    task_section = if isempty(tasks)
        empty_state(
            "Tasks",
            "No tasks in this project yet",
            "Break the work down: add the first task and assign it to someone on the team.",
            "<div class='empty__actions'>" * btn("/tasks/new?project_id=$(project.id)", "Add first task", icon_name = "plus") * "</div>",
        )
    else
        rows = String[]
        for t in tasks
            assignee_name = t.assignee_id === nothing ? "<span class='muted-inline'>Unassigned</span>" : esc(get(mmap, t.assignee_id, TeamMember(id = nothing, name = "—", email = "", role = nothing)).name)
            due = t.due_at === nothing ? "<span class='due due--none'>—</span>" : due_chip(t.due_at, t.status == "done")
            push!(rows, """
            <tr>
              <td data-label="Task"><a class="row-title" href="/tasks/$(t.id)">$(esc(t.title))</a></td>
              <td data-label="Assignee">$(assignee_name)</td>
              <td data-label="Status">$(status_pill(t.status))</td>
              <td data-label="Due">$(due)</td>
            </tr>""")
        end
        """
        <div class="panel">
          <div class="panel__head">
            <div><h2 class="panel__title">Tasks</h2><p class="panel__sub">$(length(tasks)) task$(length(tasks) == 1 ? "" : "s") in this project</p></div>
            $(btn("/tasks/new?project_id=$(project.id)", "New task", icon_name = "plus"))
          </div>
          <div class="table-scroll">
            <table class="table">
              <thead><tr><th>Task</th><th>Assignee</th><th>Status</th><th>Due</th></tr></thead>
              <tbody>$(join(rows, ""))</tbody>
            </table>
          </div>
        </div>"""
    end

    # Delete form only when the project has no tasks.
    danger = if !isempty(tasks)
        "<div class='panel panel--danger'>
            <div class='panel__head'><div><h2 class='panel__title'>Delete project</h2><p class='panel__sub'>Not available — this project still has $(length(tasks)) task$(length(tasks) == 1 ? "" : "s").</p></div></div>
            <p class='prose'>Projects with tasks can't be deleted. <a href='/tasks?project_id=$(project.id)'>Review its tasks</a> first, then delete them individually before removing the project.</p>
         </div>"
    else
        """
        <div class="panel panel--danger">
          <div class="panel__head"><div><h2 class="panel__title">Delete project</h2><p class="panel__sub">This project has no tasks, so it can be removed.</p></div></div>
          <form method="post" action="/projects/$(project.id)/delete" class="form form--danger" data-submit-guard novalidate>
            $(csrf_input())
            $(confirm_checkbox("confirm", "Yes, permanently delete “$(esc(project.name))”. This cannot be undone."))
            $(btn_submit("Delete project", kind = "destructive", icon_name = "trash", data_state = "Deleting…"))
          </form>
        </div>"""
    end

    """
    <div class="detail-stack">
      <section class="panel">
        <div class="panel__head">
          <div><h2 class="panel__title">$(esc(project.name))</h2><p class="panel__sub">Project details</p></div>
          <div class="row-actions">
            $(btn("/projects/$(project.id)/edit", "Edit", kind = "ghost", icon_name = "edit"))
            $(btn("/tasks/new?project_id=$(project.id)", "New task", icon_name = "plus"))
          </div>
        </div>
        $(meta)
      </section>
      $(description)
      $(task_section)
      $(danger)
    </div>"""
end
