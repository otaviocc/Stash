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
| `POST` | `/metadata` | access token | Fetch title/description/favicon for a URL |
| `GET`  | `/admin/users` | admin | List all users with stats |
| `POST` | `/admin/users` | admin | Create account; 409 `username_taken` on dupe |
| `GET`  | `/admin/users/:id` | admin | Single user (404 if unknown) |
| `PUT`  | `/admin/users/:id` | admin | Suspend/unsuspend (`isActive`) and/or reset `password` |
| `DELETE` | `/admin/users/:id` | admin | Hard delete + cascade all owned data (204) |
| `GET`  | `/admin/stats` | admin | Totals + per-user bookmark counts |

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
- **Full-text search** (`q`) uses SQL `LIKE` (`~~`); matching is case-insensitive on SQLite and
  case-sensitive on Postgres.

## Deviation from PRD §17.2

The PRD lists `vapor/auth.git` (`from: "2.0.0"`) for "built-in RFC-compliant TOTP". That package
is the **Vapor 3-era** authentication package and does not exist for / compile against Vapor 4
(in Vapor 4, `Authenticatable` and friends are part of Vapor core, and there is no bundled TOTP).
TOTP (RFC 6238) and Base32 are therefore implemented directly on top of `swift-crypto` (already a
transitive Vapor dependency) in `Sources/App/Auth/`. This keeps the backend dependency-light, in
line with the project's data-ownership philosophy. `fluent-sqlite-driver` is also added (not in the
table) because §17.7 mandates an in-memory SQLite test database.
