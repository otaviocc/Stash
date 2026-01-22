# Stash Backend (Vapor 4)

REST API for Stash.

- **M1** — auth foundation: User model, bcrypt passwords, JWT access tokens + rotating
  refresh tokens, TOTP 2FA enrolment/login, single-use recovery codes.
- **M2** — bookmarks: CRUD scoped to the user, duplicate-URL detection (409 with `existingID`),
  tag aggregation, full-text search, hierarchical tag prefix filtering, pagination, and
  metadata fetching.
- **M3** — admin API: user management (`/admin/users`), suspend/unsuspend, password reset,
  hard delete (cascading all owned data), and aggregate stats — all gated by an admin-role
  middleware (non-admins get 403).
- **M4** — Docker packaging: multi-stage `Dockerfile` (`swift:5.10` build → `ubuntu:22.04`
  runtime, `linux/amd64` + `linux/arm64`), canonical `docker-compose.yml`, first-boot admin
  seeding, and a `Makefile`.
- **M5** — web admin dashboard: server-rendered Leaf pages at `/admin` (login, dashboard, user
  list, create user, user detail) with cookie-based session auth, separate from the JWT API.
- **M11** — user-facing web frontend: server-rendered Leaf pages at `/app` (bookmark list with
  search/tag-filter/pagination, add/detail/edit/delete/archive, tag browser, settings with
  password change and TOTP enrolment) with its own `stash_session` cookie.

## Deployment (Docker)

The intended way to run Stash (PRD §16). Requires only Docker + the compose file:

```sh
cp .env.example .env            # then fill in real secrets (never commit .env)
make up                         # docker compose up -d  → http://<host>:8080
make logs                       # tail the app logs
make down                       # stop the stack
```

On first boot, if the database has no users, the app creates the admin account from
`ADMIN_USERNAME` / `ADMIN_PASSWORD`. If those are missing it logs an error and exits rather than
starting a login-less instance. Once an admin exists, the variables are ignored. Database
migrations run automatically on boot; `make migrate` runs them explicitly inside the container if
ever needed.

The published image is `ghcr.io/otaviocc/stash:latest` (built/pushed by CI in M4.1). To build it
locally for testing: `docker build -t stash:dev .`

## Local development

`make build` / `make test` need no database. To run the server directly against a local
Postgres, export the variables the app reads at runtime:

```sh
export DATABASE_URL=postgres://stash:password@localhost:5432/stash
export JWT_SECRET=$(openssl rand -base64 48)
export ADMIN_USERNAME=admin ADMIN_PASSWORD=change-me-min-12
swift run App serve             # migrations + admin seeding run on boot
```

## Tests

```sh
swift test
```

Tests run against an in-memory SQLite database (per PRD §17.7) using `VaporTesting` +
swift-testing. Use the local `withTestApp { app in ... }` helper rather than VaporTesting's
`withApp` — see the note in `Tests/AppTests/TestHelpers.swift`.

## Endpoints (all under `/api/v1/`, except `/health`)

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| `POST` | `/auth/login` | — | Returns a token pair, or `{requires2FA, tempToken}` |
| `POST` | `/auth/totp` | temp token | Submit TOTP code |
| `POST` | `/auth/recovery` | temp token | Redeem a single-use recovery code |
| `POST` | `/auth/refresh` | — | Rotates the refresh token |
| `POST` | `/auth/logout` | — | Deletes the refresh token (204) |
| `GET`  | `/health` | — | Unversioned health check |
| `GET`  | `/me` | access token | Current user profile |
| `PUT`  | `/me/password` | access token | `{currentPassword, newPassword}` |
| `GET`  | `/auth/totp/setup` | access token | Begin 2FA enrolment |
| `POST` | `/auth/totp/verify-setup` | access token | Confirm; returns 8 recovery codes once |
| `GET`  | `/bookmarks` | access token | List; `?q=&tag=&archived=&page=&per=` |
| `POST` | `/bookmarks` | access token | Create; 409 `duplicate_url` (+`existingID`) on dupe |
| `GET`  | `/bookmarks/:id` | access token | Single bookmark (404 if not yours) |
| `PUT`  | `/bookmarks/:id` | access token | Update (all fields optional) |
| `DELETE` | `/bookmarks/:id` | access token | Delete (204) |
| `GET`  | `/tags` | access token | Distinct tags with counts |
| `POST` | `/tags/rename` | access token | Rename a tag (and its children); 422 if `from`/`to` empty |
| `POST` | `/metadata` | access token | Fetch title/description/favicon for a URL |
| `GET`  | `/admin/users` | admin | List all users with stats |
| `POST` | `/admin/users` | admin | Create account; 409 `username_taken` on dupe |
| `GET`  | `/admin/users/:id` | admin | Single user (404 if unknown) |
| `PUT`  | `/admin/users/:id` | admin | Suspend/unsuspend (`isActive`) and/or reset `password` |
| `DELETE` | `/admin/users/:id` | admin | Hard delete + cascade all owned data (204) |
| `GET`  | `/admin/stats` | admin | Totals + per-user bookmark counts |

