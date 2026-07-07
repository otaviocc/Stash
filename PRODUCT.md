# Stash — Product Requirements Document

**Version:** 1.9
**Status:** Living Document
**Author:** Otávio

---

## 1. Overview

Stash is my self-hosted bookmark manager. Fully private, and multi-user.
Under the hood it's a Swift/Vapor REST API backed by Postgres, deployed via
Docker, with native clients for iOS, macOS, and the command line, all sharing a
Swift package (`StashKit`) for models and networking.

I built it around one non-negotiable: full data ownership. Self-hosted, no
third-party cloud — nothing about my bookmarks living on someone else's server.

---

## 2. Goals

What I wanted out of it:

- Save bookmarks quickly from any Apple platform via Share Extensions or the CLI
- Retrieve bookmarks reliably via keyword search, tag browsing, or recency
- Organise bookmarks with both flat and hierarchical tags
- Rename and delete tags across all bookmarks in bulk
- Save named queries as Smart Views that filter bookmarks by a set of AND conditions
- Auto-fetch page metadata (title, description, favicon) at save time, with
  manual override
- Support multiple users, each with a fully isolated bookmark collection
- Manage accounts myself as admin — create, suspend, and hard-delete, reset
  passwords and 2FA — via web dashboard and CLI
- Authenticate with username + password + TOTP-based 2FA, with recovery codes
- Let users enable, disable, and manage their own 2FA
- Let users change their own password
- Block duplicate URLs per user at save time
- Import bookmarks from Anybox JSON export and Stash JSON
- Export bookmarks in Stash native JSON format
- Export and import Smart Views as part of the Stash native JSON format
- Dark mode support (Light / Dark / Auto)
- Keep all data on infrastructure I control
- Stay fully private — no public sharing, no public registration

---

## 3. Non-Goals (v1)

Things I deliberately left out, at least for now:

- Public or open registration
- Cross-user bookmark visibility or sharing
- Page content archiving (saving article text/HTML for offline reading) — distinct
  from the native apps' offline access to their own bookmark data, which is supported
- Public or shared collections
- Read-later / queue functionality
- SSO or OAuth
- Menu bar app (macOS)

---

## 4. User Roles

| Role | Description |
|------|-------------|
| **Admin** | The primary user. Can manage all accounts, reset any user's 2FA. Has their own bookmark collection like any other user. |
| **User** | A regular account created by the admin. Can manage their own bookmarks, change their own password, and manage their own 2FA. Cannot see other users' data. |

There's exactly one admin, in practice. The account is seeded at first
boot from environment variables; there's no public sign-up flow.

---

## 5. Platforms

What's actually built, versus what's still on the list:

| Platform | Type | Status |
|----------|------|--------|
| Backend | Vapor 4 REST API | ✅ Complete |
| Web admin dashboard | Server-rendered (Leaf) | ✅ Complete |
| Web frontend (user-facing) | Server-rendered (Leaf) | ✅ Complete |
| CLI (`stash`) | Swift CLI tool | ✅ Complete |
| iOS | Native SwiftUI app + Share Extension | ✅ Complete (M8 + M9) |
| macOS | Native SwiftUI app + Share Extension | ✅ Complete (M10) |
| Browser extension | WebExtension (Firefox + Chrome/Zen) | ✅ Complete |

---

## 6. Architecture

Here's how the pieces fit together:

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
notation, like `swift/vapor`. I derive the tag tree dynamically per user rather
than keeping a separate tags table.

A derived `tagsSearch` column stores tags as `|swift|swift/vapor|` so prefix
matching can happen with a plain SQL `LIKE` — the same behaviour on SQLite
(tests) and PostgreSQL (production).

Querying `tag=swift` matches bookmarks where `tagsSearch` contains `|swift` —
a prefix match, so it includes `swift` and `swift/*`, but not `swiftui`.

**Tag normalisation:** trimmed, lowercased, surrounding slashes stripped,
de-duplicated. Enforced server-side on every write.

### 7.6 Site Settings

Instance-wide customisation, managed by the admin. It's a single-row
configuration table — always exactly one row, created on first boot with
default values, never deleted — and cached in the application at startup so
page renders never hit the database.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `accentTheme` | String | Default `"ocean"`. One of the ten theme identifiers. |
| `aboutText` | String? | Optional. Short message shown in the footer. Max 280 chars. |
| `footerCustomLabel` | String? | Display label for the admin's custom footer link. |
| `footerCustomURL` | String? | URL for the custom footer link. Must be `https://`. |
| `createdAt` | Date | Auto-set |
| `updatedAt` | Date | Auto-updated |

