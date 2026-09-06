# ---------------------------------------------------------------------------
# Layout shells: authenticated app shell, auth (login) shell, standalone shell.
# ---------------------------------------------------------------------------

function _head(title::AbstractString, body_class::String)
    """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#0c0c11">
<title>$(esc(title)) · GenieTeam</title>
<meta name="description" content="GenieTeam — a small team workspace for projects, tasks and the people doing them.">
<link rel="icon" href="/img/favicon.svg" type="image/svg+xml">
<link rel="preload" href="/fonts/hanken-grotesk-latin.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/css/app.css">
</head>
<body class="$(esc(body_class))">"""
end

"""Brand mark (duotone accent -> ink) + wordmark."""
function brand(compact::Bool = false)
    sub = compact ? "" : "<span class='brand__workspace'>Demo workspace</span>"
"""<a class="brand" href="/dashboard" aria-label="GenieTeam dashboard">
        <span class='brand__tile' aria-hidden='true'><svg width='18' height='18' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2.1' stroke-linecap='round' stroke-linejoin='round'><path d='M12 3l1.9 5.8a2 2 0 0 0 1.3 1.3L21 12l-5.8 1.9a2 2 0 0 0-1.3 1.3L12 21l-1.9-5.8a2 2 0 0 0-1.3-1.3L3 12l5.8-1.9a2 2 0 0 0 1.3-1.3L12 3z'/></svg></span>
        <span class='brand__name'>Genie<span class='brand__accent'>Team</span>$(sub)</span>
    </a>"""
end

const NAV_ITEMS = [
    ("dashboard", "/dashboard", "Dashboard", "dashboard"),
    ("projects", "/projects", "Projects", "folder"),
    ("tasks", "/tasks", "Tasks", "tasks"),
    ("team", "/team", "Team", "users"),
]

function nav_html(section::AbstractString)
    path = current_path()
    parts = String[]
    for (key, href, label, ic) in NAV_ITEMS
        active = if key == "dashboard"
            path == "/dashboard" || path == "/"
        else
            startswith(path, href)
        end
        cls = active ? "class='nav-link nav-link--active' aria-current='page'" : "class='nav-link'"
        push!(parts, "<a href='$(href)' $(cls)>$(icon(ic, size = 17))<span>$(label)</span></a>")
    end
    join(parts, "")
end

"""
    layout_app(; section, title, subtitle, actions, content) -> String

The authenticated application shell: sidebar navigation with active-link
highlight, the signed-in user's email and logout control, plus the content
area. Everything is served same-origin; no remote requests.
"""
function layout_app(; section::String, title::AbstractString, subtitle::String = "", actions::String = "", content::String = "")
    user = view_user()
    email = user === nothing ? "" : user.email
    top_title = isempty(subtitle) ? "" : "<p class='page-sub'>$(esc(subtitle))</p>"
    actions_html = isempty(actions) ? "" : "<div class='page-actions'>$(actions)</div>"
    flash = flash_html()

    logout_form = "<form method='post' action='/logout' class='logout-form'>$(csrf_input())<button type='submit' class='logout-btn' title='Sign out'>$(icon("logout", size = 16))<span>Sign out</span></button></form>"

    body = _head(title, "app-body") * """
<div class="app">
  <a class="skip-link" href="#main">Skip to content</a>
  <aside class="sidebar" id="sidebar" aria-label="Primary">
    <div class="sidebar__inner">
      $(brand(false))
      <nav class="nav">$(nav_html(section))</nav>
    </div>
    <div class="sidebar__user">
      <div class="avatar" aria-hidden="true">$(esc(uppercase(first(email))))</div>
      <div class="sidebar__user-meta">
        <span class="sidebar__user-email">$(esc(email))</span>
        <span class="sidebar__user-role">Workspace admin</span>
      </div>
      $(logout_form)
    </div>
  </aside>
  <div class="main" id="main">
    <header class="topbar">
      <button type="button" class="icon-btn topbar__menu" data-nav-toggle aria-label="Toggle navigation" aria-expanded="false">$(icon("menu", size = 20))</button>
      <div class="topbar__title">
        <h1>$(esc(title))</h1>
        $(top_title)
      </div>
      $(actions_html)
    </header>
    <div class="content">
      $(flash)
      $(content)
    </div>
  </div>
</div>
<script src="/js/app.js" defer></script>
</body>
</html>"""
    body
end

"""Shell used by the login screen (no app chrome, same design system)."""
function layout_auth(; title::String = "Sign in", content::String = "")
    flash = flash_html()
    body = _head(title, "auth-body") * """
<div class="auth">
  <div class="auth__glow" aria-hidden="true"></div>
  <div class="auth__panel">
    <header class="auth__header">$(brand(true))<p class="auth__tagline">One calm place for your team's projects and tasks.</p></header>
    $(flash)
    $(content)
  </div>
</div>
<script src="/js/app.js" defer></script>
</body>
</html>"""
    body
end

"""Standalone shell for styled 404 / 500 pages (works logged-in or not)."""
function layout_standalone(; status::Int, title::String, message::String, action_html::String = "")
    user = current_user()
    authed = user !== nothing
    back = authed ? "/dashboard" : "/login"
    back_label = authed ? "Back to dashboard" : "Back to sign in"
    body = _head(title, "standalone-body") * """
<div class="standalone">
  <div class="standalone__card">
    <div class="standalone__code">$(status)</div>
    <div class="standalone__mark">$(icon(status == 404 ? "flag" : "alert", size = 26))</div>
    <h1>$(esc(title))</h1>
    <p class="standalone__message">$(esc(message))</p>
    <div class="standalone__actions">
      <a class='btn btn--primary' href='$(esc(back))'>$(icon("arrow-right", size = 16))<span>$(esc(back_label))</span></a>
    </div>
  </div>
</div>
<script src="/js/app.js" defer></script>
</body>
</html>"""
    body
end
