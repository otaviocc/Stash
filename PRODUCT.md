# Stash — Product Requirements Document

**Version:** 1.7
**Status:** Living Document
**Author:** Otávio

---

## 1. Overview

Stash is a self-hosted, fully private bookmark manager. It is multi-user:
accounts are created by an admin, and each user manages their own private
collection of bookmarks. It consists of a Swift/Vapor REST API backend backed by
PostgreSQL, deployable via Docker, with native clients for iOS, macOS, and the
command line. A shared Swift package (`StashKit`) provides models and networking
logic across all clients.

The core philosophy: **full data ownership, self-hosted, no third-party cloud.**

---

## 2. Goals

- Save bookmarks quickly from any Apple platform via Share Extensions or the CLI
- Retrieve bookmarks reliably via keyword search, tag browsing, or recency
- Organise bookmarks with both flat and hierarchical tags
- Rename and delete tags across all bookmarks in bulk
- Save named queries as Smart Views that filter bookmarks by a set of AND conditions
- Auto-fetch page metadata (title, description, favicon) at save time, with
  manual override
- Support multiple users, each with a fully isolated bookmark collection
- Admin can create, suspend, and hard-delete accounts, reset passwords and 2FA —
  via web dashboard and CLI
- Users authenticate with username + password + TOTP-based 2FA, with recovery
  codes
- Users can enable, disable, and manage their own 2FA
- Users can change their own password
- Duplicate URLs per user are blocked at save time
- Import bookmarks from Anybox JSON export and Stash JSON
- Export bookmarks in Stash native JSON format
- Dark mode support (Light / Dark / Auto)
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

There is exactly one admin. The admin account is seeded at first boot via
environment variables — there is no public sign-up flow.

---

## 5. Platforms

| Platform | Type | Status |
|----------|------|--------|
| Backend | Vapor 4 REST API | ✅ Complete |
| Web admin dashboard | Server-rendered (Leaf) | ✅ Complete |
| Web frontend (user-facing) | Server-rendered (Leaf) | ✅ Complete |
| CLI (`stash`) | Swift CLI tool | ✅ Complete |
| iOS | Native SwiftUI app + Share Extension | ✅ Complete (M8 + M9) |
| macOS | Native SwiftUI app + Share Extension | ✅ Complete (M10) |

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
│  TagRenamer / TagDeleter (shared business logic)      │
└──────────────────────────┬────────────────────────────┘
                           │
                           ▼
┌───────────────────────────────────────────────────────┐
│                  PostgreSQL 16                        │
└───────────────────────────────────────────────────────┘

StashKit (Swift Package) — ✅ Complete (M6)
  └── Shared by: iOS app, macOS app, CLI
  └── DTOs, request factories, thin StashClient
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
| `title` | String | Auto-fetched, overridable. Falls back to URL if blank. |
| `description` | String? | Auto-fetched, overridable |
| `faviconURL` | String? | Auto-fetched |
| `tags` | [String] | Flat or hierarchical (e.g. `swift/vapor`). JSON column. |
| `tagsSearch` | String | Derived: `\|swift\|swift/vapor\|` for portable LIKE queries |
| `isArchived` | Bool | Default false |
| `createdAt` | Date | Auto-set |
| `updatedAt` | Date | Auto-updated |

**Duplicate URL constraint:** unique index on `(userID, url)`. API returns HTTP
409 Conflict if a duplicate is attempted.

### 7.3 Refresh Token

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `userID` | UUID | Foreign key → User |
| `tokenHash` | String | SHA-256 hash of the raw token |
| `expiresAt` | Date | 90 days from issuance |
| `createdAt` | Date | Auto-set |

Rotated on every use. Deleted on logout, suspension, hard deletion, password
reset (admin), and 2FA disable/reset.

### 7.4 Recovery Code

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `userID` | UUID | Foreign key → User |
| `codeHash` | String | Bcrypt hash of the raw code |
| `usedAt` | Date? | Null until redeemed; single-use |

Eight codes generated at 2FA enrolment. Deleted when 2FA is disabled or reset.

### 7.5 Tags

Tags are plain strings stored on each bookmark. Hierarchical tags use slash
notation: `swift/vapor`. The tag tree is derived dynamically per user — no
separate tag table.

A derived `tagsSearch` column stores tags as `|swift|swift/vapor|` for portable
prefix-matching via SQL `LIKE`. Consistent across SQLite (tests) and PostgreSQL
(production).

Querying `tag=swift` matches bookmarks where `tagsSearch` contains `|swift` —
prefix match: includes `swift` and `swift/*`, but not `swiftui`.

**Tag normalisation:** trimmed, lowercased, surrounding slashes stripped,
de-duplicated. Enforced server-side on every write.

### 7.6 Site Settings

