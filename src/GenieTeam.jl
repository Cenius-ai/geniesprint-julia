# ---------------------------------------------------------------------------
# GenieTeam — a Genie.jl powered, server-rendered team workspace.
#
# Single module, ordered includes. Loading this module only defines code; the
# app actually starts when you call `GenieTeam.boot()` (run.jl) or runs its
# database prep only via `GenieTeam.seed_command()` (seed.jl).
# ---------------------------------------------------------------------------

module GenieTeam

using Genie
using HTTP


using Random
using SHA
using Dates
using SearchLight
using SearchLightSQLite
using SQLite
using DBInterface
using DataFrames

# 1. Environment, date/validation utilities, crypto primitives
include("appenv.jl")
include("util.jl")
include("password.jl")

# 2. Domain types + repository (SQLite through SearchLight's adapter)
include("models.jl")
include("db.jl")

# 3. Idempotent demo seed (runs on boot when the DB is empty; runnable standalone)
include(joinpath(PROJECT_ROOT, "db", "seeds.jl"))

"""Connects, migrates and seeds (only when empty). Safe on every boot."""
function prepare_database!()
    repo_connect!()
    repo_migrate!()
    seed_if_empty!()
    nothing
end

# 4. Sessions / CSRF / flash (built on Genie's HTTP plumbing)
include("session.jl")

# 5. Views (helpers, layouts, pages)
include("views/helpers.jl")
include("views/layouts.jl")
include("views/pages_auth.jl")
include("views/pages_dashboard.jl")
include("views/pages_projects.jl")
include("views/pages_tasks.jl")
include("views/pages_team.jl")

# 6. Controllers, routes, web hooks and boot
include("controllers.jl")
include("routes.jl")
include("web.jl")

end # module GenieTeam
