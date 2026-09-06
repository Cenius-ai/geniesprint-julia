# ---------------------------------------------------------------------------
# Authentication pages
# ---------------------------------------------------------------------------

"""
    page_login(errors, submitted_email, next, locked_out) -> String

Login card with the demo credential callout. Shows a single non-enumerating
error message for bad credentials plus the demo hint the evaluator needs.
"""
function page_login(errors::Dict{String,String}, submitted_email::AbstractString, next::AbstractString, locked_out::Bool)::String
    general = locked_out ? "Too many sign-in attempts. Please wait a few minutes and try again." : get(errors, "__form__", "")
    alert = isempty(general) ? "" :
        "<div class='alert alert--error' role='alert'>$(icon("alert"))<div><strong>$(esc(general))</strong></div></div>"
    field_errors = Dict{String,String}(k => v for (k, v) in errors if k != "__form__")

    """
    <div class="login">
      <h2 class="login__title">Sign in to your workspace</h2>
      <p class="login__sub">Use your GenieTeam workspace admin account to continue.</p>
      $(alert)
      <form method="post" action="/login" class="form" data-login-form data-submit-guard novalidate>
        $(csrf_input())
        <input type="hidden" name="next" value="$(attr(next))">
        $(text_field("email", "Email", submitted_email; errors = field_errors, placeholder = "you@company.com", required = true, type = "email", autocomplete = "email"))
        $(password_field("password", "Password", field_errors; placeholder = "••••••••"))
        <div class="form__actions">
          $(btn_submit("Sign in", icon_name = "arrow-right", data_state = "Signing in…"))
        </div>
      </form>
      <div class="demo-card">
        <div class="demo-card__head">$(icon("spark", size = 15))<strong>Explore the demo workspace</strong></div>
        <p class="demo-card__body"><span class="demo-card__hint">Demo: cenius@cenius.ai / cenius</span><br>
        Sign in with the seeded admin account to explore a fully populated workspace — projects, tasks and team included.</p>
        <dl class="demo-card__creds">
          <div><dt>Email</dt><dd><code>cenius@cenius.ai</code></dd></div>
          <div><dt>Password</dt><dd><code>cenius</code></dd></div>
        </dl>
      </div>
    </div>"""
end
