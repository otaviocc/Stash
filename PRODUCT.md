# Stash — Product Requirements Document

**Version:** 1.3  
**Status:** Living Document  
**Author:** Otávio  

---

## 1. Overview

Stash is a self-hosted, fully private bookmark manager. It is multi-user: accounts are created by an admin, and each user manages their own private collection of bookmarks. It consists of a Swift/Vapor REST API backend backed by PostgreSQL, deployable via Docker, with native clients for iOS, macOS, and the command line planned. A shared Swift package (`StashKit`) provides models and networking logic across all clients.

The core philosophy: **full data ownership, self-hosted, no third-party cloud.**

---

## 2. Goals

- Save bookmarks quickly from any Apple platform via Share Extensions or the CLI
- Retrieve bookmarks reliably via keyword search, tag browsing, or recency
- Organise bookmarks with both flat and hierarchical tags
- Auto-fetch page metadata (title, description, favicon) at save time, with manual override
- Support multiple users, each with a fully isolated bookmark collection
- Admin can create, suspend, and hard-delete accounts, reset passwords and 2FA — via web dashboard and CLI
- Users authenticate with username + password + TOTP-based 2FA, with recovery codes
- Users can enable, disable, and manage their own 2FA
- Users can change their own password
- Duplicate URLs per user are blocked at save time
- Import bookmarks from Anybox JSON export and Stash JSON
- Export bookmarks in Stash native JSON format
- Keep all data on infrastructure the user controls
- Remain fully private — no public sharing, no public registration

---

## 3. Non-Goals (v1)

- Public or open registration
- Cross-user bookmark visibility or sharing
- Page content archiving or offline reading
- Public or shared collections
- Browser extension
- Read-later / queue functionality
- SSO or OAuth
- Menu bar app (macOS)

---

## 4. User Roles

| Role | Description |
|------|-------------|
| **Admin** | The primary user. Can manage all accounts, reset any user's 2FA. Has their own bookmark collection like any other user. |
| **User** | A regular account created by the admin. Can manage their own bookmarks, change their own password, and manage their own 2FA. Cannot see other users' data. |

There is exactly one admin. The admin account is seeded at first boot via environment variables — there is no public sign-up flow.

---

## 5. Platforms

| Platform | Type | Status |
|----------|------|--------|
| Backend | Vapor 4 REST API | ✅ Complete |
| Web admin dashboard | Server-rendered (Leaf) | ✅ Complete |
| Web frontend (user-facing) | Server-rendered (Leaf) | ✅ Complete |
| iOS | Native SwiftUI app + Share Extension | Planned (M8, M9) |
| macOS | Native SwiftUI app + Share Extension | Planned (M10) |
| CLI (`stash`) | Swift CLI tool | Planned (M7) |

---

## 6. Architecture

```
┌───────────────────────────────────────────────────────┐
│                       Clients                         │
│  iOS App   macOS App   CLI   Web Dashboard   Web App  │
└──────────────────────────┬────────────────────────────┘
                           │ HTTPS / REST
                           ▼
┌───────────────────────────────────────────────────────┐
│              Stash Backend (Vapor 4)                  │
│                                                       │
│  Auth Middleware (JWT access token)                   │
│  Role Middleware (admin / user)                       │
│  Routes → Controllers → Fluent ORM                   │
│  Metadata Fetcher (async, non-blocking)               │
│  ImportExportRegistry (pluggable importers/exporters) │
└──────────────────────────┬────────────────────────────┘
                           │
                           ▼
┌───────────────────────────────────────────────────────┐
│                  PostgreSQL 16                        │
└───────────────────────────────────────────────────────┘

StashKit (Swift Package) — Planned
  └── Shared by: iOS app, macOS app, CLI
  └── Contains: Models, APIClient
```

---

## 7. Data Model

### 7.1 User

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `username` | String | Unique, lowercase |
| `passwordHash` | String | Bcrypt, cost factor 12 |
| `totpSecret` | String? | Base32-encoded; null until 2FA enrolled |
| `isTOTPEnabled` | Bool | Default false |
| `role` | Enum | `admin` or `user` |
| `isActive` | Bool | False = suspended, cannot log in |
| `bookmarkCount` | Int | Denormalised; updated on bookmark create/delete |
| `createdAt` | Date | Auto-set |
| `updatedAt` | Date | Auto-updated |