Instance-wide customisation, managed by the admin. A single-row configuration
table — always exactly one row, created on first boot with default values, never
deleted. Cached on the application at startup so page renders never hit the
database.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `accentTheme` | String | Default `"ocean"`. One of the nine theme identifiers. |
| `aboutText` | String? | Optional. Short message shown in the footer. Max 280 chars. |
| `footerCustomLabel` | String? | Display label for the admin's custom footer link. |
| `footerCustomURL` | String? | URL for the custom footer link. Must be `https://`. |
| `createdAt` | Date | Auto-set |
| `updatedAt` | Date | Auto-updated |

**Accent themes.** Nine named themes, each with a light-mode and a dark-mode hex
value; the active value is selected automatically from the `data-theme`
attribute. `ocean` is the default and matches the app's original accent.

| Identifier | Name | Light | Dark |
|------------|------|-------|------|
| `ocean` | Ocean | `#0a84ff` | `#409cff` |
| `sunny` | Sunny | `#f59e0b` | `#fbbf24` |
| `forest` | Forest | `#16a34a` | `#4ade80` |
| `ember` | Ember | `#dc2626` | `#f87171` |
| `aurora` | Aurora | `#7c3aed` | `#a78bfa` |
| `arctic` | Arctic | `#0891b2` | `#22d3ee` |
| `rose` | Rose | `#be185d` | `#f472b6` |
| `dusk` | Dusk | `#b45309` | `#d97706` |
| `slate` | Slate | `#475569` | `#94a3b8` |

The selected theme's values are injected into `layout.leaf`'s `<head>` as a CSS
block overriding `--accent`, from the app-level cache (no per-request query).

### 7.7 Smart View

A named, saved query owned by a user. Stores rules, not results — each time it is
opened the query runs live against the user's bookmarks. All conditions are ANDed:
a bookmark must match every condition to appear.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `userID` | UUID | Foreign key → User; all queries scoped to this |
| `name` | String | Display name. Required, max 100 chars. |
| `conditions` | [SmartViewCondition] | JSON column. At least one required. |
| `createdAt` | Date | Auto-set |
| `updatedAt` | Date | Auto-updated |

Each condition is a `{ type, value }` object (all values strings; dates ISO-8601,
`isArchived` is `"true"`/`"false"`). Supported types:

| Type | Meaning |
|------|---------|
| `tag` | `tagsSearch` contains `\|<value>` (prefix match, same as the tag filter) |
| `urlContains` | `url` contains `value` (case-insensitive) |
| `titleContains` | `title` contains `value` (case-insensitive) |
| `descriptionContains` | `description` contains `value` (case-insensitive) |
| `createdBefore` | `createdAt` is before the ISO-8601 date |
| `createdAfter` | `createdAt` is after the ISO-8601 date |
| `isArchived` | `isArchived` equals `true`/`false` |

Text conditions use the same portable `lower(column) LIKE lower('%value%')` helper
as full-text search. Multiple conditions of the same type are allowed (two `tag`
conditions = the bookmark must have both tags).

**Footer.** Shown on every `/app` and `/admin` page via `layout.leaf`. Fixed,
non-configurable content: a Mastodon link (`https://social.lol/@otaviocc`), a
Ko-fi link (`https://ko-fi.com/otaviocc`), and the version string (read from a
`VERSION` file at startup, `"dev"` if missing). Configurable content: the
optional `aboutText` (shown above the links) and one optional custom link
(`footerCustomLabel` + `footerCustomURL`, shown only when both are non-empty).
All external links open in a new tab with `rel="noopener noreferrer"`. The Stash
identity (name, logo, Ko-fi and Mastodon links) is hardcoded and not
configurable.

---

## 8. Authentication & Security

### 8.1 Token Strategy

| Token | Lifetime | Storage (client) |
|-------|----------|-----------------|
| Access token (JWT, HS256) | 15 minutes | Keychain (iOS/macOS), memory (CLI, web) |
| Refresh token (opaque 256-bit hex) | 90 days, rotated on use | Keychain (iOS/macOS), file (CLI), session (web) |

Silent refresh within 60 seconds of expiry. The 2FA temp token uses `scope:
"2fa"` so it cannot be replayed as an access token.

Note: both tokens are stored in Keychain on iOS/macOS (deviation from the
original memory-only access token spec) to enable cold-start session restoration
and Share Extension token reuse.

### 8.2 Login Flow

```
POST /api/v1/auth/login  { username, password }
→ 2FA disabled: { accessToken, refreshToken }
→ 2FA enabled:  { requires2FA: true, tempToken }

POST /api/v1/auth/totp   { tempToken, totpCode }
→ { accessToken, refreshToken }

POST /api/v1/auth/recovery  { tempToken, recoveryCode }
→ { accessToken, refreshToken }  (code marked used)

POST /api/v1/auth/refresh { refreshToken }
→ { accessToken, refreshToken }  (old token deleted)

POST /api/v1/auth/logout  { refreshToken }
→ 204 No Content
```