**Accent themes.** Ten named themes, each with a light-mode and a dark-mode hex
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
| `indigo` | Indigo | `#231468` | `#818cf8` |

The selected theme's values are injected into `layout.leaf`'s `<head>` as a CSS
block overriding `--accent`, from the app-level cache (no per-request query).

### 7.7 Smart View

A named, saved query owned by a user. It stores rules, not results — every time
it's opened the query runs live against the user's bookmarks. `matchMode`
decides how the conditions combine: `all` (every condition must match — AND) or
`any` (at least one — OR), the same idea as macOS Music's "Match all/any of the
following rules".

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `userID` | UUID | Foreign key → User; all queries scoped to this |
| `name` | String | Display name. Required, max 100 chars. |
| `matchMode` | String | `"all"` (AND) or `"any"` (OR). Defaults to `"all"`. |
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
| `olderThan` | `createdAt` is more than N days/months/years ago (relative to now) |
| `newerThan` | `createdAt` is within the last N days/months/years (relative to now) |
| `isArchived` | `isArchived` equals `true`/`false` |
| `hasTags` | `tagsSearch` is non-empty (`true`) or empty (`false`) — i.e. the bookmark has any tags |

Text conditions use the same portable `lower(column) LIKE lower('%value%')` helper
as full-text search. Multiple conditions of the same type are allowed (with
`matchMode: all`, two `tag` conditions = the bookmark must have both tags; with
`any`, either tag matches). The non-archived default is applied as an outer AND in
both modes — results are limited to non-archived bookmarks unless an `isArchived`
condition is present.

