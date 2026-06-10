# Stash Backend (Vapor 4)

The server component of Stash — a self-hosted, multi-user bookmark manager. It exposes a versioned
JSON **REST API** (`/api/v1/`) plus two server-rendered **Leaf** web UIs: an admin dashboard at
`/admin` and a user-facing frontend at `/app`. PostgreSQL in production; in-memory SQLite for tests.

The design rationale, deviations from the spec, and the history behind these features live in
[`DECISIONS.md`](../DECISIONS.md); the product spec is [`PRODUCT.md`](../PRODUCT.md). This document is
the operational reference: what the server is, its dependencies, its API, and how to run and deploy it.

## Features

- **Auth** — bcrypt passwords, JWT access tokens with rotating refresh tokens, TOTP (RFC 6238) 2FA
  enrolment/login, and single-use recovery codes.
- **Bookmarks** — per-user CRUD, duplicate-URL detection (409 with `existingID`), full-text search,
  hierarchical tag prefix filtering, pagination, and URL metadata fetching.
- **Tags** — aggregation with counts, hierarchical (`swift/vapor`) tags, rename, and delete.
- **Admin API** — user management, suspend/unsuspend, password reset, hard delete (cascading all
  owned data), and aggregate stats, gated by an admin-role middleware (non-admins get 403).
- **Web admin dashboard** (`/admin`) — server-rendered login, dashboard, user list, create user, and
  user detail, with cookie-based session auth separate from the JWT API.
- **Web frontend** (`/app`) — bookmark list with search/tag-filter/pagination,
  add/detail/edit/delete/archive, a hierarchical tag sidebar and browser, import/export, dark mode,
  and settings (password change, TOTP enrolment) with its own session cookie.
- **Docker packaging** — multi-stage `Dockerfile`, canonical `docker-compose.yml`, first-boot admin
  seeding, and a `Makefile`.

## Dependencies

All fetched automatically by SwiftPM (`swift-tools-version:5.9`, macOS 13+):

| Package | Purpose |
|---------|---------|
| [`vapor/vapor`](https://github.com/vapor/vapor) | Web framework |
| [`vapor/fluent`](https://github.com/vapor/fluent) | ORM |
| [`vapor/fluent-postgres-driver`](https://github.com/vapor/fluent-postgres-driver) | PostgreSQL driver (production) |
| [`vapor/fluent-sqlite-driver`](https://github.com/vapor/fluent-sqlite-driver) | In-memory SQLite driver (tests) |
| [`vapor/jwt`](https://github.com/vapor/jwt) | JWT signing + verification |
| [`vapor/leaf`](https://github.com/vapor/leaf) | Server-rendered HTML templates |

TOTP and Base32 are implemented directly on `swift-crypto` (a transitive Vapor dependency) rather
than via a third-party package — see [`DECISIONS.md`](../DECISIONS.md).

## Deployment (Docker)

The intended way to run Stash. Requires only Docker + the compose file:

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

The published image is `ghcr.io/otaviocc/stash:latest` (built/pushed by CI). To build it locally for
testing: `docker build -t stash:dev .`

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
swift test --filter <TestName>  # run a single test / suite
```

Tests run against an in-memory SQLite database using `VaporTesting` + swift-testing. Use the local
`withTestApp { app in ... }` helper rather than VaporTesting's `withApp` — see the note in
`Tests/AppTests/TestHelpers.swift`.

## Lint

```sh
swiftformat . --lint     # must be idempotent
swiftlint lint           # must report 0 violations
```

## API (all under `/api/v1/`, except `/health`)

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
| `DELETE` | `/tags/:tag` | access token | Delete a tag (and its children); 422 if empty; idempotent |
| `POST` | `/metadata` | access token | Fetch title/description/favicon for a URL |
| `GET`  | `/admin/users` | admin | List all users with stats |
| `POST` | `/admin/users` | admin | Create account; 409 `username_taken` on dupe |
| `GET`  | `/admin/users/:id` | admin | Single user (404 if unknown) |
| `PUT`  | `/admin/users/:id` | admin | Suspend/unsuspend (`isActive`) and/or reset `password` |
| `DELETE` | `/admin/users/:id` | admin | Hard delete + cascade all owned data (204) |
| `GET`  | `/admin/stats` | admin | Totals + per-user bookmark counts |

Errors use a standard `{ error, code, message, existingID? }` envelope across every route, including
routing 404s and validation failures.

## Web admin dashboard (server-rendered)

Unversioned, mounted at `/admin`, with its own `stash_admin_session` cookie, separate from the API.

| Method | Path | Description |
|--------|------|-------------|
| `GET`/`POST` | `/admin/login` | Login form (username + password + optional TOTP) |
| `POST` | `/admin/logout` | Clear the session |
| `GET`  | `/admin` | Dashboard: total users, total bookmarks, per-user counts |
| `GET`  | `/admin/users` | User list |
| `GET`/`POST` | `/admin/users/new` | Create user (always `user` role) |
| `GET`  | `/admin/users/:id` | User detail |
| `POST` | `/admin/users/:id/suspend` · `/unsuspend` · `/reset-password` · `/reset-totp` · `/delete` | Actions |

## Web frontend (user-facing, server-rendered)

Unversioned, mounted at `/app`, with its own `stash_session` cookie, separate from the API and the
admin dashboard.

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
| `GET`  | `/app/tags` | Tag browser (counts, links to `/app?tag=…`, inline rename/delete) |
| `POST` | `/app/tags/rename` | Rename a tag (PRG → `?ok=renamed` banner) |
| `POST` | `/app/tags/delete` | Delete a tag and its children (PRG → `?ok=deleted` banner) |
| `GET`  | `/app/settings` | Settings |
| `POST` | `/app/settings/password` | Change own password |
| `GET`  | `/app/settings/totp` · `POST /verify` · `POST /disable` | 2FA enrolment / disable (requires a current code) |
| `POST` | `/app/import` | Import bookmarks from an uploaded file (multipart; format selector) |
| `GET`  | `/app/export?format=…` | Download all bookmarks as a file (attachment) |
| `POST` | `/app/settings/delete-all-bookmarks` | Danger zone: delete all of the user's bookmarks (typed-phrase confirmation) |

Import/export is pluggable (`Sources/App/ImportExport/`); it ships with Anybox JSON and Stash JSON
importers and a Stash JSON exporter. Theme (light/dark/auto) is a `stash_theme` cookie shared by both
web UIs.
