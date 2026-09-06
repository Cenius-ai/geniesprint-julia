# ---------------------------------------------------------------------------
# Dashboard page: KPI strip + a single asymmetric bento of workspace panels.
# ---------------------------------------------------------------------------

function _kpi_cell(label, value, meta, icon_name, accent::Bool = false)
    extra = accent ? " kpi--accent" : ""
    """<div class="kpi$extra">
        <span class="kpi__icon">$(icon(icon_name))</span>
        <span class="kpi__label">$(esc(label))</span>
        <span class="kpi__value">$(esc(value))</span>
        <span class="kpi__meta">$(esc(meta))</span>
    </div>"""
end

"""Task-status snapshot rendered with proportional ticks (CSP-safe, no inline styles)."""
function _status_snapshot(status_counts::Dict{String,Int})::String
    total = sum(values(status_counts))
    items = String[]
    for s in TASK_STATUSES
        n = get(status_counts, s, 0)
        pct = total == 0 ? 0 : round(Int, 100 * n / total)
        ticks = n == 0 ? "<span class='muted-inline'>none yet</span>" :
            join(["<i class='tick tick--$(s)'></i>" for _ in 1:min(n, 24)], "")
        push!(items, """
        <div class="snap-row">
          <span class="snap-row__label">$(status_pill(s))</span>
          <span class="snap-row__count"><strong>$(n)</strong><span class="muted-inline"> · $(pct)%</span></span>
          <span class="snap-row__ticks" aria-hidden="true">$(ticks)</span>
        </div>""")
    end
    """<div class="snap">$(join(items, ""))</div>"""
end

function _task_list_cell(title::String, subtitle::String, tasks::Vector{Task}, pmap::Dict{Int,Project}, mmap::Dict{Int,TeamMember}, empty_title::String, empty_body::String)::String
    body = if isempty(tasks)
        empty_state("Tasks", empty_title, empty_body, "")
    else
        rows = String[]
        for t in tasks
            due = t.due_at === nothing ? "<span class='due due--none'>—</span>" : due_chip(t.due_at, t.status == "done")
            assignee = t.assignee_id === nothing ? "Unassigned" : assignee_name(t.assignee_id, mmap)
            push!(rows, """
            <li class="task-line">
              <div class="task-line__main">
                <a class="row-title" href="/tasks/$(t.id)">$(esc(t.title))</a>
                <span class="row-meta">$(esc(project_name(t.project_id, pmap))) · $(esc(assignee))</span>
              </div>
              <div class="task-line__side">$(due)</div>
            </li>""")
        end
        "<ul class='task-lines'>$(join(rows, ""))</ul>"
    end
    """
    <div class="bento-cell">
      <div class="bento-cell__head"><div><h3 class="bento-cell__title">$(esc(title))</h3><p class="bento-cell__sub">$(esc(subtitle))</p></div></div>
      $(body)
    </div>"""
end

function _project_lines(projects::Vector{Project}, task_counts::Dict{Int,Int})::String
    rows = String[]
    for p in projects
        n = get(task_counts, p.id, 0)
        push!(rows, """
        <li class="project-line">
          <div class="project-line__main">
            <a class="row-title" href="/projects/$(p.id)">$(esc(p.name))</a>
            <span class="row-meta">$(n) task$(n == 1 ? "" : "s") · created $(esc(pretty_dt(p.created_at)))</span>
          </div>
          <div class="project-line__side">$(p.due_at === nothing ? "<span class='due due--none'>No due date</span>" : due_chip(p.due_at))</div>
        </li>""")
    end
    "<ul class='project-lines'>$(join(rows, ""))</ul>"
end

"""
    page_dashboard(; projects, project_task_counts, status_counts, overdue, upcoming, pmap, mmap, members_count) -> String
"""
function page_dashboard(; projects::Vector{Project}, project_task_counts::Dict{Int,Int}, status_counts::Dict{String,Int}, overdue::Vector{Task}, upcoming::Vector{Task}, pmap::Dict{Int,Project}, mmap::Dict{Int,TeamMember}, members_count::Int)::String
    open_tasks = get(status_counts, "todo", 0) + get(status_counts, "in_progress", 0)
    done_tasks = get(status_counts, "done", 0)
    total_tasks = sum(values(status_counts))
    done_pct = total_tasks == 0 ? 0 : round(Int, 100 * done_tasks / total_tasks)

    if isempty(projects)
        return empty_state(
            "Empty workspace",
            "Create your first project",
            "Everything in GenieTeam hangs off a project. Once one exists you can add tasks, assign teammates and watch the dashboard come alive.",
            "<div class='empty__actions'>" * btn("/projects/new", "New project", icon_name = "plus") * "</div>",
        )
    end

    kpi = join([
        _kpi_cell("Projects", string(length(projects)), "in the workspace", "folder"),
        _kpi_cell("Open tasks", string(open_tasks), string(get(status_counts, "in_progress", 0), " in progress"), "clock"),
        _kpi_cell("Completed", string(done_tasks), total_tasks == 0 ? "no tasks yet" : string(done_pct, "% of all tasks"), "check", true),
        _kpi_cell("Team members", string(members_count), "on the roster", "users"),
    ], "")

    projects_cell = """
    <div class="bento-cell bento-cell--wide">
      <div class="bento-cell__head">
        <div><h3 class="bento-cell__title">Projects</h3><p class="bento-cell__sub">$(length(projects)) active project$(length(projects) == 1 ? "" : "s") by due date</p></div>
        $(btn("/projects/new", "New project", kind = "ghost", icon_name = "plus", css = "btn--sm"))
      </div>
      $(_project_lines(projects, project_task_counts))
    </div>"""

    snapshot_cell = """
    <div class="bento-cell">
      <div class="bento-cell__head"><div><h3 class="bento-cell__title">Task status</h3><p class="bento-cell__sub">$(total_tasks) task$(total_tasks == 1 ? "" : "s") across all projects</p></div></div>
      $(_status_snapshot(status_counts))
    </div>"""

    overdue_cell = _task_list_cell(
        "Needs attention", string(length(overdue), " overdue task", length(overdue) == 1 ? "" : "s"),
        overdue, pmap, mmap,
        "Nothing overdue", "No open tasks are past their due date. Nice and calm.",
    )

    upcoming_cell = _task_list_cell(
        "Upcoming", "Open tasks due in the next 14 days",
        upcoming, pmap, mmap,
        "Nothing due soon", "Open tasks with due dates land here as they approach.",
    )

    """
    <div class="dashboard">
      <div class="kpi-strip">$(kpi)</div>
      <div class="bento">
        $(projects_cell)
        $(snapshot_cell)
        $(upcoming_cell)
        $(overdue_cell)
      </div>
    </div>"""
end