## Web admin dashboard (server-rendered, session cookie — PRD §11)

Unversioned, mounted at `/admin`, separate from the API above.

| Method | Path | Description |
|--------|------|-------------|
| `GET`/`POST` | `/admin/login` | Login form (username + password + optional TOTP) |
| `POST` | `/admin/logout` | Clear the session |
| `GET`  | `/admin` | Dashboard: total users, total bookmarks, per-user counts |
| `GET`  | `/admin/users` | User list |
| `GET`/`POST` | `/admin/users/new` | Create user (always `user` role) |
| `GET`  | `/admin/users/:id` | User detail |
| `POST` | `/admin/users/:id/suspend` · `/unsuspend` · `/reset-password` · `/reset-totp` · `/delete` | Actions |

### M5 notes

- **Session auth** uses a cookie (`stash_admin_session`, in-memory store), wholly separate from
  the API's JWT flow. `AdminSessionMiddleware` loads the admin from the session and redirects to
  `/admin/login` if it's missing, the account is gone, suspended, or no longer an admin.
- **Same business rules as the API**, enforced in the web handlers: dashboard-created accounts are
  always `user` role (the form has no role field, and any submitted one is ignored); suspension and
  password reset both revoke the target's refresh tokens; self-deletion is blocked (returns 400).
- **Templates** live in `Resources/Views` (one `layout.leaf` + five pages), copied into the Docker
  image by the Dockerfile. Plain HTML forms, inline CSS, no JS framework.

## Web frontend (user-facing, server-rendered — PRD §5, P2)

Unversioned, mounted at `/app`, separate from the API and the admin dashboard.

| Method | Path | Description |
|--------|------|-------------|
| `GET`/`POST` | `/app/login` | Login (username + password + optional TOTP); any active role |
| `POST` | `/app/logout` | Clear the session |
| `GET`  | `/app` | Bookmark list; `?q=`, `?tag=` (prefix), `?archived=true`, `?page=` |
| `GET`  | `/app/bookmarks/new` | Add bookmark form |
| `POST` | `/app/bookmarks` | Create (`action=preview` fetches metadata; `action=save` persists) |
| `GET`  | `/app/bookmarks/:id` | Detail |
| `GET`  | `/app/bookmarks/:id/edit` | Edit form |
| `POST` | `/app/bookmarks/:id` | Update (title, description, tags, archived) |
| `POST` | `/app/bookmarks/:id/delete` · `/archive` · `/unarchive` | Actions |
| `GET`  | `/app/tags` | Tag browser (counts, links to `/app?tag=…`, inline rename) |
| `POST` | `/app/tags/rename` | Rename a tag (PRG → `?ok=renamed` banner) |
| `GET`  | `/app/settings` | Settings |
| `POST` | `/app/settings/password` | Change own password |
| `GET`  | `/app/settings/totp` · `POST /verify` · `POST /disable` | 2FA enrolment (recovery codes shown once) / disable (requires a current code) |
| `POST` | `/app/import` | Import bookmarks from an uploaded file (multipart; format selector) |
| `GET`  | `/app/export?format=…` | Download all bookmarks as a file (attachment) |
| `POST` | `/app/settings/delete-all-bookmarks` | Danger zone: delete all of the user's bookmarks (typed-phrase confirmation) |