The relative-age conditions `olderThan` / `newerThan` carry a compact **duration
string** as their value — a positive integer followed by a unit suffix: `d` (days),
`m` (months), or `y` (years), e.g. `"30d"`, `"3m"`, `"1y"`. The cutoff is computed
from the current time **at query execution, not at Smart View creation** (so "older
than 6 months" stays current as time passes), using calendar arithmetic — `"1m"` is
one calendar month, not a fixed 30 days. They join, and do not replace, the absolute
`createdBefore` / `createdAfter` date conditions.

**Client support.** The web frontend and the native iOS/macOS apps create, edit,
delete, and browse Smart Views. The apps surface them as a browse-only Smart Views
section in the sidebar, and manage them (create / edit / delete) from a Settings →
Smart Views screen. The **CLI is consumption-only**: it lists Smart Views and opens
their live results (`stash smart-views`); authoring on the CLI is done on the web
or round-tripped through Stash JSON import/export.

**Footer.** Shown on every `/app` and `/admin` page via `layout.leaf`. Fixed,
non-configurable content: a GitHub link (`https://github.com/otaviocc/Stash`), a
Mastodon link (`https://social.lol/@otaviocc`), a Ko-fi link
(`https://ko-fi.com/otaviocc`), and the version string (read from a `VERSION`
file at startup, `"dev"` if missing). Configurable content: the optional
`aboutText` (shown above the links) and one optional custom link
(`footerCustomLabel` + `footerCustomURL`, shown only when both are non-empty).
All external links open in a new tab with `rel="noopener noreferrer"`. The Stash
identity (name, logo, GitHub, Ko-fi, and Mastodon links) is hardcoded and not
configurable.

### 7.8 Favicon Cache

Favicons are cached **per domain** (not per bookmark or per user) and served from
Stash itself instead of relying on the browser fetching from the origin site or
Google on every render. A new bookmark for any URL on an already-cached domain
reuses the existing image — the cache grows with unique domains, not bookmark
count. I fetch it once when a domain is first encountered, and only re-fetch on
an explicit manual refresh.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `domain` | String | Unique. Lowercased hostname, `www.` stripped, explicit port kept (e.g. `github.com`, `192.168.1.5:8080`). |
| `imageData` | Data? | Binary image bytes (`bytea`/BLOB). `nil` if the fetch failed. |
| `contentType` | String? | MIME type, e.g. `image/png`, `image/x-icon`. |
| `sourceURL` | String? | The URL the image was actually fetched from, for debugging. |
| `status` | Enum | `pending`, `cached`, or `failed`. |
| `fetchedAt` | Date? | When the fetch last completed (success or failure). |
| `createdAt` | Date | Auto-set |
| `updatedAt` | Date | Auto-updated |

There's a unique index on `domain` — the insert-then-catch path uses it to
dedupe concurrent first-time fetches for the same domain. Image bytes are
capped at 100KB (rejected via the `Content-Length` header before download when
present), the `Content-Type` must be a non-SVG `image/*` (SVG is refused as
active content), and the served response carries
`X-Content-Type-Options: nosniff`. The bookmark's `faviconURL` field is no
longer written for new bookmarks (domain-keyed lookup at render time supersedes
it) but the column is retained.

---

## 8. Authentication & Security

### 8.1 Token Strategy

| Token | Lifetime | Storage (client) |
|-------|----------|-----------------|
| Access token (JWT, HS256) | 15 minutes | Keychain (iOS/macOS), memory (CLI, web) |
| Refresh token (opaque 256-bit hex) | 90 days, rotated on use | Keychain (iOS/macOS), file (CLI), session (web) |

Silent refresh within 60 seconds of expiry. The 2FA temp token uses `scope:
"2fa"` so it cannot be replayed as an access token.

One deviation from my original plan: both tokens live in Keychain on
iOS/macOS, not just the refresh token — that's what makes cold-start session
restoration and Share Extension token reuse possible.

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

The web UI shows the `otpauthURI` plus a manual setup key — no QR image, since
CoreImage isn't available on Linux. The native clients render a QR code from
`otpauthURI` instead.

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
| `GET` | `/api/v1/bookmarks/changes` | Bookmarks changed since a timestamp (offline sync) |
| `GET` | `/api/v1/bookmarks/deleted` | Tombstones for deleted bookmarks (offline sync) |

**`GET /api/v1/bookmarks` query parameters:**

| Parameter | Description |
|-----------|-------------|
| `q` | Full-text search (URL, title, description, tags). Case-insensitive on both SQLite and PostgreSQL via `lower(column) LIKE lower(term)`. |
| `tag` | Prefix filter. `swift` matches `swift` and `swift/*` but not `swiftui`. Special values: `__untagged__` returns bookmarks with no tags; `__today__` / `__this_week__` return bookmarks created since the start of the day / the most recent Monday. |
| `archived` | Default false. Pass `true` for archived bookmarks. |
| `page` / `per` | Pagination. `per` clamped 1–100. |

**Offline-sync endpoints** (consumed by the native apps; see `DECISIONS.md` →
Offline Sync):

- **`GET /api/v1/bookmarks/changes?since=<ISO8601>&page=&per=`** — a
  `Page<Bookmark>` of all bookmarks (**archived included**) with `updatedAt >
  since`, sorted ascending by `updatedAt`. `per` defaults to 100, clamped 1–500.
  Omitting `since` returns every bookmark (initial full sync). A malformed `since`
  is a `validation_failed` 422.
- **`GET /api/v1/bookmarks/deleted?since=<ISO8601>`** — a flat array of tombstones
  `[{ "id": "<deleted bookmark id>", "deletedAt": "<ISO8601>" }]` for bookmarks
  hard-deleted after `since`, sorted ascending by `deletedAt` (no pagination).
  Omitting `since` returns all tombstones. Every hard delete — via the API or the
  web frontend, single or bulk — records a tombstone so an offline client learns
  what to remove locally.

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

Validation (`POST`/`PUT`): non-empty `name` ≤ 100 chars, an optional `matchMode`
of `all`/`any` (defaults to `all`), at least one condition, each condition a valid
type with a non-empty (and, for dates, ISO-8601-parseable) value — otherwise
`422 validation_failed`. A missing/foreign Smart View returns
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

### 9.8 Favicons

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/api/v1/favicons/:domain` | None | Serve the cached favicon image for a domain |
| `POST` | `/api/v1/favicons/:domain/refresh` | Any active user | Delete the cached row and trigger a re-fetch |

- `GET` is **unauthenticated** so `<img>` tags can load it without attaching
  credentials. A `cached` row returns the image bytes with its stored
  `Content-Type` and `Cache-Control: public, max-age=2592000, immutable` (30
  days). A `failed`, `pending`, or missing row returns `404 not_found` — the web
  UI degrades gracefully to no icon.
- `POST .../refresh` requires being logged in (favicons are shared, not
  privileged, but auth prevents anonymous abuse). It deletes the existing row and
  kicks off a fresh fetch detached, returning `202 Accepted` immediately. No rate
  limiting (see `DECISIONS.md`).

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

**Favicon fetching is decoupled** from this per-bookmark metadata fetch. The
metadata fetch still discovers the page's declared `<link rel="icon">`, but
favicon *caching* now happens at the domain level (§7.8): on bookmark creation
Stash hands that declared icon (when available) to a detached `FaviconFetcher`
keyed by domain, rather than storing a per-bookmark `faviconURL`. See §7.8 and
the Favicon Caching section of `DECISIONS.md`.

**Native clients fetch metadata on-device.** The iOS/macOS app and Share
Extension don't call `POST /api/v1/metadata` for the add-bookmark preview —
they run the same regex parser locally (`ClientMetadataFetcher`, a verbatim
port of the backend's `MetadataFetcher`), fetching the target page directly.
That way metadata still shows up even when the Stash backend is unreachable
(say, away from the home-lab network), with no round-trip and no timeout
delay. The `/api/v1/metadata` endpoint remains for the web UI and the browser
extension. Favicon *caching* is unaffected — it still happens server-side,
keyed by domain, when the bookmark reaches the backend (on create/sync),
regardless of where the title/description preview came from.

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

Anybox exports a JSON array. I verified the actual field shapes against a real
export, which turned out to differ slightly from what I first assumed:

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
| `smartViews[].name` | Required; ≤ 100 chars |
| `smartViews[].matchMode` | `all`/`any`; defaults to `all` |
| `smartViews[].conditions` | At least one valid `{ type, value }`; same validation as the API |
| `id`, `updatedAt`, `version`, `exportedAt` | Ignored (also `smartViews[].id`/`createdAt`/`updatedAt`) |

Duplicate URL: update in place. `createdAt` preserved. The `smartViews` node is optional, so
older exports without it still import. A Smart View whose `name` already exists for the user is
updated in place; otherwise it is created — so re-importing is idempotent. A Smart View with an
empty name or no valid conditions is skipped and reported, like a bad bookmark record.

### 11.4 Stash JSON Exporter (`identifier: "stash-json"`)

All bookmarks (including archived), sorted by `createdAt` ascending, plus all of the user's Smart
Views, sorted by `name`:

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
  ],
  "smartViews": [
    {
      "id": "uuid",
      "name": "Reading list",
      "matchMode": "all",
      "conditions": [
        { "type": "tag", "value": "swift" },
        { "type": "hasTags", "value": "true" }
      ],
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
  `SiteSettings` (§7.6): accent theme (ten circles, pure-HTML radios), the
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

Every web page (`/app`, `/admin`, landing, and login) carries the Stash favicon —
the app-icon mark (a white bookmark ribbon on an indigo `#231468` rounded square),
served from `Backend/Public/` as `favicon.svg` / `favicon.ico` /
`apple-touch-icon.png` and linked from the shared `layout.leaf` head, so the web
UI matches the native apps and the browser extension in the tab bar and on the home
screen.

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
- The archived toggle ("View archived" / "← Active bookmarks") preserves the
  active search and tag filter — toggling archive on a filtered view shows that
  tag's archived items rather than dropping the filter, matching the native apps
- Pagination with prev/next links preserving active filters
- Two-column layout: bookmark list (left/main) + tag sidebar (right, 220px)
- Mobile (<768px): sidebar hidden, filter pills used instead
- Each row (and the detail page title) shows the domain's cached favicon via
  `<img src="/api/v1/favicons/{domain}">` (§7.8, §9.8), with an `onerror` handler
  that hides the image on a `404` — graceful degradation to no icon, never a
  broken-image glyph. The `{domain}` is computed server-side per row.

### Favicons

- Served from Stash's domain-keyed cache (§7.8), not fetched from the origin site
  or Google by the browser. Computed once per domain at bookmark creation.
- The bookmark detail page (`/app/bookmarks/:id`) carries a small "Refresh
  favicon" button that POSTs to `/app/bookmarks/:id/refresh-favicon` (a thin
  session-auth wrapper that triggers the same re-fetch as the API's
  `POST /api/v1/favicons/:domain/refresh`). PRG redirects back with a
  `?ok=favicon_refreshing` banner ("Favicon refresh started — it may take a
  moment to update.").

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
- Parent tags with children shown via indentation; synthetic parents (no count)
  included so children always nest
- Each real tag carries a **count badge** mirroring the native apps: a single
  accent capsule with the visible (non-archived) count when nothing is archived,
  or a split pill — accent "visible" left half, muted "hidden" (archived) right
  half — when the tag has archived bookmarks, so a tag whose bookmarks are all
  archived still appears (e.g. `0|5`). Synthetic parents and tags with no
  bookmarks show no badge.
- Active tag highlighted with accent colour
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

- Tag list in a `.card`-wrapped table (Tag / Bookmarks / Actions), matching the
  Smart Views management table; the Tag column absorbs the table's slack so the
  actions sit flush
- Inline rename form per tag (vanilla JS toggle, Post/Redirect/Get); Rename is an
  accent link, styled like the Smart Views Edit action
- Delete uses a native `confirm()` dialog on submit (same pattern as deleting a
  bookmark) — no inline reveal, so the table never re-renders in place
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
  `?ok=deleted` banners; Delete uses a native `confirm()` dialog on submit (same
  pattern as the tag browser and bookmark deletion).

### Settings (`/app/settings`)

**Appearance:** Light / Dark / Auto radio buttons. `POST /app/settings/theme`
sets `stash_theme` cookie (1 year, path `/`, HTTPOnly=false, SameSite=Lax).

**Account:** change password.

**Two-Factor Authentication:** enrol (QR via `otpauthURI` + manual key), disable
(requires current TOTP code; recovery codes shown once with "I've saved these"
confirmation).

**Import & Export:**
- Import: file upload, format selector (Anybox JSON, Stash JSON), summary banner
  with imported/updated/skipped counts (plus a Smart Views count when the file
  carried any), collapsible error details. Upload body limit 16MB. A Stash JSON
  file also restores Smart Views, matched by name. After a successful import a
  detached backfill caches a favicon (§7.8) for each distinct imported domain.
- Export: "Download your bookmarks" → Stash JSON file download (bookmarks and
  Smart Views).

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
stash smart-views [list] [--json]
stash smart-views bookmarks <id> [--page] [--per] [--json]
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

`stash export` of a Stash JSON file includes the user's Smart Views, and `stash import` of a
Stash JSON file restores them (matched by name, via the Smart View REST API) — at parity with the
web frontend. The CLI cannot preserve a Smart View's `createdAt` (no direct DB access), the same
limitation already noted for bookmarks.

**Smart Views are consumption-only on the CLI.** `stash smart-views` lists the user's Smart Views
(name, match mode, a condition summary, and the full UUID); `stash smart-views bookmarks <id>` runs
the saved query server-side and prints the matching bookmarks in the same table / `--json` shape as
`stash list`. Creating and editing Smart Views is done in the web frontend (or round-tripped via
import/export); a richer condition-builder CLI is a possible later step.

---

## 15. StashKit — Shared Swift Package ✅ Complete (M6)

Built on `MicroClient` (`from: "0.0.27"`). Swift tools 6.0, iOS 26.0 / macOS
26.0.

I split it into three layers: **DTOs** (Codable/Sendable structs matching API
wire shapes), **request factories** (one `enum` per domain, `public static`
methods returning typed `NetworkRequest<…>`), and a **thin `StashClient`**
(wraps `NetworkClient`, adds `BearerAuthorizationInterceptor` +
`ContentTypeInterceptor` + `AcceptHeaderInterceptor`, maps errors to
`StashAPIError`).

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
  (I retired XcodeGen — see `DECISIONS.md`)
- Single multiplatform SwiftUI app target `Stash` (iOS 26.0 + macOS 26.0) and
  one multiplatform Share Extension target
- Bundle ID: `com.example.otavio.stash`
- App Group: `group.com.example.otavio.stash`
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

**Offline sync (complete):** the apps keep a full SwiftData copy of the user's
bookmarks (`LocalStore` + `LocalBookmark`, owned by `AppEnvironment`).
`BookmarkRepository` reads entirely from this store — search, tag, recency, and
Smart View filters run in memory, mirroring the backend's SQL semantics — so
browsing works without the network. `TagRepository` derives the tag list from the
store.

`SyncEngine` runs a pull-then-push cycle with last-write-wins: it pulls
`GET /bookmarks/changes?since=` and `GET /bookmarks/deleted?since=` (the `since`
cursor is persisted; the first, cursor-less pull seeds the whole library), then
pushes every queued local change. Writes are optimistic: a create, edit, or delete
applies to the local store and returns immediately (`pendingSyncAt`/`isLocalOnly`/
`locallyDeletedAt`), so the UI updates instantly whether online or off, then a
background sync pushes the change and reconciles the list with the server's
authoritative result. A `ConnectivityMonitor` (`NWPathMonitor`) triggers a sync when
connectivity returns; sync also runs on launch/login, after each write, and on
returning from the background — which on macOS includes the app being reactivated
(foregrounded), since macOS `scenePhase` does not track focus changes — and iOS
schedules a background-refresh sync (`BGAppRefreshTask`).

Sync state is surfaced in the UI: a slim offline banner across the top of the app
shell while disconnected, a muted pending indicator on rows and the detail header
for bookmarks with unpushed changes, and a Settings "Sync" section showing the last
sync time and pending count with a "Sync Now" button and a dismissible failure
notice. The Share Extension saves online-only, but its **tag picker works offline**: the
app caches its derived tag list into the App Group so the extension can offer the same
hierarchical tag tree even when the backend is unreachable (see `DECISIONS.md` → Share
Extension picks tags offline). macOS background-task scheduling is a known follow-up (the
entitlement is in place, the scheduler is not yet wired). See `DECISIONS.md` → Offline Sync.

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

- **iPad:** `NavigationSplitView` — a sidebar with a **Views** section (All,
  Untagged, Today, This Week), an optional **Smart Views** section (one entry per
  Smart View, shown only when the user has any), and an **always-expanded, indented
  hierarchical tag tree** (a flattened `ForEach`, mirroring the web sidebar), all
  driving the filtered `BookmarkListView` in the detail column. **Drag a bookmark row onto a tag** in the
  sidebar to add that tag to the bookmark (iPad and macOS only — where the sidebar
  and list share the screen; disabled on iPhone)
- **iPhone:** `TabContainerView` — Bookmarks / Tags / Settings tabs, each in its
  own `NavigationStack`. The Tags tab shows the same Views, the optional Smart
  Views section, and the always-expanded indented tag tree, drilling into a filtered list. Tab
  bar uses iOS 26 floating Liquid Glass style; collapses on scroll via
  `tabBarMinimizeBehavior`
- Bookmark rows use closure-based `NavigationLink` (not
  `navigationDestination(for:)`) to avoid multi-depth registration conflicts
- Login uses typed `LoginRoute` enum for 2FA navigation

### Views (core)

`RootView` → `SetupView` / `LoginView` / `TOTPView` / `RecoveryCodeView` /
`MainView` → `BookmarkListView` / `BookmarkDetailView` (stub) /
`AddBookmarkSheet` / `TagBrowserView` (Views + always-expanded indented hierarchical
tag tree, rows shared with the iPad/macOS sidebars as `TagTreeLabel`) /
`SettingsView` (server URL, account settings, Sign Out) → `AccountSettingsView`

The tag tree is built client-side from the flat `GET /api/v1/tags` list by
`[Tag].hierarchy()` → `[TagNode]`, a Swift port of the web's `buildSidebar`:
every `/`-delimited ancestor becomes a node (synthetic parents carry no count),
nested and alphabetical at each level.

Liquid Glass design adopted automatically — tab bar floats over content,
toolbars and navigation bars gain glass background. No explicit `.liquidGlass`
calls needed; compiling against iOS 26 SDK is sufficient.

`FaviconView` (`AsyncImage`, fallback `"link"` SF Symbol, `RoundFaviconModifier`
a 16×16 icon with 4pt corners on an 18×18 always-light background so icons designed
for white backdrops stay legible in dark mode) loads favicons from the configured Stash instance's cached
endpoint (`GET /api/v1/favicons/:domain`, §9.8) keyed by the bookmark's domain —
no longer Google directly. A 404 (uncached domain) falls back to the placeholder.

`BookmarkRowView` shows first three tags + `+N` overflow (not a scrolling row —
avoids gesture conflict in lists). Tags render as `TagPill`s that display a
hierarchical tag as `swift › server` (middot `›`, U+2023), mirroring the web —
presentation only; the stored tag and `tag=` filter keep the raw `swift/server`
slug.

`AddBookmarkSheet` — paste button (`PasteButton`, no `UIKit`), metadata fetch,
and tag editing via `TagPickerSheet`. The form shows a read-only tag summary
(capsule `TagPill`s, or a muted "No tags") plus an "Add Tags" button that
presents `TagPickerSheet` — a sheet over the always-expanded, indented
hierarchical tag tree with single-tap toggle and search-as-create (the search
field doubles as new-tag input: when the normalized query matches no existing
tag a `+ Create "…"` row adds it without closing the sheet). `TagSuggestionView`
autocomplete chips are retained only for `SmartViewFormView`'s single-tag
condition field.

Each bookmark row carries a context menu (and the detail view an actions
section) with a native **Share…** (`ShareLink(item: bookmark.url)`, sharing the
URL) placed after the Copy actions and before Archive.

Context-aware empty states: `ContentUnavailableView.search` for active query,
tag-specific, archived-specific, first-run.

### Account settings (iOS)

`SettingsView` reaches the shared `AccountSettingsView` (change password, enrol /
disable 2FA — the same screen the macOS Settings window uses) via a navigation link
on iPhone and a sidebar toolbar button on iPad. `AccountSettingsView` and
`QRCodeView` are cross-platform; only window-chrome sizing is `#if os(macOS)`-guarded.

`SettingsView` also carries a **Reading** section with two controls. **Browser** (a
picker: **In-App** — the default — or **Default Browser**) decides where a tapped
bookmark link opens: In-App presents the page inside the app in an
`SFSafariViewController` (Apple's recommended in-app browser); Default Browser hands
off to the system browser (the prior behavior). **Reader** (a toggle, default off)
opens supported in-app pages directly in Safari's Reader mode
(`SFSafariViewController.Configuration.entersReaderIfAvailable`); it applies only to
in-app browsing and is disabled when Browser is set to Default Browser. Both
preferences are stored in the App Group `UserDefaults` suite, and the interception is
centralized: an `openURL` environment override (`.inAppBrowser()`, applied to the
bookmark `NavigationStack`s) routes `http`/`https` opens to an in-app Safari sheet, so
it covers every open site — the detail-page URL `Link`, the "Open in Browser" button,
and the row context menu — without editing those shared views. **iOS/iPadOS only**;
macOS has no `SFSafariViewController` and always uses the default browser.

### Smart View management (iOS + macOS)

`SettingsView` also links to a shared `SmartViewManagementView` (a macOS Settings
tab) that lists the user's Smart Views with create / edit / delete. Creating and
editing use a shared `SmartViewFormView` sheet — a name, an All / Any match-mode
picker, and a list of condition rows whose value editor adapts to the condition
type (text, a tag field with autocomplete chips, a date picker, or a Yes/No
picker). Date conditions are serialized as full ISO-8601 (`…T00:00:00Z`), since the
JSON API — unlike the web form — does no date normalization. Deletes confirm. The
sidebar Smart Views section stays browse-only; because the shared
`SmartViewRepository` cache updates on every write, sidebar entries reflect edits
and deletes live.

---

## 17. macOS App ✅ Complete (M10)

macOS 26.0 is a destination of the **single multiplatform `Stash` target** (not
a separate target) — the one `@main App` branches per platform with `#if
os(macOS)`. Adopts the macOS 26 design language (Liquid Glass) automatically by
building against the SDK; no explicit modifiers.

- **Navigation:** `NavigationSplitView` with a sidebar that has a **Views**
  section (All Bookmarks, Untagged, Today, This Week), an optional **Smart Views**
  section (one entry per Smart View, shown only when the user has any), and a
  **always-expanded, indented hierarchical tag tree** (a flattened `ForEach`,
  mirroring the web sidebar) driving the shared `BookmarkListView` in the detail column; selecting a
  bookmark pushes the shared `BookmarkDetailView`. I didn't build an optional
  inspector panel — the shared list already gets you there with less code to
  maintain. **Drag a bookmark row onto a tag** in the sidebar to add that tag to
  the bookmark (shared with iPad).
- **Window:** standard `WindowGroup`, 800×500 minimum
  (`windowResizability(.contentMinSize)`).
- **Bookmarks:** shared list and rows; right-click context menu (Open in
  Browser, Copy URL, Copy Markdown URL, Share…, Archive/Unarchive, Delete); add
  and edit via shared sheets; delete with confirmation. The detail view's actions
  section carries the same Copy and Share… actions (Share… is a native
  `ShareLink` sharing the bookmark URL, placed after Copy and before Archive).
  Tags render as `TagPill`s showing `swift › server` (middot `›`, U+2023),
  mirroring the web; the stored tag keeps the raw slash slug. Tag editing on the
  add/edit sheets uses the shared `TagPickerSheet` (read-only `TagPill` summary +
  "Add Tags" button → the always-expanded tag tree with single-tap toggle and
  search-as-create).
- **Settings scene (⌘,):** General (server URL, sign out), Account (change
  password, 2FA enrol / disable), Smart Views (create / edit / delete — the shared
  `SmartViewManagementView`), Appearance (Light / Dark / Auto, stored in
  `UserDefaults` — no theme cookie on native).
- **Keyboard shortcuts:** ⌘N new, ⌘E edit, ⌘R sync (triggers an offline-sync
  cycle), ⌘⌫ delete (with confirmation), and **Esc** to leave the bookmark
  detail and return to the list (the same binding ships on iOS/iPadOS, where it
  fires only when a hardware keyboard is attached — there is no on-screen Esc).
- **Share Extension:** the single multiplatform `StashShareExtension` target
  serves both platforms (same three states and confirmation-with-undo); only the
  principal controller differs — `MacShareViewController` (`NSViewController`)
  on macOS vs `ShareViewController` (`UIViewController`) on iOS, both
  `#if`-guarded.

---

## 17B. Browser Extension ✅ Complete

A WebExtension that saves the current page to a Stash instance from Firefox or
Chrome (including Zen), living in the top-level `Extension/` folder. It talks
directly to the REST API (`/api/v1/`) — no backend, StashKit, or native-app
changes. Plain HTML + CSS + vanilla JS, no build step (the same philosophy as
the web frontend).

### Structure

```
Extension/
├── manifest.json     # WebExtension manifest v3 (Firefox + Chrome)
├── background.js     # Service worker — token storage, refresh, API calls
├── popup.html/.js/.css   # Toolbar button popup (add-bookmark form)
├── options.html/.js/.css # Settings page (server URL, sign in, 2FA)
├── icons/            # 16/32/48/128 PNGs + icon.svg master + generator
└── Makefile          # lint / icons / package / clean
```

Documented in [`Docs/browser-extension.md`](Docs/browser-extension.md).

The extension shares the Stash bookmark-ribbon identity: the 16/32 toolbar-action
icons stay a deep-indigo ribbon on a transparent background (legible on light and
dark toolbars), while the 48/128 add-ons-manager / store icons wear the full
app-icon look — a white ribbon on an indigo `#231468` rounded square — matching the
native apps and the web favicon.

### Supported browsers

Manifest v3, with the background declared as both `service_worker` (Chrome) and
`scripts` (Firefox/Zen) so one manifest serves both engines. Sideloaded via
developer mode
(`about:debugging` on Firefox, `chrome://extensions` → Load unpacked on Chrome);
distributable to the Firefox Add-ons store or Chrome Web Store.

### Behaviour

Clicking the toolbar button opens a popup with the full add-bookmark form,
pre-filled with the active tab's URL (read-only) and title. A "Fetch metadata"
button pulls the server-side title/description (`POST /api/v1/metadata`, filling
only empty fields); tag input offers autocomplete chips from `GET /api/v1/tags`
using the web UI's per-segment prefix rule; "Save" creates the bookmark
(`fetchMetadata: false`). A duplicate URL surfaces inline as "Already saved" with
a link to the existing bookmark; a save confirmation offers a View bookmark link
and auto-closes. No undo (the popup lifecycle is too short), and no "save
another" — the extension saves the page you are on, so there is nothing more to
add for the same tab.

### Authentication

Username + password against `POST /api/v1/auth/login`, with the access/refresh
pair stored in `chrome.storage.local`. The background service worker owns all
token storage and API calls (the popup/options pages communicate with it via
`chrome.runtime.sendMessage`); it decodes the JWT `exp` claim by hand and
silently refreshes within 60 s of expiry and once on any `401`, mirroring the CLI
and iOS app. The 2FA branch (`/api/v1/auth/totp`, `/api/v1/auth/recovery`) is
handled inline on the settings page. `host_permissions: ["<all_urls>"]` is
required because the self-hosted server URL is user-supplied and unknown at build
time.

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
a `v*.*.*` tag: re-runs the backend tests, then builds `linux/amd64` and
`linux/arm64` natively on separate GitHub-hosted runners. I originally
cross-compiled the arm64 build under QEMU, but the emulation crashed the Swift
compiler partway through, so both architectures now build natively instead (see
`DECISIONS.md`). Each arch is pushed by digest, then stitched into one
multi-arch manifest via `docker buildx imagetools create` → tags
`ghcr.io/otaviocc/stash` (`latest` + semver) → creates a GitHub Release with
`docker-compose.yml` attached. `GITHUB_TOKEN` only — no extra secrets. The repo
stays private; the image is made public via a one-time manual setting in the
package settings (there's no API to do it from CI).

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
│   ├── Resources/Views/           # Leaf templates (markup only; CSS/JS live in Public/)
│   ├── Public/css/                # Static stylesheets served by FileMiddleware
│   ├── Public/js/                 # Static scripts served by FileMiddleware
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
| M12.1 | Smart Views on the CLI and native apps (consumption-only: list + run) | ✅ Complete |
| M12.2 | Smart View create / edit / delete in the iOS & macOS apps (Settings) | ✅ Complete |
| M13 | Offline sync (iOS & macOS): SwiftData local store, `SyncEngine` (pull/push, last-write-wins), optimistic writes, connectivity + background refresh, sync-status UI | ✅ Complete |
| M14 | Native tag picker (iOS & macOS): `TagPickerSheet` with always-expanded indented tag tree, single-tap toggle, search-as-create; flat-indented (web-parity) tag trees; drag-a-bookmark-onto-a-tag tagging (iPad & macOS); `swift › server` tag pills; native Share… via `ShareLink` | ✅ Complete |

---

## 21. Known Leaf Gotchas

A few quirks that cost me real debugging time and are worth writing down so I
don't relearn them the hard way:

- `#if(count(x))` does **not** coerce `Int` to `Bool` — `count 0` evaluates
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
- Page content archiving (article text for offline reading) — the native apps do
  sync bookmark data for offline access; saving page contents is out of scope
- Read-later queue or unread state
- Annotations or highlights
- SSO / OAuth
- Menu bar app (macOS)