### 8.3 2FA Enrolment

```
GET  /api/v1/auth/totp/setup
→ { secret, otpauthURI }

POST /api/v1/auth/totp/verify-setup  { totpCode }
→ { recoveryCodes: [...] }  (8 codes, shown once)
```

Recovery codes: 8 × `XXXX-XXXX`, bcrypt-hashed, single-use. Shown exactly once
with mandatory "I've saved these" confirmation.

Web UI shows `otpauthURI` + manual setup key — no QR image (CoreImage
unavailable on Linux). Native clients display a QR code from `otpauthURI`.

### 8.4 2FA Disable / Reset

**User self-service (`POST /api/v1/auth/totp/disable`):** requires current TOTP
code. Clears `totpSecret`, sets `isTOTPEnabled = false`, deletes recovery codes,
invalidates all refresh tokens.

**Admin reset (`POST /api/v1/admin/users/:id/reset-totp`):** no confirmation
code required. Same effect. Self-reset allowed. Invalidates refresh tokens.

### 8.5 Password Rules

Minimum 12 characters. Bcrypt, cost factor 12. Unknown usernames run a throwaway
bcrypt verify to prevent timing-based account enumeration.

### 8.6 Token Invalidation Rules

All refresh tokens for a user are deleted when:
- Account suspended
- Password reset by admin
- Account hard-deleted
- 2FA disabled (self-service or admin reset)

---

## 9. API Specification

All API routes prefixed `/api/v1/`. Health check at `/health` (unversioned).

### 9.1 Auth (unauthenticated)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/auth/login` | Username + password |
| `POST` | `/api/v1/auth/totp` | TOTP code after login |
| `POST` | `/api/v1/auth/recovery` | Recovery code after login |
| `POST` | `/api/v1/auth/refresh` | Rotate refresh token |
| `POST` | `/api/v1/auth/logout` | Invalidate refresh token |

### 9.2 User (authenticated, any role)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/me` | Current user profile |
| `PUT` | `/api/v1/me/password` | Change own password |
| `GET` | `/api/v1/auth/totp/setup` | Begin 2FA enrolment |
| `POST` | `/api/v1/auth/totp/verify-setup` | Confirm enrolment; returns recovery codes |
| `POST` | `/api/v1/auth/totp/disable` | Disable own 2FA (requires current TOTP code) |

### 9.3 Bookmarks (authenticated, scoped to current user)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/bookmarks` | List bookmarks |
| `POST` | `/api/v1/bookmarks` | Create bookmark (409 if URL exists) |
| `GET` | `/api/v1/bookmarks/:id` | Get bookmark |
| `PUT` | `/api/v1/bookmarks/:id` | Update bookmark |
| `DELETE` | `/api/v1/bookmarks/:id` | Delete bookmark |

**`GET /api/v1/bookmarks` query parameters:**

| Parameter | Description |
|-----------|-------------|
| `q` | Full-text search (URL, title, description, tags). Case-insensitive on both SQLite and PostgreSQL via `lower(column) LIKE lower(term)`. |
| `tag` | Prefix filter. `swift` matches `swift` and `swift/*` but not `swiftui`. Special value `__untagged__` returns bookmarks with no tags. |
| `archived` | Default false. Pass `true` for archived bookmarks. |
| `page` / `per` | Pagination. `per` clamped 1–100. |

### 9.4 Tags (authenticated, scoped to current user)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/tags` | All tags with counts |
| `POST` | `/api/v1/tags/rename` | Rename a tag (and its children) |
| `DELETE` | `/api/v1/tags/:tag` | Delete a tag (and its children) |

**`POST /api/v1/tags/rename` body:**
```json
{ "from": "foo-bar", "to": "foobar" }
```
Response: `{ "from": "foo-bar", "to": "foobar", "affectedBookmarks": 12 }`

- Renames exact tag and all children (`foo-bar/x` → `foobar/x`)
- If `to` already exists: merge silently (de-duplicate)
- `from == to` or unused `from`: idempotent 200, `affectedBookmarks: 0`

**`DELETE /api/v1/tags/:tag`:** Response: `{ "tag": "foo-bar",
"affectedBookmarks": 12 }`

- Removes exact tag and all children from all affected bookmarks
- Bookmarks are never deleted — only their tags
- Unused tag: idempotent 200, `affectedBookmarks: 0`

### 9.5 Smart Views (authenticated, scoped to current user)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/smart-views` | List all Smart Views for the current user |
| `POST` | `/api/v1/smart-views` | Create a Smart View |
| `GET` | `/api/v1/smart-views/:id` | Get a single Smart View |
| `PUT` | `/api/v1/smart-views/:id` | Update a Smart View |
| `DELETE` | `/api/v1/smart-views/:id` | Delete a Smart View |
| `GET` | `/api/v1/smart-views/:id/bookmarks` | Run the query; returns `Page<Bookmark>` |

