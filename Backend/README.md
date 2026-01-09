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

## Running locally

```sh
cp .env.example .env            # then edit values
export $(grep -v '^#' .env | xargs)
swift run App migrate --yes     # run migrations against DATABASE_URL (Postgres)
swift run App serve             # serves on http://127.0.0.1:8080
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

### M3 notes

- **Admin role** is enforced by `AdminMiddleware`, layered after the access-token authenticator;
  non-admins get 403 `forbidden` in the standard envelope.
- **Suspension** (`PUT {isActive: false}`) immediately deletes all of the user's refresh tokens
  (PRD §8.6); in-flight access tokens lapse within their 15-minute window.
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