### 7.2 Bookmark

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `userID` | UUID | Foreign key → User; all queries scoped to this |
| `url` | String | Required, valid URL, unique per user |
| `title` | String | Auto-fetched, overridable |
| `description` | String? | Auto-fetched, overridable |
| `faviconURL` | String? | Auto-fetched |
| `tags` | [String] | Flat or hierarchical (e.g. `swift/vapor`) |
| `tagsSearch` | String | Derived column (`\|swift\|swift/vapor\|`) for portable LIKE queries |
| `isArchived` | Bool | Default false |
| `createdAt` | Date | Auto-set |
| `updatedAt` | Date | Auto-updated |

**Duplicate URL constraint:** a unique index on `(userID, url)` enforces one bookmark per URL per user. The API returns HTTP 409 Conflict if a duplicate is attempted.

### 7.3 Refresh Token

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `userID` | UUID | Foreign key → User |
| `tokenHash` | String | SHA-256 hash of the raw token |
| `expiresAt` | Date | 90 days from issuance |
| `createdAt` | Date | Auto-set |

Refresh tokens are stored hashed. On rotation, the old token is deleted and a new one is issued. On logout, the token is deleted. On account suspension, deletion, password reset (admin), or 2FA disable/reset, all tokens for that user are deleted.

### 7.4 Recovery Code

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `userID` | UUID | Foreign key → User |
| `codeHash` | String | Bcrypt hash of the raw code |
| `usedAt` | Date? | Null until redeemed; once used, cannot be reused |

Eight recovery codes are generated at 2FA enrolment. Each is single-use. Stored hashed. All recovery codes are deleted when 2FA is disabled or reset.

### 7.5 Tags

Tags are plain strings stored on each bookmark. Hierarchical tags use slash notation: `swift/vapor`, `swift/uikit`, `music/jazz`. The tag tree is derived dynamically per user — no separate tag table.

A derived `tagsSearch` column stores tags in `|swift|swift/vapor|` format for portable prefix-matching via SQL `LIKE` queries. This works consistently across both SQLite (tests) and PostgreSQL (production).

Querying `tag=swift` returns all bookmarks where `tagsSearch` contains `|swift` (prefix match: matches `swift` and `swift/*`).

**Tag normalisation:** all tags are normalised on write — trimmed of whitespace, lowercased, and de-duplicated. Enforced server-side. `Swift`, `swift`, and `  Swift  ` all resolve to `swift`.

---

## 8. Authentication & Security

### 8.1 Token Strategy

| Token | Lifetime | Storage (client) |
|-------|----------|-----------------|
| Access token (JWT) | 15 minutes | Memory only (never persisted to disk) |
| Refresh token (opaque) | 90 days, rotated on use | Keychain (iOS/macOS), `~/.config/stash/tokens.json` (CLI), session cookie (web) |

Silent refresh: client checks expiry within 60 seconds and calls `POST /api/v1/auth/refresh` transparently before each request.

### 8.2 Login Flow

```
1. POST /api/v1/auth/login  { username, password }
   → If 2FA disabled: { accessToken, refreshToken }
   → If 2FA enabled:  { requires2FA: true, tempToken: "<5-min JWT, limited scope>" }

2. POST /api/v1/auth/totp   { tempToken, totpCode }
   → { accessToken, refreshToken }

3. POST /api/v1/auth/refresh { refreshToken }
   → { accessToken, refreshToken }  (old refresh token invalidated)

4. POST /api/v1/auth/logout  { refreshToken }
   → 204 No Content  (refresh token deleted from DB)
```

### 8.3 2FA Enrolment Flow

```
1. GET  /api/v1/auth/totp/setup
   → { secret: "<base32>", otpauthURI: "otpauth://totp/Stash:username?secret=..." }
   Web UI: shows otpauth URI + manual key (no server-side QR — CoreImage unavailable on Linux)
   Native clients: display QR code from otpauthURI

2. POST /api/v1/auth/totp/verify-setup  { totpCode }
   → { recoveryCodes: ["ABCD-EFGH", ...] }  (8 codes, shown once, never retrievable again)
   Server sets isTOTPEnabled = true, stores hashed codes.
```

Recovery codes shown exactly once. Client must require explicit "I've saved these" confirmation before dismissal.

### 8.4 Recovery Code Login Flow

