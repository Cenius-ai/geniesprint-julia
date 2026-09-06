# ---------------------------------------------------------------------------
# HTML helpers & shared UI fragments.
#
# These views are assembled as plain Julia strings. There is NO template
# auto-escaping in that pipeline, so every user-derived value is passed
# through `esc()` at interpolation time — both in element text and attributes.
# Internal literals (button labels, icons, navigation) are static.
# ---------------------------------------------------------------------------

"""Escape text for safe interpolation into HTML text/attributes."""
function esc(v)
    v === nothing && return ""
    s = string(v)
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s = replace(s, "\"" => "&quot;")
    s = replace(s, "'" => "&#39;")
    s
end

"""Safe attribute value (quotes are escaped so values can sit inside "...")."""
attr(v) = esc(v)

"""Serializes an attribute dictionary into an HTML attribute string."""
function attrs_html(pairs::Vector{Pair{String,String}})::String
    isempty(pairs) && return ""
    " " * join(["$(k)=\"$(attr(v))\"" for (k, v) in pairs], " ")
end

"""Human readable date from a stored SQL datetime (`yyyy-mm-dd HH:MM:SS`)."""
function pretty_dt(v)::String
    v === nothing && return "—"
    v === missing && return "—"
    s = String(v)
    d = tryparse(Date, first(split(s, " ")), dateformat"yyyy-mm-dd")
    d === nothing ? esc(s) : Dates.format(d, "d uuuu")
end

"""Pretty date for `d::Date`."""
pretty_date(d::Date) = Dates.format(d, "d uuuu")

# ---------------------------------------------------------------------------
# Icons (inline SVG, single family, currentColor)
# ---------------------------------------------------------------------------

const ICON_PATHS = Dict(
    "dashboard" => raw"<rect x='3' y='3' width='7' height='9' rx='1.5'/><rect x='14' y='3' width='7' height='5' rx='1.5'/><rect x='14' y='12' width='7' height='9' rx='1.5'/><rect x='3' y='16' width='7' height='5' rx='1.5'/>",
    "folder" => raw"<path d='M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z'/>",
    "users" => raw"<path d='M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2'/><circle cx='9' cy='7' r='4'/><path d='M22 21v-2a4 4 0 0 0-3-3.87'/><path d='M16 3.13a4 4 0 0 1 0 7.75'/>",
    "tasks" => raw"<path d='M9 11l3 3L22 4'/><path d='M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11'/>",
    "plus" => raw"<path d='M12 5v14'/><path d='M5 12h14'/>",
    "logout" => raw"<path d='M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4'/><path d='M16 17l5-5-5-5'/><path d='M21 12H9'/>",
    "menu" => raw"<path d='M3 12h18'/><path d='M3 6h18'/><path d='M3 18h18'/>",
    "eye" => raw"<path d='M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z'/><circle cx='12' cy='12' r='3'/>",
    "eye-off" => raw"<path d='M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94'/><path d='M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19'/><path d='M14.12 14.12a3 3 0 1 1-4.24-4.24'/><path d='M1 1l22 22'/>",
    "calendar" => raw"<rect x='3' y='4' width='18' height='18' rx='2'/><path d='M16 2v4'/><path d='M8 2v4'/><path d='M3 10h18'/>",
    "edit" => raw"<path d='M17 3a2.83 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z'/>",
    "trash" => raw"<path d='M3 6h18'/><path d='M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6'/><path d='M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2'/>",
    "alert" => raw"<path d='M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z'/><path d='M12 9v4'/><path d='M12 17h.01'/>",
    "arrow-right" => raw"<path d='M5 12h14'/><path d='M12 5l7 7-7 7'/>",
    "check" => raw"<path d='M20 6L9 17l-5-5'/>",
    "clock" => raw"<circle cx='12' cy='12' r='10'/><path d='M12 6v6l4 2'/>",
    "spark" => raw"<path d='M12 3l1.9 5.8a2 2 0 0 0 1.3 1.3L21 12l-5.8 1.9a2 2 0 0 0-1.3 1.3L12 21l-1.9-5.8a2 2 0 0 0-1.3-1.3L3 12l5.8-1.9a2 2 0 0 0 1.3-1.3L12 3z'/>",
    "flag" => raw"<path d='M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z'/><path d='M4 22v-7'/>",
    "link" => raw"<path d='M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71'/><path d='M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71'/>",
    "lock" => raw"<rect x='3' y='11' width='18' height='11' rx='2'/><path d='M7 11V7a5 5 0 0 1 10 0v4'/>",
)

