# Stash Backend (Vapor 4)

REST API for Stash. This milestone (**M1**) implements the authentication foundation:
User model, bcrypt passwords, JWT access tokens + rotating refresh tokens, TOTP 2FA
enrolment/login, and single-use recovery codes.

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

## Deviation from PRD §17.2

The PRD lists `vapor/auth.git` (`from: "2.0.0"`) for "built-in RFC-compliant TOTP". That package
is the **Vapor 3-era** authentication package and does not exist for / compile against Vapor 4
(in Vapor 4, `Authenticatable` and friends are part of Vapor core, and there is no bundled TOTP).
TOTP (RFC 6238) and Base32 are therefore implemented directly on top of `swift-crypto` (already a
transitive Vapor dependency) in `Sources/App/Auth/`. This keeps the backend dependency-light, in
line with the project's data-ownership philosophy. `fluent-sqlite-driver` is also added (not in the
table) because §17.7 mandates an in-memory SQLite test database.
