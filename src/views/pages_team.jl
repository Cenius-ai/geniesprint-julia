# ---------------------------------------------------------------------------
# Team roster pages
# ---------------------------------------------------------------------------

function page_team_index(members::Vector{TeamMember}, counts::Dict{Int,Int})::String
    if isempty(members)
        return empty_state(
            "Team",
            "No team members yet",
            "Add the people who do the work so tasks can be assigned to a real face.",
            "<div class='empty__actions'>" * btn("/team/new", "Add team member", icon_name = "plus") * "</div>",
        )
    end

    rows = String[]
    for m in members
        n = get(counts, m.id, 0)
        role = isempty(m.role === nothing ? "" : m.role) ? "<span class='muted-inline'>No role</span>" : esc(m.role)
        count_html = n == 0 ? "<span class='count-pill count-pill--zero'>0 tasks</span>" : "<span class='count-pill'>$(n) task$(n == 1 ? "" : "s")</span>"
        push!(rows, """
        <tr>
          <td data-label="Member">
            <div class="person">
              <span class="avatar" aria-hidden="true">$(esc(uppercase(first(m.name))))</span>
              <div class="person__meta">
                <a class="row-title" href="/team/$(m.id)">$(esc(m.name))</a>
                <span class="row-meta">$(esc(m.email))</span>
              </div>
            </div>
          </td>
          <td data-label="Role">$(role)</td>
          <td data-label="Assigned tasks">$(count_html)</td>
          <td class="row-actions">
            <a class="btn btn--ghost btn--sm" href="/team/$(m.id)">View</a>
            <a class="btn btn--ghost btn--sm" href="/team/$(m.id)/edit">$(icon("edit", size = 14))<span>Edit</span></a>
          </td>
        </tr>""")
    end

    """
    <div class="panel">
      <div class="panel__head">
        <div><h2 class="panel__title">Team roster</h2><p class="panel__sub">$(length(members)) member$(length(members) == 1 ? "" : "s") · sorted by name</p></div>
        $(btn("/team/new", "Add member", icon_name = "plus"))
      </div>
      <div class="table-scroll">
        <table class="table">
          <thead><tr><th>Member</th><th>Role</th><th>Assigned</th><th class="th-actions"><span class="visually-hidden">Actions</span></th></tr></thead>
          <tbody>$(join(rows, ""))</tbody>
        </table>
      </div>
    </div>"""
end

function page_team_form(; mode::Symbol, member::Union{TeamMember,Nothing}, errors::Dict{String,String}, values::Dict{String,String})
    is_edit = mode == :edit
    action = is_edit ? "/team/$(member.id)/update" : "/team"

    name_val = get(values, "name", is_edit ? member.name : "")
    email_val = get(values, "email", is_edit ? member.email : "")
    role_val = get(values, "role", is_edit ? something(member.role, "") : "")

    """
    <div class="panel panel--form">
      <div class="panel__head">
        <div><h2 class="panel__title">$(is_edit ? "Edit team member" : "Add team member")</h2>
        <p class="panel__sub">$(is_edit ? "Update their details below." : "Roster the people who can be assigned to tasks.")</p></div>
      </div>
      $(error_summary(errors))
      <form method="post" action="$(action)" class="form" data-submit-guard novalidate>
        $(csrf_input())
        $(text_field("name", "Full name", name_val; errors = errors, placeholder = "e.g. Amara Okafor", required = true, maxlength = "120", autocomplete = "name"))
        $(text_field("email", "Email address", email_val; errors = errors, placeholder = "amara@company.com", required = true, type = "email", autocomplete = "email", maxlength = "190"))
        $(text_field("role", "Role", isempty(role_val) ? nothing : role_val; errors = errors, placeholder = "e.g. Product designer", maxlength = "120", autocomplete = "off"))
        $(REQUIRED_HINT)
        <div class="form__actions">
          $(btn_submit(is_edit ? "Save changes" : "Add team member", icon_name = "check"))
          <a class="btn btn--ghost" href="$(is_edit ? "/team/$(member.id)" : "/team")">Cancel</a>
        </div>
      </form>
    </div>"""