"""Inline SVG for `name` with the default stroke style."""
function icon(name::AbstractString; size::Int = 18)
    path = get(ICON_PATHS, name, ICON_PATHS["spark"])
    "<svg class='ic' width='$(size)' height='$(size)' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'>$(path)</svg>"
end

# ---------------------------------------------------------------------------
# Shared state helpers (request-aware)
# ---------------------------------------------------------------------------

"""Hidden CSRF input for forms. Registers the session (and its cookie)."""
csrf_input() = "<input type='hidden' name='_csrf' value='$(esc(csrf_token()))'>"

"""Current request path (used for active navigation)."""
function current_path()::String
    req = Genie.Requests.request()
    req === nothing && return "/"
    target = req.target
    isempty(target) && return "/"
    path = split(target, "?")[1]
    isempty(path) ? "/" : path
end

"""Flash banner HTML for the current request (reads + clears the flash)."""
function flash_html()::String
    f = take_flash()
    f === nothing && return ""
    kind, msg = f
    class = kind == "error" ? "flash flash--error" : (kind == "success" ? "flash flash--success" : "flash flash--notice")
    ic = kind == "error" ? icon("alert") : icon("check")
    "<div class='$(class)' role='status' data-flash>$(ic)<span>$(esc(msg))</span><button type='button' class='flash__close' data-flash-close aria-label='Dismiss'>×</button></div>"
end

# ---------------------------------------------------------------------------
# Small UI atoms
# ---------------------------------------------------------------------------

"""Anchor styled as a button."""
function btn(href::AbstractString, label::AbstractString; kind::AbstractString = "primary", icon_name::Union{String,Nothing} = nothing, extra::String = "", css::String = "")
    ic = icon_name === nothing ? "" : icon(icon_name)
    "<a class='btn btn--$(esc(kind)) $(css)' href='$(esc(href))' $(extra)><span>$(esc(label))</span>$(ic == "" ? "" : ic)</a>"
end

"""Submit button."""
function btn_submit(label::AbstractString; kind::AbstractString = "primary", icon_name::Union{String,Nothing} = nothing, name::Union{String,Nothing} = nothing, value::Union{String,Nothing} = nothing, data_state::String = "")
    ic = icon_name === nothing ? "" : icon(icon_name)
    n = name === nothing ? "" : " name='$(esc(name))'"
    v = value === nothing ? "" : " value='$(esc(value))'"
    ds = isempty(data_state) ? "" : " data-loading-label='$(esc(data_state))'"
    "<button type='submit' class='btn btn--$(esc(kind))' $(n)$(v)$(ds)><span>$(esc(label))</span>$(ic == "" ? "" : ic)</button>"
end

"""Inline status pill for a task status."""
function status_pill(status::AbstractString)::String
    st = valid_status(status) ? status : "todo"
    "<span class='pill pill--$(esc(st))'><span class='pill__dot'></span>$(esc(status_label(st)))</span>"
end

