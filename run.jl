#!/usr/bin/env julia
# GenieTeam web server entrypoint.
#   julia run.jl            -> serves on 0.0.0.0:$PORT (default 8000)
# A fresh clone boots with NO .env: migrations + demo seed run automatically
# on the normal boot path, then the server starts in the foreground.
using GenieTeam

GenieTeam.boot()