Validation (`POST`/`PUT`): non-empty `name` ≤ 100 chars, at least one condition,
each condition a valid type with a non-empty (and, for dates, ISO-8601-parseable)
value — otherwise `422 validation_failed`. A missing/foreign Smart View returns
`404 smart_view_not_found`. `:id/bookmarks` supports `page`/`per`; the `isArchived`
condition overrides the default archived filter (otherwise non-archived only).

### 9.6 Metadata (authenticated)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/metadata` | Fetch title, description, favicon without saving |

### 9.7 Admin (authenticated, admin role only)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/admin/users` | List all users with stats |
| `POST` | `/api/v1/admin/users` | Create user (always `user` role) |
| `GET` | `/api/v1/admin/users/:id` | Get user |
| `PUT` | `/api/v1/admin/users/:id` | Suspend/unsuspend, reset password |
| `DELETE` | `/api/v1/admin/users/:id` | Hard-delete (cannot delete self) |
| `POST` | `/api/v1/admin/users/:id/reset-totp` | Reset user's 2FA |
| `GET` | `/api/v1/admin/stats` | Aggregate stats |

---

## 10. Metadata Fetching

On `POST /api/v1/bookmarks` with `fetchMetadata: true` (default):

1. HTTP GET to the URL via Vapor's built-in HTTP client
2. Dependency-free regex parser (`MetadataFetcher`) extracts `<title>`, `<meta
   name="description">`, favicon
3. Client-supplied values take precedence
4. Title falls back to URL if blank
5. On any failure: save proceeds with client-supplied values — never blocks

Timeout: 5 seconds. No retry.

---

## 11. Import & Export

### 11.1 Architecture

Pluggable `ImportExportRegistry`. New formats: conform to protocol, register in
`init` — no controller, route, or template changes needed.

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

Parse failure throws `ImportError.invalidFormat` (inline error, no redirect).
Bad individual records are counted in `skipped`/`errors`, shown in a collapsible
`<details>` block.

### 11.2 Anybox JSON Importer (`identifier: "anybox"`)

Anybox exports a JSON array. **Actual field shapes** (verified against a real
export):

- `tags` is `[[String]]` — arrays of `[namespace, value]` pairs (e.g.
  `[["topic","swift"],["status","reading"]]`). Each pair joined with `/` →
  hierarchical Stash tag (`topic/swift`). Plain `[String]` accepted as fallback.
- `dateAdded` — camelCase, ISO-8601 string. Numeric `date_added`/`dateAdded`
  accepted as fallback. Missing → current time.

| Anybox field | Stash field | Notes |
|---|---|------|
| `url` | `url` | Required; skip if missing or invalid |
| `title` | `title` | Empty string if missing |
| `description` | `description` | |
| `tags` | `tags` | Normalised |
| `dateAdded` | `createdAt` | ISO-8601; Unix int fallback |
| `folder` | — | Ignored (flat import) |
| others | — | Ignored |

Duplicate URL: update title, description, tags in place. `createdAt` preserved.

### 11.3 Stash JSON Importer (`identifier: "stash-json"`)

Imports a previously exported Stash JSON file. Useful for migrating between
instances.

| Field | Notes |
|-------|-------|
| `bookmarks[].url` | Required; skip if missing or invalid |
| `bookmarks[].title` | |
| `bookmarks[].description` | |
| `bookmarks[].tags` | Normalised |
| `bookmarks[].isArchived` | |
| `bookmarks[].faviconURL` | |
| `bookmarks[].createdAt` | ISO-8601; current time if missing |
| `id`, `updatedAt`, `version`, `exportedAt` | Ignored |

Duplicate URL: update in place. `createdAt` preserved.

### 11.4 Stash JSON Exporter (`identifier: "stash-json"`)

All bookmarks (including archived), sorted by `createdAt` ascending:

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

`Content-Disposition: attachment; filename="stash-export-YYYY-MM-DD.json"`.

---

## 12. Web Admin Dashboard (`/admin`)

Session-based auth (`stash_admin_session` cookie, in-memory, HTTPOnly,
SameSite=Lax). Only active admin accounts can log in. Sessions don't survive a
container restart.

### Pages

| Page | Path |
|------|------|
| Login | `/admin/login` |
| Dashboard | `/admin` |
| User List | `/admin/users` |
| Create User | `/admin/users/new` |
| User Detail | `/admin/users/:id` |
| Appearance | `/admin/appearance` |

### Business Rules