"""Due-date chip: colours by urgency. `done` suppresses urgency styling."""
function due_chip(iso_due, is_done::Bool = false)::String
    due = parse_stored_date(iso_due)
    due === nothing && return "<span class='due due--none'>No due date</span>"
    delta = Dates.value(due - today_local())
    text = if delta == 0
        "Due today"
    elseif delta == 1
        "Due tomorrow"
    elseif delta < 0
        "Due " * string(-delta) * (delta == -1 ? " day ago" : " days ago")
    else
        "Due in " * string(delta) * " days"
    end
    class = if is_done
        "due due--done"
    elseif delta < 0
        "due due--overdue"
    elseif delta <= 2
        "due due--soon"
    else
        "due"
    end
    ic = icon((delta < 0 && !is_done) ? "alert" : "calendar", size = 14)
    "<span class='$(class)'>$(ic)$(esc(text))</span>"
end

"""Human date (e.g. 12 Jun 2025) for headers/details, nothing-safe."""
function pretty_date(iso_due)::String
    d = parse_stored_date(iso_due)
    d === nothing ? "—" : Dates.format(d, "d uuuu")
end

"""Empty-state block used on lists and detail pages."""
function empty_state(eyebrow::AbstractString, title::AbstractString, body::AbstractString, action_html::String = "")
    "<div class='empty'><div class='empty__mark'>$(icon("spark", size = 22))</div><p class='empty__eyebrow'>$(esc(eyebrow))</p><h3>$(esc(title))</h3><p class='empty__body'>$(esc(body))</p>$(action_html)</div>"
end

"""Renders server-side validation errors for a field (or an empty string)."""
function field_error(errors::Dict{String,String}, field::AbstractString)::String
    haskey(errors, field) || return ""
    "<p class='field-error' id='error-$(esc(field))' role='alert'>$(esc(errors[field]))</p>"
end

"""Validation summary box shown at the top of a form."""
function error_summary(errors::Dict{String,String})::String
    isempty(errors) && return ""
    msgs = String[]
    for (_, msg) in errors
        push!(msgs, msg)
    end
    body = join(["<li>$(esc(m))</li>" for m in msgs], "")
    "<div class='alert alert--error' role='alert'>$(icon("alert"))<div><strong>Please fix the following:</strong><ul>$(body)</ul></div></div>"
end

# ---------------------------------------------------------------------------
# Form field builders (all server-rendered, values preserved on re-render)
# ---------------------------------------------------------------------------

function _label(for_id::AbstractString, label::AbstractString, required::Bool)
    star = required ? "<span class='req' aria-hidden='true'>*</span>" : ""
    "<label class='label' for='$(esc(for_id))'>$(esc(label))$(star)</label>"
end

function _input_wrap(name::AbstractString, errors::Dict{String,String}, inner::String)
    errclass = haskey(errors, name) ? " input-wrap--invalid" : ""
    "<div class='input-wrap$(errclass)'>$(inner)$(field_error(errors, name))</div>"
end

function text_field(name::AbstractString, label::AbstractString, value::Union{AbstractString,Nothing}; errors::Dict{String,String} = Dict{String,String}(), placeholder::String = "", required::Bool = false, type::String = "text", id::Union{String,Nothing} = nothing, autocomplete::String = "off", min::Union{String,Nothing} = nothing, max::Union{String,Nothing} = nothing, maxlength::Union{String,Nothing} = nothing)
    fid = id === nothing ? name : id
    req = required ? " required" : ""
    extra = isempty(placeholder) ? "" : " placeholder='$(attr(placeholder))'"
    auto = isempty(autocomplete) ? "" : " autocomplete='$(attr(autocomplete))'"
    min_attr = min === nothing ? "" : " min='$(attr(min))'"
    max_attr = max === nothing ? "" : " max='$(attr(max))'"
    ml_attr = maxlength === nothing ? "" : " maxlength='$(attr(maxlength))'"
    val = value === nothing ? "" : value
    inner = "$(_label(fid, label, required))<input id='$(esc(fid))' type='$(esc(type))' name='$(esc(name))' value='$(attr(val))'$(req)$(extra)$(auto)$(min_attr)$(max_attr)$(ml_attr) class='input'>"
    _input_wrap(name, errors, inner)
end

