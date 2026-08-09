# Stash PRD: Technical Spec, Milestones, Leaf Gotchas & Out of Scope (§19\u201322)

_Part of the Stash Product Requirements Document. See [`PRODUCT.md`](../PRODUCT.md) for the index._

---

## 19. Technical Specification

### 19.1 Repository Structure

```
stash/
├── Backend/                      # ✅ Complete: Vapor 4 REST API + Leaf web UIs
│   ├── Sources/App/
│   │   ├── API/                  # the /api/v1 JSON contract clients depend on
│   │   │   ├── Controllers/
│   │   │   └── DTOs/
│   │   ├── Web/                  # the Leaf /admin + /app + landing UIs
│   │   │   ├── Controllers/      # one RouteCollection per domain
│   │   │   ├── DTOs/
│   │   │   ├── Presenters/       # pure Leaf-context shaping, no request/DB
│   │   │   └── Support/          # cross-controller glue (FlashMessage, etc.)
│   │   ├── Core/                 # shared domain, used by both API and Web
│   │   │   ├── Models/
│   │   │   ├── Migrations/
│   │   │   ├── Services/
│   │   │   ├── Auth/
│   │   │   ├── ImportExport/
│   │   │   ├── Extensions/
│   │   │   ├── Middleware/
│   │   │   ├── Errors/
│   │   │   └── Support/          # stateless helpers
│   │   ├── configure.swift
│   │   └── routes.swift
│   ├── Tests/AppTests/
│   ├── Resources/Views/          # Leaf templates (markup only; CSS/JS live in Public/)
│   ├── Public/                   # served by FileMiddleware; also openapi.yaml
│   │   ├── css/
│   │   ├── js/
│   │   └── openapi.yaml          # machine-readable /api/v1 + /health contract
│   ├── Package.swift
│   ├── Dockerfile
│   └── docker-compose.yml
├── StashKit/                     # ✅ Complete (M6): shared Swift package
│   ├── Sources/StashKit/
│   │   ├── Client/
│   │   ├── DTOs/
│   │   ├── Factories/
│   │   └── Requests/
│   └── Tests/StashKitTests/
├── StashApp/                     # ✅ Complete (M8–M10)
│   ├── Common/                   # compiled into the app + both Share Extensions
│   ├── Stash/                    # app-only code (iOS + macOS); @main entry
│   ├── StashShareExtension/      # both Share Extensions (#if-guarded controllers)
│   ├── Config/                   # non-synced per-platform Info.plist + entitlements
│   └── Stash.xcodeproj           # committed; synchronized folder groups
├── CLI/                          # ✅ Complete (M7)
│   ├── Sources/stash/
│   └── Package.swift
├── Extension/                    # ✅ Complete: Manifest v3 WebExtension, no build step
│   ├── background.js             # single owner of token storage + silent refresh
│   ├── popup.js / options.js
│   └── icons/
├── StashSkill/                   # committed AI coding assistant skill for the CLI
├── Script/                       # repo-wide maintenance scripts (e.g. bump-version.sh)
├── Docs/                         # user-facing docs, one guide per concern
├── .github/workflows/            # CI: backend, apple, extension jobs
├── PRODUCT.md
└── DECISIONS.md
```

### 19.2 Swift Package Dependencies

#### Backend

| Package | Purpose |
|---------|---------|
| `vapor/vapor` `from: "4.0.0"` | Web framework |
| `vapor/fluent` `from: "4.0.0"` | ORM |
| `vapor/fluent-postgres-driver` `from: "2.0.0"` | PostgreSQL (production) |
| `vapor/fluent-sqlite-driver` | SQLite (tests only) |
| `vapor/jwt` `from: "4.0.0"` | JWT |
| `vapor/leaf` `from: "4.0.0"` | Server-rendered HTML |
| `vapor/authentication` `from: "2.0.0"` | Auth helpers (TOTP implemented natively via `swift-crypto`) |

#### StashKit

| Package | Purpose |
|---------|---------|
| `otaviocc/MicroClient` `from: "0.0.27"` | Typed HTTP client |

#### CLI

| Package | Purpose |
|---------|---------|
| `apple/swift-argument-parser` `from: "1.5.0"` | Argument parsing |
| `otaviocc/MicroClient` `from: "0.0.27"` | Direct dep for 2FA login branch |

#### iOS App

| Dependency | Purpose |
|-----------|---------|
| `StashKit` (local) | Networking |
| `otaviocc/MicroClient` `from: "0.0.27"` | Direct dep for 2FA login branch |

### 19.3 API Versioning

API: `/api/v1/`. Admin dashboard: `/admin`. Frontend: `/app`. Health: `/health`.

### 19.4 Error Response Format

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
| `token_expired` | 401 | Access token expired |
| `token_invalid` | 401 | Malformed or unrecognized token |
| `totp_required` | 401 | Login requires TOTP |
| `totp_invalid` | 401 | Wrong TOTP or recovery code |
| `forbidden` | 403 | Insufficient role |
| `not_found` | 404 | Resource not found |
| `duplicate_url` | 409 | URL already saved (includes `existingID`) |
| `username_taken` | 409 | Username already exists |
| `cannot_delete_self` | 400 | Admin attempting to delete own account |
| `cannot_suspend_self` | 400 | Admin attempting to suspend own account |
| `validation_failed` | 422 | Validation error |
| `internal_error` | 500 | Unexpected server error |