### M11 notes

- **Tag sidebar** on `/app`: a two-column layout adds a right-hand hierarchical tag tree (sorted,
  indented by depth, counts shown, active tag + "All" highlighted) plus an **"Untagged"** filter
  (`?tag=__untagged__`, an internal sentinel never shown as a label). The tree is built server-side
  into a flattened pre-ordered list (`SidebarTag` with `depth`) since Leaf doesn't recurse; synthetic
  parents are included for nesting. The sidebar and bookmark list are two plain flex
  columns that scroll together with the page (no sticky/fixed/independent scrolling); the sidebar is
  hidden below 768px (the on-list filter pills cover mobile). All colours use the
  dark-mode CSS variables; `/app/tags` is unchanged.
- **Dark mode** (light / dark / auto) is chosen in `/app/settings` and stored in a 1-year,
  site-wide (`path=/`) `stash_theme` cookie that themes both `/app` and `/admin`. All colours are
  CSS variables in `layout.leaf` (`:root` light, `[data-theme="dark"]` explicit, and a
  `prefers-color-scheme` media query for auto); an inline script at the top of `<head>` applies the
  saved theme before paint to avoid a flash. No DB change — it's a presentation cookie
  (`HTTPOnly=false` so the script can read it).
- **Session auth** uses its own cookie (`stash_session`, path `/app`), distinct from the admin
  dashboard's `stash_admin_session` but sharing the same in-memory store. `UserSessionMiddleware`
  admits any **active** account regardless of role; suspended accounts are rejected at login and
  on every request.
- **Scoped to the user** — every bookmark/tag query filters on the authenticated user's ID, so one
  user can never reach another's data (cross-user access redirects to the list).
- **Same rules as the API**: tags normalised on write (trimmed, lowercased, de-duplicated);
  duplicate URL on create shows an inline error linking to the existing bookmark (its `existingID`);
  `?tag=swift` prefix-matches `swift/*`. Hierarchical tags display as `swift › vapor`, stored as
  `swift/vapor`.
- **Add flow** is two-button, no JS: "Fetch metadata" previews title/description via an inline
  server-side fetch; "Save" persists (also auto-fetching any blank fields).
- **Reuses `layout.leaf`** — same base template and inline CSS as the admin dashboard, with a
  user nav. Nine `app-*.leaf` templates. 2FA setup shows the otpauth URI + setup key for manual
  entry (a scannable QR image would need a QR-encoding dependency, omitted for the minimal build).
- **Self-service 2FA disable** (`POST /app/settings/totp/disable`) requires a *current TOTP code*
  (not just a password) to confirm authenticator access, then clears the secret/flag and recovery
  codes. **Admins** can reset a user's 2FA from the user detail page
  (`POST /admin/users/:id/reset-totp`); that also revokes the user's refresh tokens, forcing
  re-login (self-reset allowed).
- **Tag autocomplete** on the create/edit forms: the user's existing tags are embedded as a JSON
  array in a `data-known-tags` attribute (no extra request), and a ~50-line dependency-free vanilla
  JS block in `layout.leaf` filters the comma-segment under the cursor and offers prefix matches
  (full hierarchical strings like `swift/vapor` included).

### Import / export

- **Pluggable formats** via `Sources/App/ImportExport/`: conform to `BookmarkImporter` /
  `BookmarkExporter` and add a `register(...)` line in `ImportExportRegistry.init` — the settings
  selectors and routes pick it up automatically. Ships with the **Anybox JSON** and **Stash JSON**
  importers and the **Stash JSON** exporter (so a Stash export round-trips as a restore).
