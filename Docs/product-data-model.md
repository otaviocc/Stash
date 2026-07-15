# Stash PRD: Data Model (§7)

_Part of the Stash Product Requirements Document. See [`PRODUCT.md`](../PRODUCT.md) for the index._

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
| `bookmarkCount` | Int | Denormalized; updated on bookmark create/delete |
| `archiveNewBookmarks` | Bool | Default true. Auto-submit new bookmarks to the Internet Archive; see §7.2. |
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
| `isArchived` | Bool | Default false. Stash's own archive/inbox flag, unrelated to `waybackStatus` below. |
| `waybackStatus` | Enum | `none` (default), `pending`, `archived`, or `failed`. Internet Archive (Wayback Machine) submission state. |
| `waybackURL` | String? | The captured snapshot's URL, set once `waybackStatus` is `archived` |
| `waybackArchivedAt` | Date? | When the snapshot was last captured |
| `createdAt` | Date | Auto-set |
| `updatedAt` | Date | Auto-updated |

**Duplicate URL constraint:** unique index on `(userID, url)`. API returns HTTP
409 Conflict if a duplicate is attempted.

**Internet Archive submission.** A bookmark can be submitted to the Wayback
Machine (`web.archive.org`), anonymously (no API credentials), through a
persisted, single-serial background queue: a bookmark is enqueued by flipping
`waybackStatus` to `pending`, and a queue worker submits one at a time (30s
pace), setting `archived` + `waybackURL` on success or `failed` on a genuine
error. A `429` (the anonymous endpoint's rate limit; observed in practice to
be common from server/datacenter IPs) is treated as transient rather than
terminal: the bookmark stays `pending` and is retried automatically after a
longer backoff, rather than requiring a manual "Retry failed" — up to 3
consecutive rate-limited attempts, after which the bookmark gives up and
falls back to `failed` like any other error, so one persistently
rate-limited bookmark can't block every other bookmark queued behind it
forever. Auto-submission
on save requires both the admin's instance-wide switch (`/admin/internet-archive`,
§7.6, default on) and the user's own preference (`archiveNewBookmarks`, §7.1,
default on) to be enabled; a manual "Save to Wayback Machine" submission (or
re-submission, capturing a fresh snapshot) bypasses the user preference but
still requires the instance switch to be on. See §9.3 and §12.

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

Eight codes generated at 2FA enrollment. Deleted when 2FA is disabled or reset.

### 7.5 Tags

Tags are plain strings stored on each bookmark. Hierarchical tags use slash
notation, like `swift/vapor`. I derive the tag tree dynamically per user rather
than keeping a separate tags table.

A derived `tagsSearch` column stores tags as `|swift|swift/vapor|` so prefix
matching can happen with a plain SQL `LIKE`, the same behavior on SQLite
(tests) and PostgreSQL (production).

Querying `tag=swift` matches bookmarks where `tagsSearch` contains `|swift`,
a prefix match, so it includes `swift` and `swift/*`, but not `swiftui`.

**Tag normalization:** trimmed, lowercased, surrounding slashes stripped,
de-duplicated. Enforced server-side on every write.

### 7.6 Site Settings

Instance-wide customization, managed by the admin. It's a single-row
configuration table (always exactly one row, created on first boot with
default values, never deleted) and cached in the application at startup so
page renders never hit the database.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `accentTheme` | String | Default `"ocean"`. One of the twenty-three theme identifiers. |
| `aboutText` | String? | Optional. Short message shown in the footer. Max 280 chars. |
| `footerLinks` | String | JSON array of up to four `FooterLink` objects (`{ "label", "url" }`). Defaults to GitHub, Mastodon, Ko-fi, and one empty custom slot. All URLs must be `https://`. Empty slots are hidden from the rendered footer. |
| `internetArchiveEnabled` | Bool | Default true. Instance-wide switch for Internet Archive submission; see §7.2 and §12. |
| `updateCheckEnabled` | Bool | Default true. Instance-wide switch for the GitHub Releases update check; see §12. |
| `createdAt` | Date | Auto-set |
| `updatedAt` | Date | Auto-updated |

**Accent themes.** Seventeen named themes, each with a light-mode and a dark-mode hex
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
| `teal` | Teal | `#0d9488` | `#2dd4bf` |
| `coral` | Coral | `#f97316` | `#fb923c` |
| `lavender` | Lavender | `#8b5cf6` | `#c4b5fd` |
| `gold` | Gold | `#eab308` | `#facc15` |
| `apple-music` | Apple Music | `#FC3C44` | `#FC3C44` |
| `spotify` | Spotify | `#1DB954` | `#1DB954` |
| `obsidian` | Obsidian | `#6C31E3` | `#6C31E3` |
| `discord` | Discord | `#5865F2` | `#5865F2` |