- Accounts always created as `user` role
- Admin cannot delete own account (button hidden + POST blocked → 400)
- Admin cannot suspend own account (button hidden + POST blocked → 400)
- Suspend and password reset invalidate all refresh tokens
- 2FA reset: clears secret + recovery codes + invalidates refresh tokens
- Post/Redirect/Get with `?ok=` confirmation banners
- HTML forms use POST sub-routes for destructive actions (suspend, delete, etc.)
- Nav includes an "App" link to `/app` (always shown — every admin also has a
  regular bookmark collection, so it is never a dead end)
- The Appearance page (`GET`/`POST /admin/appearance`) edits the instance
  `SiteSettings` (§7.6): accent theme (nine circles, pure-HTML radios), the
  about message (max 280 chars), and the custom footer link (URL must be
  `https://`). Each theme circle previews the colour for the active mode — its
  light value in light mode, its dark value in dark mode — matching what the app
  actually renders. Invalid input → 422 with the form re-rendered; on success the
  app-level cache is refreshed and PRG redirects with `?ok=saved`.

---

## 13. Web Frontend (`/app`)

Session-based auth (`stash_session` cookie, path `/app`, in-memory,
SameSite=Lax). Any active user role can log in. Sessions don't survive a
container restart.

### Pages

| Page | Path |
|------|------|
| Login | `/app/login` |
| Bookmark List | `/app` |
| Add Bookmark | `/app/bookmarks/new` |
| Bookmark Detail | `/app/bookmarks/:id` |
| Edit Bookmark | `/app/bookmarks/:id/edit` |
| Tag Browser | `/app/tags` |
| Smart Views (manage) | `/app/smart-views` |
| New / Edit Smart View | `/app/smart-views/new`, `/app/smart-views/:id/edit` |
| Smart View results | `/app/smart-views/:id` |
| Settings | `/app/settings` |

Nav includes a "Dashboard" link to `/admin`, shown only when the signed-in user
is an admin (a regular user can't get past the admin login, so the link would be
a dead end for them).

### Bookmark List Features

- Search (`?q=`), tag filter (`?tag=`), archived toggle (`?archived=true`)
- Pagination with prev/next links preserving active filters
- Two-column layout: bookmark list (left/main) + tag sidebar (right, 220px)
- Mobile (<768px): sidebar hidden, filter pills used instead

### Tag Sidebar

- Right column, plain flex — scrolls with the page as one unit (no fixed/sticky
  positioning)
- Two labeled sections: a **Views** heading over the smart filters (All,
  Untagged, Today, This Week), then a **Tags** heading over the hierarchical tag
  tree. The top heading also lines the sidebar up with the search field.
- "All" link at top (highlighted when no filter active)
- "Untagged" link (highlighted when `?tag=__untagged__`; count shown when > 0)
- "Today" link (highlighted when `?tag=__today__`; bookmarks created since the
  start of the current day; count shown when > 0)
- "This Week" link (highlighted when `?tag=__this_week__`; bookmarks created
  since the most recent Monday; count shown when > 0)
- Full hierarchical tag tree, alphabetical at every level
- Parent tags with children shown via indentation; synthetic parents (count 0)
  included so children always nest
- Tag counts in muted colour; active tag highlighted with accent colour
- Aligned with the search bar via `margin-top`

### Add / Edit Bookmark

- Add form: two-step — "Fetch metadata" previews server-side; "Save" persists
- Add form accepts an optional `?url=` query parameter that pre-populates the
  URL field (e.g. `/app/bookmarks/new?url=https://example.com`). It only
  pre-fills — the user must still click "Save"; nothing is added automatically.
  Enables a browser bookmarklet that opens Stash with the current page's URL.
- Duplicate URL: inline error with link to existing bookmark
- Edit form does not allow URL changes (avoids duplicate-handling complexity)
- Tag input with autocomplete: vanilla JS (~50 lines), splits on commas, matches
  user's existing tags embedded as JSON in `data-known-tags` attribute by
  per-segment prefix (a fragment matches any `/`-delimited segment that starts
  with it, so `music` finds `kind/music-gear`)

### Tag Browser (`/app/tags`)

- Full tag list with counts
- Inline rename form per tag (vanilla JS toggle, Post/Redirect/Get)
- Inline delete confirmation per tag (vanilla JS toggle, Post/Redirect/Get)
- Rename renames tag and all children; merge if target exists
- Delete removes tag and all children from all bookmarks

### Smart Views

- Appear in the bookmark-list sidebar above the tag tree (below Today / This Week),
  sorted alphabetically, each a `⊞`-prefixed link to `/app/smart-views/:id`. No
  count is shown; the section only appears when the user has at least one Smart
  View. The active Smart View highlights with `--accent`.
- The results page reuses the bookmark-list template (same sidebar, same
  pagination) with the page title set to the Smart View name and a "Smart View"
  label. No search bar. The archived toggle works unless the Smart View has an
  `isArchived` condition (then it is hidden and the condition controls it).
