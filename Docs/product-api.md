# Stash PRD: API, Metadata Fetching, Import & Export (§9\u201311)

_Part of the Stash Product Requirements Document. See [`PRODUCT.md`](../PRODUCT.md) for the index._

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
| `GET` | `/api/v1/auth/totp/setup` | Begin 2FA enrollment |
| `POST` | `/api/v1/auth/totp/verify-setup` | Confirm enrollment; returns recovery codes |
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
| `POST` | `/api/v1/bookmarks/:id/wayback` | Submit (or re-submit) to the Internet Archive; `202` on success, `409` if disabled instance-wide |

**`GET /api/v1/bookmarks` query parameters:**

| Parameter | Description |
|-----------|-------------|
| `q` | Full-text search (URL, title, description, tags). Case-insensitive on both SQLite and PostgreSQL via `lower(column) LIKE lower(term)`. |
| `tag` | Prefix filter. `swift` matches `swift` and `swift/*` but not `swiftui`. Special values: `__untagged__` returns bookmarks with no tags; `__today__` / `__this_week__` return bookmarks created since the start of the day / the most recent Monday. |
| `archived` | Default false. Pass `true` for archived bookmarks. |
| `page` / `per` | Pagination. `per` clamped 1-100. |

**Offline-sync endpoints** (consumed by the native apps; see `DECISIONS.md` →
Offline Sync):

- **`GET /api/v1/bookmarks/changes?since=<ISO8601>&page=&per=`**: a
  `Page<Bookmark>` of all bookmarks (**archived included**) with `updatedAt >
  since`, sorted ascending by `updatedAt`. `per` defaults to 100, clamped 1-500.
  Omitting `since` returns every bookmark (initial full sync). A malformed `since`
  is a `validation_failed` 422.
- **`GET /api/v1/bookmarks/deleted?since=<ISO8601>`**: a flat array of tombstones
  `[{ "id": "<deleted bookmark id>", "deletedAt": "<ISO8601>" }]` for bookmarks
  hard-deleted after `since`, sorted ascending by `deletedAt` (no pagination).
  Omitting `since` returns all tombstones. Every hard delete, via the API or the
  web frontend, single or bulk, records a tombstone so an offline client learns
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
- Bookmarks are never deleted, only their tags
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
type with a non-empty (and, for dates, ISO-8601-parseable) value; otherwise
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
| `GET` | `/api/v1/admin/sessions` | List every live session (admin + app), optional `q` username filter |
| `POST` | `/api/v1/admin/sessions/revoke-all` | Revoke every active session and refresh token instance-wide |
| `POST` | `/api/v1/admin/sessions/revoke-user` | Revoke one user's sessions and refresh tokens (body: `userName`) |

**Active Sessions** reads and mutates Vapor's in-memory session store directly, so it
covers both the admin dashboard and the `/app` frontend with no new table or
per-session tracking hooks. It can't show IP address, user-agent, or session
creation time — the in-memory driver doesn't capture them, only who's signed in and
where. Revoking deletes the affected refresh tokens too, so JSON API access dies
alongside the web session.

### 9.8 Favicons

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/api/v1/favicons/:domain` | None | Serve the cached favicon image for a domain |
| `POST` | `/api/v1/favicons/:domain/refresh` | Any active user | Delete the cached row and trigger a re-fetch |

- `GET` is **unauthenticated** so `<img>` tags can load it without attaching
  credentials. A `cached` row returns the image bytes with its stored
  `Content-Type` and `Cache-Control: public, max-age=2592000, immutable` (30
  days). A `failed`, `pending`, or missing row returns `404 not_found`; the web
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
5. On any failure: save proceeds with client-supplied values, never blocks

Timeout: 5 seconds. No retry.

**Favicon fetching is decoupled** from this per-bookmark metadata fetch. The
metadata fetch still discovers the page's declared `<link rel="icon">`, but
favicon *caching* now happens at the domain level (§7.8): on bookmark creation
Stash hands that declared icon (when available) to a detached `FaviconFetcher`
keyed by domain, rather than storing a per-bookmark `faviconURL`. See §7.8 and
the Favicon Caching section of `DECISIONS.md`.

**Native clients fetch metadata on-device.** The iOS/macOS app and Share
Extension don't call `POST /api/v1/metadata` for the add-bookmark preview;
they run the same regex parser locally (`ClientMetadataFetcher`, a verbatim
port of the backend's `MetadataFetcher`), fetching the target page directly.
That way metadata still shows up even when the Stash backend is unreachable
(say, away from the home-lab network), with no round-trip and no timeout
delay. The `/api/v1/metadata` endpoint remains for the web UI and the browser
extension. Favicon *caching* is unaffected; it still happens server-side,
keyed by domain, when the bookmark reaches the backend (on create/sync),
regardless of where the title/description preview came from.

---

## 11. Import & Export

### 11.1 Architecture

Pluggable `ImportExportRegistry`. New formats: conform to protocol, register in
`init`, no controller, route, or template changes needed.

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

- `tags` is `[[String]]`: arrays of `[namespace, value]` pairs (e.g.
  `[["topic","swift"],["status","reading"]]`). Each pair joined with `/` →
  hierarchical Stash tag (`topic/swift`). Plain `[String]` accepted as fallback.
- `dateAdded`: camelCase, ISO-8601 string. Numeric `date_added`/`dateAdded`
  accepted as fallback. Missing → current time.

| Anybox field | Stash field | Notes |
|---|---|------|
| `url` | `url` | Required; skip if missing or invalid |
| `title` | `title` | Empty string if missing |
| `description` | `description` | |
| `tags` | `tags` | Normalized |
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
| `bookmarks[].tags` | Normalized |
| `bookmarks[].isArchived` | |
| `bookmarks[].faviconURL` | |
| `bookmarks[].createdAt` | ISO-8601; current time if missing |
| `smartViews[].name` | Required; ≤ 100 chars |
| `smartViews[].matchMode` | `all`/`any`; defaults to `all` |
| `smartViews[].conditions` | At least one valid `{ type, value }`; same validation as the API |
| `id`, `updatedAt`, `version`, `exportedAt` | Ignored (also `smartViews[].id`/`createdAt`/`updatedAt`) |

Duplicate URL: update in place. `createdAt` preserved. The `smartViews` node is optional, so
older exports without it still import. A Smart View whose `name` already exists for the user is
updated in place; otherwise it is created, so re-importing is idempotent. A Smart View with an
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

### 11.5 Anybox JSON Exporter (`identifier: "anybox"`)

The inverse of the Anybox importer (§11.2): all bookmarks (including archived),
sorted by `createdAt` ascending, written as a flat top-level JSON array. It is
intentionally lossy — Anybox has no concept of archived bookmarks or Smart
Views, so `isArchived` is dropped and Smart Views are omitted.

| Stash field | Anybox field | Notes |
|---|---|------|
| `url` | `url` | |
| `title` | `title` | |
| `description` | `description` | Omitted when empty |
| `tags` | `tags` | Plain `[String]` (e.g. `["topic/swift", "ios"]`); the importer's documented fallback shape, so a Stash → Anybox → Stash round-trip preserves tags |
| `createdAt` | `dateAdded` | ISO-8601 string |
| `isArchived` | — | Dropped (Anybox has no archive) |
| Smart Views | — | Omitted (Anybox has no equivalent) |

```json
[
  {
    "url": "https://example.com",
    "title": "Example",
    "description": "...",
    "tags": ["topic/swift", "ios"],
    "dateAdded": "2026-01-01T00:00:00Z"
  }
]
```