end

function page_team_show(member::TeamMember, tasks::Vector{Task}, pmap::Dict{Int,Project})::String
    count = length(tasks)
    role_html = isempty(member.role === nothing ? "" : member.role) ? "<span class='muted-inline'>No role set</span>" : esc(member.role)

    meta = """
    <div class="profile">
      <span class="avatar avatar--lg" aria-hidden="true">$(esc(uppercase(first(member.name))))</span>
      <div class="profile__info">
        <h2 class="panel__title">$(esc(member.name))</h2>
        <p class="panel__sub">$(role_html)</p>
        <p class="profile__email">$(esc(member.email))</p>
      </div>
      <div class="profile__stat"><strong>$(count)</strong><span>assigned task$(count == 1 ? "" : "s")</span></div>
    </div>"""

    task_section = if isempty(tasks)
        empty_state(
            "Assigned tasks",
            "No tasks assigned yet",
            "Assign tasks from the task screens — until then this member can be removed from the roster.",
            "<div class='empty__actions'>" * btn("/tasks/new", "Assign a task", icon_name = "plus") * "</div>",
        )
    else
        rows = String[]
        for t in tasks
            pname = project_name(t.project_id, pmap)
            due = t.due_at === nothing ? "<span class='due due--none'>—</span>" : due_chip(t.due_at, t.status == "done")
            push!(rows, """
            <tr>
              <td data-label="Task"><a class="row-title" href="/tasks/$(t.id)">$(esc(t.title))</a></td>
              <td data-label="Project"><a class="table-link" href="/projects/$(t.project_id)">$(esc(pname))</a></td>
              <td data-label="Status">$(status_pill(t.status))</td>
              <td data-label="Due">$(due)</td>
            </tr>""")
        end
        """
        <div class="panel">
          <div class="panel__head"><div><h2 class="panel__title">Assigned tasks</h2><p class="panel__sub">$(count) task$(count == 1 ? "" : "s")</p></div></div>
          <div class="table-scroll">
            <table class="table">
              <thead><tr><th>Task</th><th>Project</th><th>Status</th><th>Due</th></tr></thead>
              <tbody>$(join(rows, ""))</tbody>
            </table>
          </div>
        </div>"""
    end

    danger = if count > 0
        "<div class='panel panel--danger'>
            <div class='panel__head'><div><h2 class='panel__title'>Remove from team</h2><p class='panel__sub'>Not available while tasks are assigned.</p></div></div>
            <p class='prose'>$(esc(member.name)) still has $(count) assigned task$(count == 1 ? "" : "s"). Reassign or delete those tasks first — team members with work can't simply disappear from the board.</p>
         </div>"
    else
        """
        <div class="panel panel--danger">
          <div class="panel__head"><div><h2 class='panel__title'>Remove from team</h2><p class='panel__sub'>No tasks are assigned, so this member can be removed.</p></div></div>
          <form method="post" action="/team/$(member.id)/delete" class="form form--danger" data-submit-guard novalidate>
            $(csrf_input())
            $(confirm_checkbox("confirm", "Yes, remove $(esc(member.name)) from the team. This cannot be undone."))
            $(btn_submit("Remove member", kind = "destructive", icon_name = "trash", data_state = "Removing…"))
          </form>
        </div>"""
    end

    """
    <div class="detail-stack">
      <section class="panel">
        <div class="panel__head">
          <div><p class="eyebrow">Team member</p></div>
          <div class="row-actions">$(btn("/team/$(member.id)/edit", "Edit", kind = "ghost", icon_name = "edit"))</div>
        </div>
        $(meta)
      </section>
      $(task_section)
      $(danger)
    </div>"""
end