```
POST /api/v1/auth/login  { username, password }
→ { requires2FA: true, tempToken }

POST /api/v1/auth/recovery  { tempToken, recoveryCode }
→ { accessToken, refreshToken }
Server marks the code as used (sets usedAt). It cannot be reused.
```

### 8.5 2FA Disable Flow

**User self-service:** requires current TOTP code to confirm. Clears `totpSecret`, sets `isTOTPEnabled = false`, deletes all recovery codes, invalidates all refresh tokens.

**Admin reset:** no confirmation code required. Same effect — clears TOTP secret, disables 2FA, deletes recovery codes, invalidates all refresh tokens for the target user. Self-reset is allowed.

### 8.6 Password Rules

- Minimum 12 characters
- Stored as bcrypt hash, cost factor 12

### 8.7 Account Suspension & Deletion

- **Suspension:** `isActive = false`. All refresh tokens immediately deleted.
- **Password reset (admin):** all refresh tokens for the target user immediately deleted.
- **Hard deletion:** all bookmarks, refresh tokens, and recovery codes cascade-deleted. No soft delete.
- **2FA disable/reset:** all refresh tokens deleted, forcing re-login.

---

## 9. API Specification

### 9.1 Auth Endpoints (unauthenticated)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/auth/login` | Submit username + password |
| `POST` | `/api/v1/auth/totp` | Submit TOTP code after login |
| `POST` | `/api/v1/auth/recovery` | Submit recovery code after login |
| `POST` | `/api/v1/auth/refresh` | Rotate refresh token, get new access token |
| `POST` | `/api/v1/auth/logout` | Invalidate refresh token |
| `GET` | `/health` | Health check (unversioned) |

### 9.2 User Endpoints (authenticated, any role)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/me` | Get current user profile |
| `PUT` | `/api/v1/me/password` | Change own password |
| `GET` | `/api/v1/auth/totp/setup` | Begin 2FA enrolment |
| `POST` | `/api/v1/auth/totp/verify-setup` | Confirm 2FA enrolment; returns recovery codes |
| `POST` | `/api/v1/auth/totp/disable` | Disable own 2FA (requires current TOTP code) |

### 9.3 Bookmark Endpoints (authenticated, scoped to current user)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/bookmarks` | List bookmarks |
| `POST` | `/api/v1/bookmarks` | Create bookmark; returns 409 if URL already saved |
| `GET` | `/api/v1/bookmarks/:id` | Get single bookmark |
| `PUT` | `/api/v1/bookmarks/:id` | Update bookmark |
| `DELETE` | `/api/v1/bookmarks/:id` | Delete bookmark |

**`GET /api/v1/bookmarks` query parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `q` | String | Full-text search across URL, title, description. Case-insensitive (`ILIKE` on PostgreSQL). |
| `tag` | String | Filter by tag (prefix match: `swift` matches `swift` and `swift/*`, not `swiftui`) |
| `archived` | Bool | Default false; pass `true` for archived bookmarks |
| `page` | Int | Page number, default 1 |
| `per` | Int | Results per page, default 20, max 100 (clamped) |

### 9.4 Tag Endpoints (authenticated, scoped to current user)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/tags` | List all tags with counts for current user |

### 9.5 Metadata Endpoint (authenticated)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/metadata` | Fetch title, description, favicon for a URL without saving |

### 9.6 Admin Endpoints (authenticated, admin role only)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/admin/users` | List all users with stats |
| `POST` | `/api/v1/admin/users` | Create a new user account (always `user` role) |
| `GET` | `/api/v1/admin/users/:id` | Get a single user |
| `PUT` | `/api/v1/admin/users/:id` | Suspend/unsuspend, reset password (invalidates tokens) |
| `DELETE` | `/api/v1/admin/users/:id` | Hard-delete user and all their data (cannot delete self) |
| `POST` | `/api/v1/admin/users/:id/reset-totp` | Reset user's 2FA (invalidates tokens) |
| `GET` | `/api/v1/admin/stats` | Aggregate stats (total users, total bookmarks, per-user counts) |

---

## 10. Metadata Fetching — Backend Behaviour

When a bookmark is created with `fetchMetadata: true` (default):

1. HTTP GET to the URL
2. Parses `<title>`, `<meta name="description">`, favicon (`<link rel="icon">` or `/favicon.ico` fallback) using a dependency-free regex parser (`MetadataFetcher`) over Vapor's built-in HTTP client
3. Client-supplied values take precedence over fetched ones
4. If fetching fails (timeout, 4xx/5xx), save proceeds with whatever the client supplied — never blocks the save