### 19.5 Pagination

Vapor's native `Page<T>`:
```json
{ "items": [], "metadata": { "page": 1, "per": 20, "total": 142 } }
```

### 19.6 Testing

Backend: `VaporTesting` + swift-testing, in-memory SQLite. Leaf templates:
throwaway smoke tests (run then removed). StashKit: mock `URLSessionProtocol`.
iOS app: no unit tests. CLI: manual integration only.

**Required backend coverage:**

| Layer | Coverage |
|-------|---------|
| Auth | Login, TOTP, recovery codes, refresh rotation, logout, 2FA enroll/disable |
| Bookmarks | CRUD, 409, tag filtering, `__untagged__`, full-text search (case-insensitive), pagination, user isolation |
| Admin | Create, suspend, reset password, reset TOTP, delete, stats, self-delete guard |
| Tags | Rename (with children, merge), delete (with children), user isolation |
| Middleware | 401 unauthenticated, 403 non-admin |
| Admin seeding | Seeds, skips, exits on bad creds |

### 19.7 Code Style

SwiftLint + SwiftFormat. `swiftlint lint` 0 violations, `swiftformat --lint`
idempotent. Applied to Backend, StashKit, CLI, and iOS app.

- Organization: type mode (`Nested Types → Static Properties → Properties →
  Computed Properties → Lifecycle → Functions`), public-before-private within
  sections
- `///` doc comments on declarations (types, properties, methods/functions);
  no comments of any kind inside method/function bodies
- American English throughout
- Tests: Given/When/Then structure, `#expect` with `"It should ..."`
  descriptions
- Blank line after `guard`; blank line before control flow and `return` in
  multi-statement bodies (manual convention)

---

## 20. Development Milestones

| Milestone | Deliverable | Status |
|-----------|-------------|--------|
| M1 | Backend: auth, JWT, TOTP, recovery codes | ✅ Complete |
| M2 | Backend: bookmark CRUD, tags, metadata fetching | ✅ Complete |
| M3 | Backend: admin user management API | ✅ Complete |
| M4 | Backend: Docker image, docker-compose, first-boot seeding | ✅ Complete |
| M5 | Web admin dashboard (Leaf) | ✅ Complete |
| M11 | Web frontend: full CRUD, tag sidebar, tag browser, dark mode, import/export, danger zone | ✅ Complete |
| M6 | StashKit: DTOs, request factories, thin client | ✅ Complete |
| M7 | CLI: all commands including import/export, tag rename/delete | ✅ Complete |
| M8 | iOS app: auth, bookmark list, add bookmark | ✅ Core complete |
| M9 | iOS Share Extension | ✅ Complete |
| M10 | macOS app + Share Extension | ✅ Complete |
| M4.1 | CI/CD: GitHub Actions, publish to ghcr.io | ✅ Complete |
| M12 | Smart Views: saved AND-condition queries (backend, StashKit, web UI) | ✅ Complete |
| M12.1 | Smart Views on the CLI and native apps (consumption-only: list + run) | ✅ Complete |
| M12.2 | Smart View create / edit / delete in the iOS & macOS apps (Settings) | ✅ Complete |
| M13 | Offline sync (iOS & macOS): SwiftData local store, `SyncEngine` (pull/push, last-write-wins), optimistic writes, connectivity + background refresh, sync-status UI | ✅ Complete |
| M14 | Native tag picker (iOS & macOS): `TagPickerSheet` with always-expanded indented tag tree, single-tap toggle, search-as-create; flat-indented (web-parity) tag trees; drag-a-bookmark-onto-a-tag tagging (iPad & macOS); `swift › server` tag pills; native Share… via `ShareLink` | ✅ Complete |

This table stopped being updated after M14; later features (Internet Archive
submission, audit log, active sessions, system logs, favicon cache management,
instance backup/restore, the update checker, editable footer links, Read
Later) are tracked in `DECISIONS.md` instead, each under its own dated entry.

---

## 21. Known Leaf Gotchas

A few quirks that cost me real debugging time and are worth writing down so I
don't relearn them the hard way:

- `#if(count(x))` does **not** coerce `Int` to `Bool`; `count 0` evaluates
  truthy. Always use `#if(count(x) > 0)`.
- Inline conditionals require the colon: `#if(cond): … #endif`.
- `#if(cond):#else: X #endif` with an empty then-branch misbehaves (else content
  dropped). Use positive single-branch tests.
- A non-optional `String` field set to `""` makes `#if(field)` evaluate
  **true**. Use `#if(field != "")` or `#if(field == "")` explicitly.

---

## 22. Out of Scope

Deliberately not building, at least for v1:

- Open/public registration
- Cross-user bookmark visibility or sharing
- Page content archiving (article text for offline reading); the native apps do
  sync bookmark data for offline access; saving page contents is out of scope
- Annotations or highlights
- SSO / OAuth
- Menu bar app (macOS)