- **Anybox import** is flat (folders ignored). Anybox stores `tags` as `[namespace, value]` pairs,
  which are joined into hierarchical tags (`["status","paid"]` → `status/paid`) then normalised; the
  ISO-8601 `dateAdded` becomes `createdAt`. Existing bookmarks (matched by URL) are updated in
  place. Unparseable files show an inline error; bad records are counted and listed in a
  `<details>` block. Settings shows the result after a Post/Redirect/Get with a session-flashed
  summary.
- **Stash export** emits the native `{ version, exportedAt, bookmarks[] }` format — all bookmarks
  (archived included), sorted by `createdAt` — as an attachment download.

### M4 notes

- **Image** is a two-stage build: `swift:5.10-jammy` compiles a release binary with a statically
  linked Swift stdlib; the runtime stage is a minimal `ubuntu:22.04` with only the binary and the
  required system libraries. The jammy build base matches the 22.04 runtime for ABI compatibility,
  and the Dockerfile is arch-agnostic so `buildx` produces `linux/amd64` and `linux/arm64`.
- **First-boot seeding** (`AdminSeeder`, invoked from `configure.swift` after migrations) creates
  the admin from `ADMIN_USERNAME` / `ADMIN_PASSWORD` only when the database has no users; it
  throws (exits) on missing/invalid credentials and is a no-op once any user exists. It never runs
  against the test database.
- **Migrations auto-run on boot** so the canonical `docker compose up -d` works with zero manual
  steps; Fluent tracks applied migrations, so this is idempotent.

### M3 notes

- **Admin role** is enforced by `AdminMiddleware`, layered after the access-token authenticator;
  non-admins get 403 `forbidden` in the standard envelope.
- **Account creation is always `user` role** — any `role` field in the `POST /admin/users` body is
  silently ignored. Admin accounts exist only via first-boot seeding (PRD §4).
- **Suspension** (`PUT {isActive: false}`) and **password reset** (`PUT {password: …}`) both
  immediately delete all of the user's refresh tokens, forcing re-authentication (PRD §8.6);
  in-flight access tokens lapse within their 15-minute window.
- **Self-deletion is blocked** — `DELETE /admin/users/:id` targeting the caller's own ID returns
  400 `cannot_delete_self`.
- **Hard delete** explicitly removes the user's bookmarks, refresh tokens, and recovery codes
  before the user row — so it behaves identically on SQLite (tests) and Postgres regardless of
  FK-cascade enforcement.
- **Per-user bookmark counts** use the denormalised `User.bookmarkCount` field (PRD §7.1), the
  same source as `/me`; the test helper maintains it so stats reflect reality.

### M2 notes

- **Tags** are normalised (trimmed, lowercased, de-duplicated). A derived `tags_search` column
  (`|swift|swift/vapor|`) makes the hierarchical prefix filter (`tag=swift` matches `swift` and
  `swift/*`) a portable `LIKE` query across both SQLite and Postgres.
- **Metadata fetching** uses Vapor's built-in HTTP client (5s timeout, no retry) and a
  dependency-free regex HTML parser (`MetadataFetcher`). It never blocks a save: on any failure the
  bookmark is saved with whatever the client supplied. Client-supplied title/description take
  precedence over fetched values.
- **Full-text search** (`q`) matches across URL, title, description, and tags (via the
  `tags_search` column) using SQL `LIKE` (`~~`); matching is case-insensitive on SQLite and
  case-sensitive on Postgres.

## Deviation from PRD §17.2

The PRD lists `vapor/auth.git` (`from: "2.0.0"`) for "built-in RFC-compliant TOTP". That package
is the **Vapor 3-era** authentication package and does not exist for / compile against Vapor 4
(in Vapor 4, `Authenticatable` and friends are part of Vapor core, and there is no bundled TOTP).
TOTP (RFC 6238) and Base32 are therefore implemented directly on top of `swift-crypto` (already a
transitive Vapor dependency) in `Sources/App/Auth/`. This keeps the backend dependency-light, in
line with the project's data-ownership philosophy. `fluent-sqlite-driver` is also added (not in the
table) because §17.7 mandates an in-memory SQLite test database.