Timeout: 5 seconds. No retry.

---

## 11. Import & Export

### 11.1 Architecture

A pluggable `ImportExportRegistry` allows new formats to be added by conforming to protocols and registering — no controller changes required.

```swift
protocol BookmarkImporter {
    static var identifier: String { get }
    static var displayName: String { get }
    static var fileExtension: String { get }
    func `import`(from data: Data, for userID: UUID, on db: Database) async throws -> ImportResult
}

protocol BookmarkExporter {
    static var identifier: String { get }
    static var displayName: String { get }
    static var fileExtension: String { get }
    static var mimeType: String { get }
    func export(for userID: UUID, on db: Database) async throws -> Data
}

struct ImportResult {
    let imported: Int
    let updated: Int
    let skipped: Int
    let errors: [String]
}
```

### 11.2 Anybox JSON Importer (`identifier: "anybox"`)

Anybox exports a JSON array. Relevant fields:

```json
[
  {
    "url": "https://example.com",
    "title": "Example",
    "description": "Optional",
    "tags": ["swift", "ios"],
    "folder": ["Development"],
    "date_added": 1756535446
  }
]
```

Mapping rules:
- `url` → required; skip record if missing or invalid
- `title` → `Bookmark.title` (empty string if missing)
- `description` → `Bookmark.description`
- `tags` → `Bookmark.tags` (normalised)
- `folder` → ignored (flat import, folders not mapped to tags)
- `date_added` → `Bookmark.createdAt` (Unix timestamp; current time if missing)
- All other fields ignored

**Duplicate URL:** update existing bookmark — overwrite title, description, tags. Do not change `createdAt`.

### 11.3 Stash JSON Importer (`identifier: "stash-json"`)

Imports a previously exported Stash JSON file. Useful for migrating between Stash instances.

Mapping rules:
- `bookmarks[].url` → required; skip record if missing or invalid
- `bookmarks[].title` → `Bookmark.title`
- `bookmarks[].description` → `Bookmark.description`
- `bookmarks[].tags` → `Bookmark.tags` (normalised)
- `bookmarks[].isArchived` → `Bookmark.isArchived`
- `bookmarks[].faviconURL` → `Bookmark.faviconURL`
- `bookmarks[].createdAt` → `Bookmark.createdAt` (ISO 8601; current time if missing or unparseable)
- Top-level `version`, `exportedAt`, and per-bookmark `id`/`updatedAt` → ignored

**Duplicate URL:** update existing bookmark — overwrite title, description, tags, isArchived, faviconURL. Do not change `createdAt` on update.

### 11.4 Stash JSON Exporter (`identifier: "stash-json"`)

Exports all bookmarks (including archived) for the authenticated user, sorted by `createdAt` ascending:

```json
{
  "version": "1",
  "exportedAt": "2026-06-09T12:00:00Z",
  "bookmarks": [
    {
      "id": "uuid",
      "url": "https://example.com",
      "title": "Example",
      "description": "...",
      "tags": ["swift", "ios"],
      "faviconURL": "https://example.com/favicon.ico",
      "isArchived": false,
      "createdAt": "2026-01-01T00:00:00Z",
      "updatedAt": "2026-01-02T00:00:00Z"
    }
  ]
}
```

Returned as a file download: `Content-Disposition: attachment; filename="stash-export-{date}.json"`.

---

## 12. Web Admin Dashboard (`/admin`)

Server-rendered with Leaf. Session-based authentication (`stash_admin_session` cookie, in-memory store). Only active admin accounts can log in.

### Pages

| Page | Path |
|------|------|
| Login | `/admin/login` |
| Dashboard | `/admin` |
| User List | `/admin/users` |
| Create User | `/admin/users/new` |
| User Detail | `/admin/users/:id` |

### Business Rules

- All accounts created via the dashboard are always `user` role
- Admin cannot delete their own account (button hidden + POST blocked with 400)
- Suspend and password reset both invalidate all refresh tokens for the target user
- 2FA reset: clears TOTP secret, deletes recovery codes, invalidates all refresh tokens
- Post/Redirect/Get pattern with `?ok=…` confirmation banners
- Sessions are in-memory — a container restart logs out active admin sessions (by design)

---

## 13. Web Frontend (`/app`)

Server-rendered with Leaf. Session-based authentication (`stash_session` cookie, in-memory store, path `/app`). Any active user role can log in.