- Management is a top-level nav item (`Smart Views`, between Tags and Settings): a
  table of all Smart Views with their condition summaries and Edit / Delete actions. The create/edit form is
  a dynamic condition builder (type `<select>` + value input per row, Add / Remove
  rows, native date picker for date conditions, Yes/No select for `isArchived`),
  using the same minimal vanilla JS as the tag autocomplete. A `tag` condition's
  value field reuses the bookmark forms' tag autocomplete (suggesting the user's
  existing tags), so tags don't have to be guessed. PRG with `?ok=saved` /
  `?ok=deleted` banners; inline delete confirmation.

### Settings (`/app/settings`)

**Appearance:** Light / Dark / Auto radio buttons. `POST /app/settings/theme`
sets `stash_theme` cookie (1 year, path `/`, HTTPOnly=false, SameSite=Lax).

**Account:** change password.

**Two-Factor Authentication:** enrol (QR via `otpauthURI` + manual key), disable
(requires current TOTP code; recovery codes shown once with "I've saved these"
confirmation).

**Import & Export:**
- Import: file upload, format selector (Anybox JSON, Stash JSON), summary banner
  with imported/updated/skipped counts, collapsible error details. Upload body
  limit 16MB.
- Export: "Download your bookmarks" → Stash JSON file download.

**Danger Zone:**
- "Delete all bookmarks" — requires typing `delete all` (case-insensitive).
  Verified server-side. Resets `bookmarkCount` to 0. Redirects to `/app` with
  flash banner.

### Dark Mode

Three-way CSS resolution:
- `:root` → light values
- `[data-theme="dark"]` → explicit dark
- `@media (prefers-color-scheme: dark) :root:not([data-theme])` → auto

Inline flash-prevention script at top of `<head>` sets `data-theme` from
`stash_theme` cookie before first paint — no flash. Applies to both `/app` and
`/admin` (shared `layout.leaf`). iOS-style palette: bg `#1c1c1e`, surface
`#2c2c2e`, accent `#0a84ff`, danger `#ff453a`, success `#30d158`.

---

## 14. CLI — `stash` ✅ Complete (M7)

Swift CLI, `ArgumentParser` + `MicroClient` (direct, for 2FA login branch),
`StashKit`. Config: `~/.config/stash/config.json`.

```
stash login / logout

stash add <url> [--title] [--description] [--tag] [--no-fetch] [--json]
stash list [--tag] [--search] [--archived] [--page] [--json]
stash get <id> [--json]
stash delete <id>
stash archive <id>
stash tags [--json]
stash tags rename --from <tag> --to <tag>
stash tags delete <tag>
stash import <file> [--format anybox|stash-json]
stash export [--format stash-json] [--output <path>]

stash admin users [--json]
stash admin create-user --username <u> --password <p>
stash admin suspend-user / unsuspend-user <username>
stash admin reset-password <username> --password <p>
stash admin reset-totp <username>
stash admin delete-user <username>
stash admin stats [--json]
```

---

## 15. StashKit — Shared Swift Package ✅ Complete (M6)

Built on `MicroClient` (`from: "0.0.27"`). Swift tools 6.0, iOS 26.0 / macOS
26.0.

Three layers: **DTOs** (Codable/Sendable structs matching API wire shapes),
**request factories** (one `enum` per domain, `public static` methods returning
typed `NetworkRequest<…>`), **thin `StashClient`** (wraps `NetworkClient`, adds
`BearerAuthorizationInterceptor` + `ContentTypeInterceptor` +
`AcceptHeaderInterceptor`, maps errors to `StashAPIError`).

No storage, no refresh logic, no business logic. `tokenProvider: @escaping
@Sendable () async -> String?` keeps the package storage-agnostic. Tag cache and
silent refresh are the app's repository layer responsibility.

Domains covered by request factories: auth, user, bookmarks, tags, metadata,
admin, and `SmartViewRequestFactory` (list/create/get/update/delete plus the
`:id/bookmarks` query), with matching `SmartViewDTO` / `SmartViewConditionDTO`
DTOs and a `SmartViewRequest` body.

---

## 16. iOS App ✅ Complete (M8 + M9)

### Project

- `StashApp/Stash.xcodeproj` is committed and uses synchronized folder groups
  (XcodeGen was retired — see `DECISIONS.md`)
- Single multiplatform SwiftUI app target `Stash` (iOS 26.0 + macOS 26.0) and
  one multiplatform Share Extension target
- Bundle ID: `cc.otavio.stash`
- App Group: `group.cc.otavio.stash`
- `NSAllowsArbitraryLoads: true`
- Direct dependency on `MicroClient` (for 2FA login branch, same as CLI)

### Architecture