function password_field(name::AbstractString, label::AbstractString, errors::Dict{String,String} = Dict{String,String}(); placeholder::String = "", autocomplete::String = "current-password")
    ph = isempty(placeholder) ? "" : " placeholder='$(attr(placeholder))'"
    inner = "$(_label(name, label, true))
        <div class='input-affix'>
            <input id='$(esc(name))' type='password' name='$(esc(name))' class='input input--affixed' required $(ph) autocomplete='$(attr(autocomplete))'>
            <button type='button' class='input-affix__btn' data-password-toggle aria-label='Show password' aria-pressed='false'>
    <span class='pw-ic pw-ic--show'>$(icon("eye"))</span><span class='pw-ic pw-ic--hide' hidden>$(icon("eye-off"))</span>
</button>
        </div>"
    _input_wrap(name, errors, inner)
end

function textarea_field(name::AbstractString, label::AbstractString, value::Union{AbstractString,Nothing}; errors::Dict{String,String} = Dict{String,String}(), rows::Int = 4, placeholder::String = "", required::Bool = false, id::Union{String,Nothing} = nothing)
    fid = id === nothing ? name : id
    req = required ? " required" : ""
    ph = isempty(placeholder) ? "" : " placeholder='$(attr(placeholder))'"
    val = value === nothing ? "" : value
    inner = "$(_label(fid, label, required))<textarea id='$(esc(fid))' name='$(esc(name))' rows='$(rows)'$(req)$(ph) class='input input--textarea'>$(esc(val))</textarea>"
    _input_wrap(name, errors, inner)
end

"""
    select_field(name, label, options, selected; errors, required, placeholder)

`options` is a Vector{Pair{String,String}} of (value, label). An optional
leading placeholder option appears first.
"""
function select_field(name::AbstractString, label::AbstractString, options::Vector{Pair{String,String}}, selected::Union{AbstractString,Nothing}; errors::Dict{String,String} = Dict{String,String}(), required::Bool = false, placeholder::String = "", id::Union{String,Nothing} = nothing)
    fid = id === nothing ? name : id
    req = required ? " required" : ""
    opts = String[]
    if !isempty(placeholder)
        sel = (selected === nothing || isempty(selected)) ? " selected" : ""
        push!(opts, "<option value=''$(sel) disabled>$(esc(placeholder))</option>")
    end
    for (value, label) in options
        sel = (selected !== nothing && string(value) == string(selected)) ? " selected" : ""
        push!(opts, "<option value='$(attr(value))'$(sel)>$(esc(label))</option>")
    end
    inner = "$(_label(fid, label, required))<select id='$(esc(fid))' name='$(esc(name))' class='input input--select'$(req)>$(join(opts, ""))</select>"
    _input_wrap(name, errors, inner)
end

function date_field(name::AbstractString, label::AbstractString, value::Union{AbstractString,Nothing}; errors::Dict{String,String} = Dict{String,String}(), required::Bool = false, id::Union{String,Nothing} = nothing)
    fid = id === nothing ? name : id
    req = required ? " required" : ""
    val = value === nothing ? "" : value
    inner = "$(_label(fid, label, required))<input id='$(esc(fid))' type='date' name='$(esc(name))' value='$(attr(val))'$(req) class='input'>"
    _input_wrap(name, errors, inner)
end

"""Checkbox used for the explicit delete confirmation gate."""
function confirm_checkbox(name::AbstractString, label::AbstractString, checked::Bool = false)
    chk = checked ? " checked" : ""
    "<label class='confirm'><input type='checkbox' name='$(esc(name))' value='yes' required$(chk)><span>$(esc(label))</span></label>"
end

"""Inline text for required-legend."""
const REQUIRED_HINT = "<p class='form-hint'>Fields marked <span class='req'>*</span> are required.</p>"

"""Top-of-form block: validation summary only (flash renders in the layout)."""
form_top(errors::Dict{String,String}) = error_summary(errors)

"""Logged-in user for the current request (layout shell convenience)."""
view_user() = current_user()
