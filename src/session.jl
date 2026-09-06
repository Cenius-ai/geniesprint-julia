# ---------------------------------------------------------------------------
# Sessions + CSRF + flash.
#
# Modern Genie no longer ships a server-side Sessions module, so this is the
# app's own lightweight session layer built directly on Genie's HTTP plumbing:
# an opaque random session id lives in an HttpOnly SameSite=Lax cookie, keyed
# server-side into an in-memory store. The id is HMAC-signed with the app
# secret so clients cannot forge ids. CSRF tokens are per-session, injected by
# the shared form helper and verified before every state-changing POST.
# ---------------------------------------------------------------------------

using Random
using Dates

const SESSION_COOKIE = "gt_sid"
const SESSION_TTL_SECONDS = 8 * 60 * 60          # 8 hours
const FLASH_COOKIE = nothing                     # flash travels in the session

mutable struct SessData
    user_id::Union{Int,Nothing}
    csrf::String
    flash_kind::Union{String,Nothing}
    flash_msg::Union{String,Nothing}
    expires::Float64
end

const SESSIONS = Dict{String,SessData}()
const SESSIONS_LOCK = ReentrantLock()

"""Random hex token of `nbytes` bytes."""
function random_hex(nbytes::Int = 16)::String
    bytes2hex(rand(UInt8, nbytes))
end

"""HMAC-SHA256 hex signature of `value` keyed with the app secret."""
function sign_value(value::AbstractString)::String
    key = Vector{UInt8}(codeunits(app_secret()))
    bytes2hex(hmac_sha256(key, value))
end

"""Signed cookie value: `id.signature`."""
function signed_session_value(sid::AbstractString)::String
    string(sid, ".", sign_value(sid))
end

"""Verifies + returns the session id from a signed cookie value, or nothing."""
function verify_signed_session(value::AbstractString)::Union{String,Nothing}
    parts = split(value, ".")
    length(parts) == 2 || return nothing
    sid, sig = parts[1], parts[2]
    PasswordHasher.secure_equals(sig, sign_value(sid)) || return nothing
    isempty(sid) && return nothing
    sid
end

"""Raw cookie value from the current request (encrypted = false)."""
function request_cookie(name::AbstractString)::Union{String,Nothing}
    req = Genie.Requests.request()
    req === nothing && return nothing
    Genie.Cookies.get(req, String(name); encrypted = false)
end

"""Purge expired sessions (called opportunistically)."""
function purge_expired_sessions!()
    now_t = time()
    lock(SESSIONS_LOCK) do
        for (sid, data) in SESSIONS
            data.expires < now_t && delete!(SESSIONS, sid)
        end
    end
    nothing
end

"""
    ensure_session!() -> String

Returns the current request's session id, creating a fresh anonymous session
(with a CSRF token) when the visitor has no valid cookie. The caller must make
sure the response carries the cookie (handled automatically by the session
response hook in web.jl via `session_cookie_to_attach()`).
"""
function ensure_session!()::String
    purge_expired_sessions!()

    cached = get(task_local_storage(), :gt_sid, nothing)
    cached !== nothing && return cached

    sid = nothing
    raw = request_cookie(SESSION_COOKIE)
    if raw !== nothing
        candidate = verify_signed_session(raw)
        if candidate !== nothing
            lock(SESSIONS_LOCK) do
                data = get(SESSIONS, candidate, nothing)
                if data !== nothing && data.expires > time()
                    sid = candidate
                    if isempty(data.csrf)
                        data.csrf = random_hex(16)
                    end
                end
            end
        end
    end

    if sid === nothing
        sid = random_hex(24)
        lock(SESSIONS_LOCK) do
            SESSIONS[sid] = SessData(nothing, random_hex(16), nothing, nothing, time() + SESSION_TTL_SECONDS)
        end
    end

    task_local_storage(:gt_sid, sid)
    sid
end

"""Session data for the current request, or nothing."""
function current_session()::Union{SessData,Nothing}
    sid = get(task_local_storage(), :gt_sid, nothing)
    if sid === nothing
        raw = request_cookie(SESSION_COOKIE)
        raw === nothing && return nothing
        sid = verify_signed_session(raw)
        sid === nothing && return nothing
        task_local_storage(:gt_sid, sid)
    end
    lock(SESSIONS_LOCK) do
        data = get(SESSIONS, sid, nothing)
        (data === nothing || data.expires <= time()) ? nothing : data
    end
end

"""Signed cookie value for the current session (nothing when anonymous/absent)."""
function session_cookie_to_attach()::Union{String,Nothing}
    sid = get(task_local_storage(), :gt_sid, nothing)
    sid === nothing && return nothing
    signed_session_value(sid)
end

"""CSRF token for the current session (creating the session when needed)."""
function csrf_token()::String
    ensure_session!()
    data = current_session()
    data === nothing && return ""
    data.csrf
end

"""The id of the user in the current session, or nothing."""
function session_user_id()::Union{Int,Nothing}
    data = current_session()
    data === nothing ? nothing : data.user_id