**Layers:** `StashKit` (DTOs + factories) → `Repository` (DTO→domain mapping,
session state, tag cache) → `ViewModel/View`

**`AppEnvironment`** — `@MainActor @Observable` DI container built once at
launch. Exposes `makeBookmarkRepository()` (per-view instances) rather than a
shared instance; `AuthRepository` and `TagRepository` remain shared singletons.

**Repository pattern:** `AuthRepository`, `BookmarkRepository`, `TagRepository`
are `@MainActor @Observable`. Silent refresh centralised in
`AuthRepository.refreshIfNeeded()` behind a `SessionRefreshing` protocol to
avoid reference cycles.

**`StashClientProvider`** — rebuilds `StashClient` only when the server URL
changes. `tokenProvider` closure reads from `TokenManager` at request time.

### Keychain

`KeychainStore` vendored from Triton, extended with optional `accessGroup:
String?` parameter for Share Extension token sharing. Both tokens (access +
refresh) stored in Keychain — enables cold-start session restoration and Share
Extension reuse (deviation from original memory-only access token spec).

`TokenManager` decodes JWT `exp` by hand (base64url, no library) for
`isAccessTokenExpiringSoon()`.

### Navigation

- **iPad:** `NavigationSplitView` — tag sidebar drives filtered
  `BookmarkListView` in detail column
- **iPhone:** `TabContainerView` — Bookmarks / Tags / Settings tabs, each in its
  own `NavigationStack`. Tab bar uses iOS 26 floating Liquid Glass style;
  collapses on scroll via `tabBarMinimizeBehavior`
- Bookmark rows use closure-based `NavigationLink` (not
  `navigationDestination(for:)`) to avoid multi-depth registration conflicts
- Login uses typed `LoginRoute` enum for 2FA navigation

### Views (core)

`RootView` → `SetupView` / `LoginView` / `TOTPView` / `RecoveryCodeView` /
`MainView` → `BookmarkListView` / `BookmarkDetailView` (stub) /
`AddBookmarkSheet` / `TagBrowserView` (stub) / `SettingsView` (stub with Sign
Out)

Liquid Glass design adopted automatically — tab bar floats over content,
toolbars and navigation bars gain glass background. No explicit `.liquidGlass`
calls needed; compiling against iOS 26 SDK is sufficient.

`FaviconView` vendored from Triton (Google favicon service, `AsyncImage`,
fallback `"link"` SF Symbol, `RoundFaviconModifier` 16×16 4pt corners).

`BookmarkRowView` shows first three tags + `+N` overflow (not a scrolling row —
avoids gesture conflict in lists).

`AddBookmarkSheet` — paste button (`PasteButton`, no `UIKit`), metadata fetch,
comma-separated tag input with `TagSuggestionView` autocomplete chips.

Context-aware empty states: `ContentUnavailableView.search` for active query,
tag-specific, archived-specific, first-run.

### Remaining for M10

Full Settings (password change, 2FA management), edit/delete bookmark, tag
rename/delete, macOS target.

---

## 17. macOS App ✅ Complete (M10)

macOS 26.0 is a destination of the **single multiplatform `Stash` target** (not
a separate target) — the one `@main App` branches per platform with `#if
os(macOS)`. Adopts the macOS 26 design language (Liquid Glass) automatically by
building against the SDK; no explicit modifiers.

- **Navigation:** `NavigationSplitView` with a tag sidebar (All Bookmarks,
  Untagged, the tag list) driving the shared `BookmarkListView` in the detail
  column; selecting a bookmark pushes the shared `BookmarkDetailView`. The
  optional inspector panel was not built (the shared list is reused as-is for
  maximum code sharing).
- **Window:** standard `WindowGroup`, 800×500 minimum
  (`windowResizability(.contentMinSize)`).
- **Bookmarks:** shared list and rows; right-click context menu (Open in
  Browser, Copy URL, Archive/Unarchive, Delete); add and edit via shared sheets;
  delete with confirmation.
- **Settings scene (⌘,):** General (server URL, sign out), Account (change
  password, 2FA enrol / disable), Appearance (Light / Dark / Auto, stored in
  `UserDefaults` — no theme cookie on native).
- **Keyboard shortcuts:** ⌘N new, ⌘E edit, ⌘R refresh, ⌘⌫ delete (with
  confirmation).
- **Share Extension:** the single multiplatform `StashShareExtension` target
  serves both platforms (same three states and confirmation-with-undo); only the
  principal controller differs — `MacShareViewController` (`NSViewController`)
  on macOS vs `ShareViewController` (`UIViewController`) on iOS, both
  `#if`-guarded.

---

## 18. Deployment

### Distribution

Docker image at `ghcr.io/otaviocc/stash`. Single `docker-compose.yml` — no build
step required.

### Image

