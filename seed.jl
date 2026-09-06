#!/usr/bin/env julia
# Standalone seed entrypoint (used by install.sh and by verification phases).
# Connects -> migrates -> seeds idempotently, prints a summary, and EXITS.
# It never starts the HTTP server, so it never holds the app port.
using GenieTeam

GenieTeam.seed_command()
exit(0)
