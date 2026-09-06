#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# GenieTeam one-shot installer.
#
#   bash install.sh
#
# Installs the pinned Julia environment, applies migrations and seeds the
# demo data (idempotent), then EXITS. It never starts the web server — start
# it separately with `julia run.jl`.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

echo "==> GenieTeam install: resolving the pinned Julia environment"
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

echo "==> GenieTeam install: migrations + demo seed (idempotent)"
julia --project=. seed.jl

echo "==> GenieTeam install complete."
echo "    Run the app with:  julia run.jl"
echo "    Demo login:        cenius@cenius.ai / cenius"
