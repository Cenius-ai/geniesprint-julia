# ---------------------------------------------------------------------------
# Application environment: paths and env-var handling with dev defaults.
#
# Bootability contract: the app must start from a fresh clone with NO .env at
# all. Every variable below therefore has a working in-code default of the
# correct *shape*; production operators can override via .env / environment.
# ---------------------------------------------------------------------------

"""Absolute path of the project root (the directory that contains Project.toml)."""
const PROJECT_ROOT = abspath(joinpath(@__DIR__, ".."))

"""Default location of the embedded SQLite database, relative to the project root."""
const DEFAULT_DB_RELATIVE = joinpath("data", "genieteam.db")

"""
    db_path() -> String

Resolves the SQLite file path. Honors `GENIETEAM_DB_PATH` (path shape) and
falls back to `./data/genieteam.db` inside the project root.
"""
function db_path()::String
    p = get(ENV, "GENIETEAM_DB_PATH", "")
    if isempty(p)
        return abspath(joinpath(PROJECT_ROOT, DEFAULT_DB_RELATIVE))
    end
    isabspath(p) ? abspath(p) : abspath(joinpath(PROJECT_ROOT, p))
end

# Dev-only signing/encryption fallback. The same literal is used everywhere a
# secret is read (see app_secret below), so session cookies signed in one layer
# verify in every other layer. Override with GENIETEAM_SECRET in production.
const DEV_SECRET_FALLBACK = "cenius-dev-9f2c4a7e1b6d8f3a"

"""
    app_secret() -> String

The key used for cookie signing. Reads `GENIETEAM_SECRET`; empty/missing falls
back to a clearly-marked dev-only literal so a fresh clone boots with nothing
configured.
"""
function app_secret()::String
    s = get(ENV, "GENIETEAM_SECRET", "")
    isempty(s) ? DEV_SECRET_FALLBACK : s
end

"""Port the web server binds. Honors the PORT env var; framework default is 8000."""
function server_port()::Int
    p = get(ENV, "PORT", "")
    if isempty(p)
        return 8000
    end
    parsed = tryparse(Int, p)
    parsed === nothing ? 8000 : parsed
end

"""Host the web server binds (must be externally reachable in sandboxes)."""
server_host() = "0.0.0.0"

"""Base path for static assets (document root under the project)."""
static_document_root() = abspath(joinpath(PROJECT_ROOT, "public"))