- **Build:** `swift:6.1-jammy` → `ubuntu:22.04` runtime
- **Platforms:** `linux/amd64`, `linux/arm64`
- **Tags:** `latest`, semver

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

### First Boot

Reads `ADMIN_USERNAME` / `ADMIN_PASSWORD` from env, creates admin if no users
exist. Missing/invalid → logs critical error, exits. Subsequent boots: silent
no-op. Migrations auto-run on boot (idempotent).

### Local Network

Primary use case: `http://192.168.1.x:8080`. No domain or TLS required.
In-memory sessions don't survive a container restart.

### External Access (optional)

```
stash.yourdomain.com {
    reverse_proxy localhost:8080
}
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `DB_PASSWORD` | PostgreSQL password |
| `JWT_SECRET` | JWT signing secret (min 32 chars) |
| `ADMIN_USERNAME` | Admin username (first boot only) |
| `ADMIN_PASSWORD` | Admin password (first boot only, min 12 chars) |

### CI/CD ✅ Complete (M4.1)

Two GitHub Actions workflows. `ci.yml` runs on every push to `main` and every
pull request — builds and tests all components, no image. `release.yml` runs on
a `v*.*.*` tag: re-runs the backend tests, then builds a multi-arch image
(`linux/amd64`, `linux/arm64`) → pushes to `ghcr.io/otaviocc/stash` (`latest` +
semver) → creates a GitHub Release with `docker-compose.yml` attached.
`GITHUB_TOKEN` only — no extra secrets. The repo stays private; the image is
made public via a **one-time manual setting** in the package settings (there is
no API to do it from CI).

---

## 19. Technical Specification

### 19.1 Repository Structure

```
stash/
├── Backend/
│   ├── Sources/App/
│   │   ├── Controllers/
│   │   ├── Models/
│   │   ├── Migrations/
│   │   ├── Middleware/
│   │   ├── ImportExport/
│   │   ├── Tags/
│   │   ├── Extensions/          # QueryBuilder+filterFullText, etc.
│   │   └── configure.swift
│   ├── Tests/AppTests/
│   ├── Resources/Views/
│   ├── Package.swift
│   ├── Dockerfile
│   └── docker-compose.yml
├── StashKit/                    # ✅ Complete (M6)
│   ├── Sources/StashKit/
│   │   ├── Client/
│   │   ├── DTOs/
│   │   └── Factories/
│   └── Tests/StashKitTests/
├── StashApp/                    # ✅ Complete (M8–M10)
│   ├── Common/                  # compiled into the app + both Share Extensions
│   ├── Stash/                   # app-only code (iOS + macOS); @main entry
│   ├── StashShareExtension/     # both Share Extensions (#if-guarded controllers)
│   ├── Config/                  # non-synced per-platform Info.plist + entitlements
│   └── Stash.xcodeproj          # committed; synchronized folder groups
├── CLI/                         # ✅ Complete (M7)
│   ├── Sources/stash/
│   └── Package.swift
├── .github/workflows/           # Planned (M4.1)
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
| `token_invalid` | 401 | Malformed or unrecognised token |
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
| Auth | Login, TOTP, recovery codes, refresh rotation, logout, 2FA enrol/disable |
| Bookmarks | CRUD, 409, tag filtering, `__untagged__`, full-text search (case-insensitive), pagination, user isolation |
| Admin | Create, suspend, reset password, reset TOTP, delete, stats, self-delete guard |
| Tags | Rename (with children, merge), delete (with children), user isolation |
| Middleware | 401 unauthenticated, 403 non-admin |
| Admin seeding | Seeds, skips, exits on bad creds |

### 19.7 Code Style

SwiftLint + SwiftFormat. `swiftlint lint` 0 violations, `swiftformat --lint`
idempotent. Applied to Backend, StashKit, CLI, and iOS app.

- Organisation: type mode (`Nested Types → Static Properties → Properties →
  Computed Properties → Lifecycle → Functions`), public-before-private within
  sections
- `///` doc comments on types only; no inline comments inside method bodies
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

---

## 21. Known Leaf Gotchas

- `#if(count(x))` does **not** coerce `Int` to `Bool` — `count 0` evaluates
  truthy. Always use `#if(count(x) > 0)`.
- Inline conditionals require the colon: `#if(cond): … #endif`.
- `#if(cond):#else: X #endif` with an empty then-branch misbehaves (else content
  dropped). Use positive single-branch tests.
- A non-optional `String` field set to `""` makes `#if(field)` evaluate
  **true**. Use `#if(field != "")` or `#if(field == "")` explicitly.

---

## 22. Out of Scope

- Open/public registration
- Cross-user bookmark visibility or sharing
- Page archiving or offline reading
- Browser extension
- Read-later queue or unread state
- Annotations or highlights
- SSO / OAuth
- Menu bar app (macOS)