end

"""Logged-in user for the current request, or nothing."""
function current_user()::Union{User,Nothing}
    uid = session_user_id()
    uid === nothing && return nothing
    user_by_id(uid)
end

"""True when the visitor is authenticated."""
function is_authenticated()
    session_user_id() !== nothing
end

"""
    login_user!(user::User) -> Nothing

Rotates to a brand-new session id bound to `user` (defends against session
fixation), resets the CSRF token, and schedules the cookie for the response.
"""
function login_user!(user::User)
    ensure_session!()   # guaranteed to exist (login form carried a CSRF token)
    old_sid = get(task_local_storage(), :gt_sid, nothing)
    new_sid = random_hex(24)

    flash = take_flash()
    lock(SESSIONS_LOCK) do
        if old_sid !== nothing
            delete!(SESSIONS, old_sid)
        end
        SESSIONS[new_sid] = SessData(
            user.id,
            random_hex(16),
            flash === nothing ? nothing : flash[1],
            flash === nothing ? nothing : flash[2],
            time() + SESSION_TTL_SECONDS,
        )
    end
    task_local_storage(:gt_sid, new_sid)
    nothing
end

"""Clears the current session and schedules cookie deletion on the response."""
function logout_user!()
    sid = get(task_local_storage(), :gt_sid, nothing)
    if sid !== nothing
        lock(SESSIONS_LOCK) do
            delete!(SESSIONS, sid)
        end
    end
    task_local_storage(:gt_sid, nothing)
    task_local_storage(:gt_logout, true)
    nothing
end

"""True when the response must clear the session cookie."""
function session_logout_pending()::Bool
    get(task_local_storage(), :gt_logout, false) === true
end

# ---------------------------------------------------------------------------
# Flash messages
# ---------------------------------------------------------------------------

function set_flash(kind::AbstractString, msg::AbstractString)
    ensure_session!()
    sid = get(task_local_storage(), :gt_sid, nothing)
    sid === nothing && return
    lock(SESSIONS_LOCK) do
        data = get(SESSIONS, sid, nothing)
        data === nothing && return
        data.flash_kind = String(kind)
        data.flash_msg = String(msg)
    end
    nothing
end

flash_success(msg) = set_flash("success", msg)
flash_error(msg) = set_flash("error", msg)
flash_notice(msg) = set_flash("notice", msg)

"""Returns and clears the pending flash message: (kind, text) or nothing."""
function take_flash()::Union{Tuple{String,String},Nothing}
    sid = get(task_local_storage(), :gt_sid, nothing)
    sid === nothing && return nothing
    lock(SESSIONS_LOCK) do
        data = get(SESSIONS, sid, nothing)
        data === nothing && return nothing
        if data.flash_kind === nothing
            return nothing
        end
        kind = data.flash_kind
        msg = data.flash_msg
        data.flash_kind = nothing
        data.flash_msg = nothing
        return (kind, msg)
    end
end

# ---------------------------------------------------------------------------
# CSRF verification
# ---------------------------------------------------------------------------

"""True when the current POST carries a valid CSRF token for the session."""
function csrf_valid()::Bool
    submitted = Genie.Router.params(:_csrf, "")
    submitted === nothing && return false
    data = current_session()
    data === nothing && return false
    isempty(data.csrf) && return false
    PasswordHasher.secure_equals(String(submitted), data.csrf)
end

# ---------------------------------------------------------------------------
# Login throttling (in-memory, per session)
# ---------------------------------------------------------------------------

const LOGIN_ATTEMPTS = Dict{String,Tuple{Int,Float64}}()
const LOGIN_LOCK = ReentrantLock()
const MAX_LOGIN_ATTEMPTS = 10
const LOGIN_WINDOW_SECONDS = 10 * 60

function login_locked_out()::Bool
    sid = ensure_session!()
    lock(LOGIN_LOCK) do
        entry = get(LOGIN_ATTEMPTS, sid, nothing)
        if entry === nothing
            return false
        end
        attempts, reset_at = entry
        if reset_at < time()
            delete!(LOGIN_ATTEMPTS, sid)
            return false
        end
        return attempts >= MAX_LOGIN_ATTEMPTS
    end
end

function register_failed_login!()
    sid = ensure_session!()
    lock(LOGIN_LOCK) do
        entry = get(LOGIN_ATTEMPTS, sid, (0, time() + LOGIN_WINDOW_SECONDS))
        attempts, reset_at = entry
        if reset_at < time()
            attempts = 0
            reset_at = time() + LOGIN_WINDOW_SECONDS
        end
        LOGIN_ATTEMPTS[sid] = (attempts + 1, reset_at)
    end
    nothing
end

function clear_login_failures!()
    sid = get(task_local_storage(), :gt_sid, nothing)
    sid === nothing && return
    lock(LOGIN_LOCK) do
        delete!(LOGIN_ATTEMPTS, sid)
    end
    nothing
end