### Pages

| Page | Path |
|------|------|
| Login | `/app/login` |
| Bookmark List | `/app` |
| Add Bookmark | `/app/bookmarks/new` |
| Bookmark Detail | `/app/bookmarks/:id` |
| Edit Bookmark | `/app/bookmarks/:id/edit` |
| Tag Browser | `/app/tags` |
| Settings | `/app/settings` |
| Import & Export | `/app/settings` (section) |

### Features

- Search (`?q=`), tag filter (`?tag=`), archived toggle, pagination with prev/next links preserving filters
- Add form: two-step flow — "Fetch metadata" previews title/description server-side, "Save" persists
- Duplicate URL: inline error with link to existing bookmark
- Archive/unarchive toggle per bookmark
- Tag autocomplete on add and edit forms: vanilla JS (~60 lines), dependency-free, splits on commas, prefix-matches against the user's existing tag list fetched at page load
- Hierarchical tags displayed as `swift › vapor`, stored as `swift/vapor`
- 2FA enrolment: shows `otpauth://` URI + manual setup key (no QR image — CoreImage unavailable on Linux); recovery codes shown once with "I've saved these" confirmation
- 2FA disable: requires current TOTP code
- Import: file upload, format selector (Anybox JSON, Stash JSON), summary banner with imported/updated/skipped counts, collapsible error details
- Export: "Download your bookmarks" → Stash JSON file download
- Danger Zone: "Delete all bookmarks" requires typing `delete all` (case-insensitive) to confirm; verified server-side; resets `bookmarkCount` to 0

---

## 14. CLI — `stash` (Planned — M7)

Swift CLI built with `ArgumentParser`. No external dependencies beyond `StashKit`.  
Configuration stored in `~/.config/stash/config.json`.

### Auth Commands

```
stash login
stash logout
```

### Bookmark Commands

```
stash add <url> [--title "..."] [--description "..."] [--tag <tag>] [--no-fetch] [--json]
stash list [--tag <tag>] [--search "..."] [--archived] [--page <n>] [--json]
stash get <id> [--json]
stash delete <id>
stash archive <id>
stash tags [--json]
stash import <file> [--format anybox]
stash export [--format stash-json] [--output <path>]
```

### Admin Commands (admin accounts only)

```
stash admin users [--json]
stash admin create-user --username <u> --password <p>
stash admin suspend-user <username>
stash admin unsuspend-user <username>
stash admin reset-password <username> --password <newpassword>
stash admin reset-totp <username>
stash admin delete-user <username>
stash admin stats [--json]
```

---

## 15. StashKit — Shared Swift Package (Planned — M6)

No external dependencies. Uses only `Foundation` and `URLSession`.

### Tag Autocomplete Strategy

Tags fetched once per session via `GET /api/v1/tags`, cached in memory. `autocompleteTags(prefix:)` is synchronous, local. Cache invalidated after any bookmark mutation that modifies tags.

---

## 16. iOS + macOS App (Planned — M8–M10)

Single multiplatform SwiftUI target.

**Minimum OS versions:** iOS 17.0, macOS 14.0 (Sonoma)  
**Bundle ID prefix:** `cc.otavio.stash`  
**App Group:** `group.cc.otavio.stash` (shared Keychain for Share Extension)

### iOS Screens

Login → TOTP Entry → Recovery Code Entry → 2FA Setup → Bookmark List → Add Bookmark → Bookmark Detail → Tag Browser → Archived → Settings

### Share Extension

- Shared Keychain access via App Group
- Compact Add Bookmark sheet
- Auto-fetches metadata; user can edit before saving
- Duplicate URL: shows existing bookmark title + "View existing" option

---

## 17. Deployment

### Distribution Model

Distributed as a ready-to-run Docker image at `ghcr.io/otaviocc/stash`. Users run a single `docker-compose.yml` — no build step required.

### Docker Image

- **Build base:** `swift:6.1-jammy` (compilation), `ubuntu:22.04` (runtime)
- **Platforms:** `linux/amd64` and `linux/arm64`
- **Registry:** `ghcr.io/otaviocc/stash`
- **Tags:** `latest`, semver (e.g. `1.0.0`, `1.0`)

### Canonical `docker-compose.yml`