The selected theme's values are injected into `layout.leaf`'s `<head>` as a CSS
block overriding `--accent`, from the app-level cache (no per-request query).

### 7.7 Smart View

A named, saved query owned by a user. It stores rules, not results; every time
it's opened the query runs live against the user's bookmarks. `matchMode`
decides how the conditions combine: `all` (every condition must match, AND) or
`any` (at least one, OR), the same idea as macOS Music's "Match all/any of the
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
| `hasTags` | `tagsSearch` is non-empty (`true`) or empty (`false`); i.e. the bookmark has any tags |
| `isWaybackArchived` | `waybackStatus` equals `archived` (`true`), or anything else — `none`/`pending`/`failed` (`false`); i.e. whether the bookmark has a captured Internet Archive snapshot |

Text conditions use the same portable `lower(column) LIKE lower('%value%')` helper
as full-text search. Multiple conditions of the same type are allowed (with
`matchMode: all`, two `tag` conditions = the bookmark must have both tags; with
`any`, either tag matches). The non-archived default is applied as an outer AND in
both modes; results are limited to non-archived bookmarks unless an `isArchived`
condition is present.

The relative-age conditions `olderThan` / `newerThan` carry a compact **duration
string** as their value: a positive integer followed by a unit suffix: `d` (days),
`m` (months), or `y` (years), e.g. `"30d"`, `"3m"`, `"1y"`. The cutoff is computed
from the current time **at query execution, not at Smart View creation** (so "older
than 6 months" stays current as time passes), using calendar arithmetic: `"1m"` is
one calendar month, not a fixed 30 days. They join, and do not replace, the absolute
`createdBefore` / `createdAfter` date conditions.

**Client support.** The web frontend and the native iOS/macOS apps create, edit,
delete, and browse Smart Views. The apps surface them as a browse-only Smart Views
section in the sidebar, and manage them (create / edit / delete) from a Settings →
Smart Views screen. The **CLI is consumption-only**: it lists Smart Views and opens
their live results (`stash smart-views`); authoring on the CLI is done on the web
or round-tripped through Stash JSON import/export.

**Footer.** Shown on every `/app` and `/admin` page via `layout.leaf`. Up to
four editable label+URL links, stored as a JSON array in `footerLinks` (§7.6).
Defaults to GitHub (`https://github.com/otaviocc/Stash`), Mastodon
(`https://social.lol/@otaviocc`), Ko-fi (`https://ko-fi.com/otaviocc`), and one
empty custom slot. Empty slots (both label and URL empty) are hidden from the
rendered footer. All URLs must be `https://`. Also shown: the optional `aboutText`
(above the links) and the version string (read from a `VERSION` file at startup,
`"dev"` if missing). All external links open in a new tab with
`rel="noopener noreferrer"`. The Stash identity (name, logo) is hardcoded and
not configurable; the default links are configurable by the admin.

### 7.8 Favicon Cache

Favicons are cached **per domain** (not per bookmark or per user) and served from
Stash itself instead of relying on the browser fetching from the origin site or
Google on every render. A new bookmark for any URL on an already-cached domain
reuses the existing image; the cache grows with unique domains, not bookmark
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

There's a unique index on `domain`; the insert-then-catch path uses it to
dedupe concurrent first-time fetches for the same domain. Image bytes are
capped at 100KB (rejected via the `Content-Length` header before download when
present), the `Content-Type` must be a non-SVG `image/*` (SVG is refused as
active content), and the served response carries
`X-Content-Type-Options: nosniff`. The bookmark's `faviconURL` field is no
longer written for new bookmarks (domain-keyed lookup at render time supersedes
it) but the column is retained.

### 7.9 Audit Log

A narrow, best-effort admin audit trail: auth events (login success, login failure,
logout) and admin user-management actions (create, suspend, unsuspend, password
reset, TOTP reset, delete, site-appearance changes). Deliberately excludes bookmark,
tag, and Smart View CRUD — too high-volume and low audit value to be worth crowding
the viewer.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `actorUsername` | String? | Username performing the action, or the attempted username on a failed login. `nil` only if none was ever supplied. |
| `action` | String | Slug, e.g. `login_success`, `login_failure`, `logout`, `user_created`, `user_suspended`, `user_unsuspended`, `password_reset`, `totp_reset`, `user_deleted`, `appearance_updated` |
| `detail` | String? | Free-text context, e.g. the target username plus what changed |
| `ip` | String? | Best-effort client IP: `X-Forwarded-For` first, falling back to the raw socket address |
| `createdAt` | Date | Auto-set |

Writes are best-effort and non-throwing from the caller's side: a login or admin
action must never fail because the audit write did. An action that always runs but
doesn't actually change anything (e.g. suspending an already-suspended user, or
resetting TOTP for a user with no 2FA configured) does not write a row — only real
state transitions are logged. Viewed at `/admin/audit`, most recent 50 rows, no
pagination or filtering.

