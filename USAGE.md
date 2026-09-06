# Using GenieTeam

Sign in at `/login` with the demo admin account shown on the card:
**cenius@cenius.ai / cenius**. (A second admin, `demo@example.com / password123`,
is seeded too.)

## The dashboard

After login you land on `/dashboard`:

- **KPI strip** — projects, open tasks, completed tasks (with % done), team members.
- **Projects** panel — every project by due date; click a row to open it.
- **Task status** panel — the todo / in-progress / done split.
- **Needs attention** — open tasks past their due date (red chips).
- **Upcoming** — open tasks due in the next 14 days.

`New task` and `New project` buttons are in the page header.

## Projects

- `/projects` — dense table of projects (name, due date, task count). Use **New
  project** or the header button.
- Project detail (`/projects/:id`) shows metadata and that project's tasks, with
  **Edit** and, when the project has no tasks, a **Delete** form that requires
  checking the confirmation box. Projects that still have tasks can't be deleted —
  the app explains why and points at the tasks.
- New/edit forms validate the required, workspace-unique name and optional due
  date; errors re-render the form with your input preserved.

## Tasks

- `/tasks` — every task with status pills. The chips filter by **All / To do /
  In progress / Done** (`?status=…`), and `?project_id=…` scopes to one project.
- Task detail (`/tasks/:id`) shows project, assignee, status, due date and
  description plus Edit and (confirmed) Delete.
- The new/edit form requires a title and a project, offers every team member as
  assignee, and lets you set status and due date. Status values are constrained to
  `todo / in_progress / done` server-side on every write.

## Team

- `/team` — roster with each member's role and assigned-task count.
- Member detail (`/team/:id`) shows their profile and assigned tasks. Members with
  no assignments can be removed (with confirmation); members who still have tasks
  are blocked until you reassign or delete those tasks.
- New/edit forms require a name and a valid, workspace-unique email.

## Signing out

The sidebar shows your email and a **Sign out** button (a CSRF-protected POST).
After sign-out, protected routes redirect back to `/login?next=…`.

## Notes for an evaluator

- Every mutating action is an HTML form POST protected by a per-session CSRF
  token; missing/invalid tokens get a 403 styled page.
- Passwords are stored as salted PBKDF2-HMAC-SHA256 hashes — the plaintext never
  touches the database.
- All CSS/JS/fonts are served from the same origin; nothing is fetched from the
  network while the app runs.
- The database file (`./data/genieteam.db`) is created, migrated and seeded
  automatically on the first boot — no manual setup.