```yaml
services:
  app:
    image: ghcr.io/otaviocc/stash:latest
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=postgres://stash:${DB_PASSWORD}@db:5432/stash
      - JWT_SECRET=${JWT_SECRET}
      - ADMIN_USERNAME=${ADMIN_USERNAME}
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
    depends_on:
      - db
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    volumes:
      - stash_db:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=stash
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=stash
    restart: unless-stopped

volumes:
  stash_db:
```

### First Boot — Admin Seeding

On first run, if no user exists, reads `ADMIN_USERNAME` and `ADMIN_PASSWORD` from env vars and creates the admin account. Missing/invalid credentials with an empty DB → logs critical error and exits. Subsequent boots: silent no-op.

### Local Network Usage

Primary use case: deployment on a home server or NAS at `http://192.168.1.x:8080`. iOS/macOS apps require an ATS exception for arbitrary HTTP loads (`NSAllowsArbitraryLoads: true`). Sessions are in-memory — a container restart logs out active web sessions.

### Reverse Proxy (optional, for external access)

```
stash.yourdomain.com {
    reverse_proxy localhost:8080
}
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `DB_PASSWORD` | PostgreSQL password |
| `JWT_SECRET` | JWT signing secret (min 32 chars, random) |
| `ADMIN_USERNAME` | Admin username (first boot only) |
| `ADMIN_PASSWORD` | Admin password (first boot only, min 12 chars) |

### CI/CD (Planned — M4.1)

GitHub Actions on version tag push: build multi-arch image → push to `ghcr.io/otaviocc/stash` → attach `docker-compose.yml` as release artifact.

---

## 18. Technical Specification

### 18.1 Repository Structure

```
stash/
├── Backend/                        # Vapor 4 REST API
│   ├── Sources/App/
│   │   ├── Controllers/
│   │   ├── Models/
│   │   ├── Migrations/
│   │   ├── Middleware/
│   │   ├── ImportExport/           # Importers, exporters, registry
│   │   └── configure.swift
│   ├── Tests/AppTests/
│   ├── Resources/Views/            # Leaf templates
│   ├── Package.swift
│   ├── Dockerfile
│   └── docker-compose.yml
│
├── StashKit/                       # Shared Swift package (planned)
│   ├── Sources/StashKit/
│   └── Package.swift
│
├── StashApp/                       # Xcode project — iOS + macOS (planned)
│   ├── Shared/
│   ├── iOS/
│   ├── macOS/
│   └── ShareExtension/
│
├── stash-cli/                      # Swift CLI tool (planned)
│   ├── Sources/stash/
│   └── Package.swift
│
├── .github/workflows/
│   └── release.yml                 # Planned (M4.1)
│
└── README.md
```

### 18.2 Swift Package Dependencies

#### Backend (`Backend/Package.swift`)

| Package | Purpose |
|---------|---------|
| `vapor/vapor` `from: "4.0.0"` | Web framework |
| `vapor/fluent` `from: "4.0.0"` | ORM |
| `vapor/fluent-postgres-driver` `from: "2.0.0"` | PostgreSQL driver |
| `vapor/jwt` `from: "4.0.0"` | JWT signing + verification |
| `vapor/leaf` `from: "4.0.0"` | Server-rendered HTML |
| `vapor/authentication` `from: "2.0.0"` | TOTP/HOTP + password auth |

No third-party TOTP library — `vapor/authentication` includes RFC-compliant TOTP built in.

#### CLI (`stash-cli/Package.swift`)

| Package | Purpose |
|---------|---------|
| `apple/swift-argument-parser` `from: "1.0.0"` | Argument parsing |

### 18.3 API Versioning

All API routes: `/api/v1/`. Web dashboard: `/admin`. Web frontend: `/app`. Health check: `/health`.

### 18.4 Error Response Format

```json
{
  "error": true,
  "code": "error_code_snake_case",
  "message": "Human-readable description."
}
```

| Code | Status | Description |
|------|--------|-------------|
| `invalid_credentials` | 401 | Wrong username or password |
| `account_suspended` | 401 | Account is inactive |
| `token_expired` | 401 | Access token has expired |
| `token_invalid` | 401 | Malformed or unrecognised token |
| `totp_required` | 401 | Login requires TOTP |
| `totp_invalid` | 401 | Wrong TOTP or recovery code |
| `forbidden` | 403 | Insufficient role |
| `not_found` | 404 | Resource does not exist |
| `duplicate_url` | 409 | URL already saved by this user |
| `username_taken` | 409 | Username already exists |
| `cannot_delete_self` | 400 | Admin attempting to delete their own account |
| `validation_failed` | 422 | One or more fields failed validation |
| `internal_error` | 500 | Unexpected server error |

Duplicate URL (409) also includes `"existingID": "<uuid>"`.

### 18.5 Pagination Response Envelope

Vapor's native `Page<T>`:

```json
{
  "items": [],
  "metadata": { "page": 1, "per": 20, "total": 142 }
}
```

### 18.6 Xcode Project (Planned)

- Single multiplatform SwiftUI target
- iOS 17.0 / macOS 14.0 minimum
- Bundle IDs: `cc.otavio.stash` (app), `cc.otavio.stash.ShareExtension`
- App Group: `group.cc.otavio.stash`
- Refresh token in Keychain (shared group); access token in memory only
- `NSAllowsArbitraryLoads: true` in `Info.plist`

### 18.7 Testing Expectations

Backend tests use `VaporTesting` against in-memory SQLite.

| Layer | Coverage |
|-------|---------|
| Auth controller | Login, TOTP, recovery codes, refresh rotation, logout, 2FA disable |
| Bookmark controller | CRUD, duplicate 409, tag filtering, full-text search, pagination, user isolation |
| Admin controller | Create, suspend/unsuspend, reset password, reset TOTP, delete, stats, self-delete guard |
| Middleware | 401 unauthenticated, 403 non-admin |
| Error format | Standard envelope on all errors |
| Admin seeding | Seeds on empty DB, skips if user exists, exits on missing creds |

Leaf templates: not tested. StashKit: mock URLSession tests. CLI: manual integration testing only.

---

## 19. Development Milestones

| Milestone | Deliverable | Status |
|-----------|-------------|--------|
| M1 | Backend: auth, JWT, TOTP, recovery codes | ✅ Complete |
| M2 | Backend: bookmark CRUD, tags, metadata fetching | ✅ Complete |
| M3 | Backend: admin user management API | ✅ Complete |
| M4 | Backend: Docker image, docker-compose, first-boot seeding | ✅ Complete |
| M5 | Web admin dashboard (Leaf) | ✅ Complete |
| M11 | Web frontend (`/app`): full CRUD, tag browser, 2FA, import/export (Anybox + Stash JSON), danger zone | ✅ Complete |
| M6 | StashKit: models + APIClient | Planned |
| M7 | CLI: all commands including import/export | Planned |
| M8 | iOS app | Planned |
| M9 | iOS Share Extension | Planned |
| M10 | macOS app + Share Extension | Planned |
| M4.1 | CI/CD: GitHub Actions, publish to ghcr.io | Planned (after M10) |

---

## 20. Implementation Decisions Log

| Decision | Rationale |
|----------|-----------|
| `swift:6.1-jammy` Docker base (not 5.10) | Latest Vapor/Fluent packages require Swift tools version 6.0+ |
| `tagsSearch` derived column for tag prefix matching | Portable across SQLite (tests) and PostgreSQL (production) without DB-specific functions |
| Full-text search uses `ILIKE` on PostgreSQL | Case-insensitive; SQLite tests use `LIKE` (case-sensitive — acceptable in test environment) |
| Tags lowercased on write | Prevents fragmented tag tree (`Swift` vs `swift`); matches all examples in the PRD |
| In-memory sessions for web frontend | Single self-hosted instance; DB/Redis store can be added later if needed |
| No QR code in web 2FA setup | CoreImage unavailable on Linux; `otpauth://` URI + manual key is fully functional |
| Anybox folder field ignored on import | Flat import as decided; hierarchical tag mapping can be added as a future importer option |
| Stash JSON importer uses same update-on-duplicate behaviour as Anybox | Consistent behaviour across all importers |
| Danger zone confirmation verified server-side (not just client-side JS) | Client check is convenience only; server is authoritative |
| Admin password reset invalidates tokens | Treats forced reset as potential account compromise response |
| `POST` sub-routes for web actions (delete, archive, etc.) | HTML forms cannot send PUT/DELETE; Post/Redirect/Get pattern used throughout |

---

## 21. Out of Scope

- Open/public registration
- Cross-user bookmark visibility or sharing
- Page archiving or offline reading
- Browser extension
- Read-later queue or unread state
- Annotations or highlights
- SSO / OAuth
- Menu bar app (macOS)
