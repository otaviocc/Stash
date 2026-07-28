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

### 9.9 Instance (unauthenticated)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/instance` | Public instance chrome — currently just the accent theme |

```json
{
  "accent": {
    "theme": "ocean",
    "light": "#0a84ff",
    "dark": "#409cff"
  }
}
```

Unauthenticated so any client — the login screen, native apps before sign-in,
the CLI — can tint before authenticating. Reads the same app-level cache as the
web `siteChrome()` (§12), so it never hits the database. StashKit has a
matching DTO and request factory, but no client consumes the endpoint yet: the
native apps' first attempt at instance-accent theming was reverted (see
`DECISIONS.md`), and the endpoint is kept for a future redesign.

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

### 11.6 Netscape HTML Importer/Exporter (`identifier: "netscape-html"`)

A Netscape Bookmark File (`<!DOCTYPE NETSCAPE-Bookmark-file-1>`) — the universal browser-export
format (Chrome, Firefox, Safari, Edge), also produced by Raindrop.io's and Pinboard's own "HTML"
export options. The format has no strict XML structure (real exports leave `<DT>`/`<p>` unclosed),
so the importer is a small hand-rolled token scanner over `<A>`/`<H3>`/`<DL>`/`</DL>`/`<DD>`,
dependency-free like `MetadataFetcher`'s HTML handling — no HTML/XML parser library was added.

| Netscape field | Stash field | Notes |
|---|---|------|
| `HREF` | `url` | Required; skip if missing or invalid |
| anchor inner text | `title` | HTML entities decoded |
| `<DD>` line | `description` | Only attaches to the immediately preceding bookmark |
| `ADD_DATE` | `createdAt` | Unix seconds; current time if missing/unparseable |
| folder nesting (`<H3>` + its `<DL>`) | `tags` | One hierarchical tag joined by `/`, e.g. `bookmarks bar/github`. No folder name is special-cased (browsers localize "Bookmarks Bar" etc.) |
| `TAGS="a,b,c"` (non-standard, used by Pinboard/Delicious-style exporters) | `tags` | Merged in alongside the folder tag |

Duplicate URL: update title, description, tags in place. `createdAt` preserved.

The exporter (all bookmarks including archived) is intentionally **flat** — no folders — since
Stash tags are hierarchical *and* multi-valued per bookmark, while a Netscape file's folders are a
strict single-parent tree; there's no lossless way to place a multi-tagged bookmark into one
folder. Every bookmark's full tag set is instead written into the `TAGS` attribute, which the
importer above reads back losslessly on a round-trip. `isArchived` and Smart Views are dropped, same
as the Anybox exporter (§11.5).

```html
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><A HREF="https://example.com" ADD_DATE="1735689600" TAGS="topic/swift,ios">Example</A>
    <DD>A description
</DL><p>
```

`Content-Disposition: attachment; filename="stash-export-YYYY-MM-DD.html"`, `Content-Type: text/html`.

### 11.7 Raindrop.io CSV Importer/Exporter (`identifier: "raindrop-csv"`)

Raindrop.io has no JSON export in its UI (only HTML, CSV, TXT). Raindrop documents the CSV columns
it both produces and accepts back as `folder,url,title,note,tags,created`
(help.raindrop.io/import#csv), but a full-account export may carry extra columns from Raindrop's
richer API object model (`id`, `cover`, `highlights`, `favorite`, …) — so columns are matched **by
header name** (case-insensitively, with aliases), and any unrecognized column is ignored rather
than rejecting the file, following the same "tolerate shape variance" convention as the Anybox
importer (§11.2).

| Raindrop column (aliases) | Stash field | Notes |
|---|---|------|
| `url` (`link`, `href`) | `url` | Required; skip if missing or invalid |
| `title` | `title` | Empty string if missing |
| `note` (`excerpt`, `description`) | `description` | |
| `tags` | `tags` | Comma-separated (Raindrop's own convention); split on comma only, not whitespace, so a tag containing a space survives |
| `folder` (`collection`) | `tags` | Raindrop already uses `/` to nest folders, the same separator Stash uses for hierarchical tags, so the whole path becomes one additional tag as-is |
| `created` | `createdAt` | Unix seconds or ISO-8601 (both documented as accepted by Raindrop itself) |

Duplicate URL: update in place. `createdAt` preserved.

The exporter (all bookmarks including archived) uses the exact column layout Raindrop documents
accepting back, for the best round-trip fidelity into Raindrop itself. `folder` is left empty:
Stash has no folder concept, and Raindrop has no hierarchical-tag concept, so a Stash tag like
`topic/swift` is written as-is into `tags` rather than guessing a single "primary" folder for a
bookmark that may carry several tags. `isArchived` and Smart Views are dropped, same as the Anybox
exporter.

```csv
folder,url,title,note,tags,created
,https://example.com,Example,A description,"topic/swift, ios",2026-01-01T00:00:00Z
```

`Content-Disposition: attachment; filename="stash-export-YYYY-MM-DD.csv"`, `Content-Type: text/csv`.

### 11.8 Pinboard JSON Importer/Exporter (`identifier: "pinboard-json"`)

Pinboard's export (`Settings → Backups → JSON`, backed by `GET /v1/posts/all?format=json`) is a
flat top-level array using Pinboard's Delicious-legacy field names.

| Pinboard field | Stash field | Notes |
|---|---|------|
| `href` | `url` | Required; skip if missing or invalid |
| `description` | `title` | Pinboard's field for the page title, not a description |
| `extended` | `description` | Pinboard's actual description field |
| `tags` | `tags` | A single space-separated string (Pinboard tags may not contain whitespace) |
| `time` | `createdAt` | ISO-8601 |
| `shared`, `toread` | — | Read and discarded: Stash has no public-sharing or read-later/unread concept (§22, Out of Scope) |

Duplicate URL: update in place. `createdAt` preserved.

The exporter (all bookmarks including archived) writes Pinboard's field names so the file is
importable by Pinboard itself and by the many tools that already speak this shape. `shared`/`toread`
are always written as `"no"`. `isArchived` and Smart Views are dropped, same as the Anybox exporter.
Known lossy edge case: a Stash tag containing a literal space (rare, but not disallowed) would not
survive a round-trip, since Pinboard's `tags` field is space-separated.

```json
[
  {
    "href": "https://example.com",
    "description": "Example",
    "extended": "A description",
    "tags": "topic/swift ios",
    "time": "2026-01-01T00:00:00Z",
    "shared": "no",
    "toread": "no"
  }
]
```

`Content-Disposition: attachment; filename="stash-export-YYYY-MM-DD.json"`.

