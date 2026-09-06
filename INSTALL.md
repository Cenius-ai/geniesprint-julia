# Install & run

GenieTeam is a Julia 1.10 application. The **only** package manager is Julia's
built-in `Pkg`; the committed `Manifest.toml` pins every dependency.

## Prerequisites

- Julia 1.10+ on the `PATH`.

## Step 1 — Install (one command, then it exits)

```bash
bash install.sh
```

This:
1. `Pkg.instantiate()` — resolves the pinned environment from `Manifest.toml`;
2. `Pkg.precompile()` — pays the compilation cost up front;
3. runs `julia seed.jl` — applies the idempotent migrations and seeds the demo
   workspace (admin + 4 team members + 3 projects + 8 tasks).

`install.sh` never starts the server, so it always exits. Re-running it is safe.

## Step 2 — Seed (already covered by step 1, separate entrypoint for automation)

```bash
julia seed.jl
```

Connects → migrates → seeds idempotently, prints a summary, and exits. It never
binds the HTTP port.

## Step 3 — Run in dev / production

```bash
julia run.jl
```

The server binds `0.0.0.0` on `$PORT` (default **8000**). On boot it re-checks
migrations, seeds only if the database is empty, and then serves. Press Ctrl+C to
stop.

Open http://localhost:8000 and sign in with:

| Email | Password |
| --- | --- |
| cenius@cenius.ai | cenius |

## Step 4 — Test

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Runs the offline suite (no network): password hashing, migrations + idempotent
seed, repository CRUD and FK-safe deletes, session cookie signing/verification,
and the end-to-end HTTP contract (auth wall, CSRF, demo login, dashboard, status
filter, persistent create form, logout).

## Environment

No environment variables are required. If you want to override defaults, copy
`.env.example` to `.env` (or export the variables):

- `PORT` — HTTP port (default 8000)
- `GENIETEAM_DB_PATH` — SQLite file location (default `./data/genieteam.db`)
- `GENIETEAM_SECRET` — session-cookie signing key. **Required for production**;
  the built-in dev fallback is clearly marked as such.

## Troubleshooting

- `Address already in use` — another process holds the port; pick another with
  `PORT=8001 julia run.jl`.
- Data lives in `./data/genieteam.db`; delete that file to reset to a fresh,
  auto-seeded workspace.
