# Stash PRD: Web Admin Dashboard & Web Frontend (§12\u201313)

_Part of the Stash Product Requirements Document. See [`PRODUCT.md`](../PRODUCT.md) for the index._

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
| Health | `/admin/health` |
| Maintenance | `/admin/maintenance` |
| Favicon Cache | `/admin/favicons` |
| Internet Archive | `/admin/internet-archive` |
| Audit Log | `/admin/audit` |
| Active Sessions | `/admin/sessions` |
| System Logs | `/admin/logs` |
| Backup & Restore | `/admin/backup` |

### Business Rules

- Accounts always created as `user` role
- Admin cannot delete own account (button hidden + POST blocked → 400)
- Admin cannot suspend own account (button hidden + POST blocked → 400)
- Suspend and password reset invalidate all refresh tokens
- 2FA reset: clears secret + recovery codes + invalidates refresh tokens
- Post/Redirect/Get with `?ok=` confirmation banners
- HTML forms use POST sub-routes for destructive actions (suspend, delete, etc.)
- Nav is trimmed to Dashboard, Users, and App (always shown; every admin also
  has a regular bookmark collection, so App is never a dead end). Every other
  admin page (New user, Appearance, Audit log, Sessions, Health, Maintenance,
  Favicons, Internet Archive, Logs) is reached via a Dashboard card, not the
  top nav — see the Dashboard bullet below.
- The Dashboard (`GET /admin`) is the admin hub: a KPI stat strip (total users
  with an active/suspended split, total bookmarks, live web sessions, and the
  Internet Archive queue depth), a grid of navigation cards — one per other
  admin page, each with a one-line description and a cheap live detail where
  one exists (e.g. Favicons shows cached/pending counts, Internet Archive
  shows queued count or "Disabled") — and a recent-activity feed (the last 8
  audit-log rows, most recent first, reusing the same row shape as the Audit
  Log page). The old per-user table was dropped from the dashboard; it lives
  only on the dedicated Users page.
- The Appearance page (`GET`/`POST /admin/appearance`) edits the instance
  `SiteSettings` (§7.6): accent theme (twenty-three circles, pure-HTML radios), the
  about message (max 280 chars), and up to four editable footer links (label +
  URL pairs, all URLs validated for `https://`). Each theme circle previews the
  color for the active mode: its light value in light mode, its dark value in
  dark mode, matching what the app actually renders. Empty link slots (both
  label and URL empty) are hidden from the footer. Invalid input → 422 with the
  form re-rendered; on success the app-level cache is refreshed and PRG
  redirects with `?ok=saved`.
- The Health page (`GET /admin/health`) is mostly a read-only operational
  view: the running version string, a live database connectivity probe with
  the active driver name (Postgres/SQLite), process uptime since boot, disk
  usage for the working directory, and total user/bookmark counts. It is
  deliberately separate from the public, unauthenticated `GET /health`
  liveness probe (§9), which stays a minimal `{ "status": "ok" }` for
  monitors and orchestrators; this page is the human-facing admin-only
  equivalent. It also carries an **Updates** card: once a day (and whenever
  the dashboard or this page is loaded, if the cached result has gone stale)
  Stash checks GitHub Releases for a newer version than the one running,
  showing an "update available" state with the latest version and a release
  notes link, an up-to-date state, or a check-failed state, plus a
  "Check now" button (`POST /admin/health/check-updates`) and an
  enable/disable toggle (`POST /admin/health/toggle-updates`,
  `SiteSettings.updateCheckEnabled`, default on) for fully offline/air-gapped
  instances. A container can't update itself, so an available update just
  shows the same `docker/podman compose pull && up -d` upgrade command
  documented in `Docs/backend-docker.md`. The dashboard also shows a
  same-banner summary when an update is available.
- The Maintenance page (`GET /admin/maintenance`) has a single "Run database
  optimize" button (`POST /admin/db/optimize`) that runs a plain `VACUUM`
  against the configured database, reclaiming dead-tuple space left behind by
  hard deletes (single bookmark delete, the "delete all bookmarks" danger
  zone, and admin user-deletion cascades). It does not lock tables and is
  safe to run at any time; no confirmation dialog is needed, unlike the
  destructive user actions elsewhere on the dashboard. PRG redirects with
  `?ok=db_optimized&ms=<elapsed>`, and the elapsed time is shown in the
  success banner. Nothing about past runs is persisted.
- The Favicon Cache page (`GET /admin/favicons`) shows `favicon_cache` stats
  (total/cached/pending/failed counts, total bytes cached) and two bulk
  actions: "Clear favicon cache" (`POST /admin/favicons/clear`, deletes every
  row, `confirm()` dialog since it's a quick-to-recover action, not the typed
  danger-zone pattern) and "Re-scan all favicons" (`POST /admin/favicons/rescan`,
  re-fetches every domain used by any bookmark plus any domain still in the
  cache, so it can rebuild from scratch after a clear; re-fetches run
  sequentially, one at a time, to avoid bursting external favicon providers).
  A cleared favicon does **not** silently regenerate just by viewing a
  bookmark; it comes back via re-scan, a new bookmark saved for that domain,
  or that bookmark's own "Refresh favicon" button.
- The Internet Archive page (`GET /admin/internet-archive`) shows Wayback
  Machine submission stats across every bookmark on the instance (total,
  archived, queued/pending, failed, not-yet-submitted counts), an on/off
  switch for `SiteSettings.internetArchiveEnabled` (default on; `POST
  .../toggle`), and two bulk actions: "Retry failed" (`POST
  .../retry-failed`, re-queues every `failed` bookmark) and "Queue all"
  (`POST .../queue-all`, submits every not-yet-submitted or failed
  bookmark; `confirm()` dialog since it can touch the whole library).
  Submissions always run through the same serial background queue, one at
  a time, to respect the Internet Archive's rate limits. When the switch is
  off, no bookmark can be submitted anywhere in Stash: auto-submit, the
  detail-page button, the API, and both bulk actions all refuse (the bulk
  actions PRG with a `?error=internet_archive_disabled` banner rather than
  silently re-queueing), and the "View"/"Save to Wayback Machine" buttons
  don't appear on the bookmark detail page (§13). Toggling the switch is
  audited as its own distinct action (`internet_archive_toggled`), not
  folded into the accent-theme/appearance audit action. The page also shows
  a live queue-status line (idle/nothing queued, paused with a pending
  count, submitting a specific URL, running at the normal pace, or
  rate-limited and retrying with an attempt count) plus a "Resume queue
  now" button that nudges the background worker (a safe no-op if it's
  already running); toggling the switch off stops the drain loop
  immediately — mid-flight, not just for future submissions — leaving any
  still-`pending` bookmarks untouched until re-enabled or manually resumed.
- The Audit Log page (`GET /admin/audit`) shows the most recent 50 rows of
  the audit trail (§7.9): auth events and admin user-management actions, most
  recent first. No pagination, filtering, or export in v1.
- The Active Sessions page (`GET /admin/sessions`) lists every live web
  session — both the admin dashboard and the `/app` frontend — reading
  directly from the in-memory session store (§9.7). An admin can revoke every
  session instance-wide (`POST /admin/sessions/revoke-all`) or just one
  user's (`POST /admin/sessions/revoke-user`), both of which also delete the
  affected refresh tokens. Revoking the admin's own current session correctly
  signs them out immediately rather than leaving their dashboard session
  silently resurrected. Supports a username filter (`?q=`); no IP,
  user-agent, or session-creation time is shown, since the in-memory driver
  doesn't capture them.
- The System Logs page (`GET /admin/logs`) reads from a fixed-capacity
  (1000-entry) in-memory ring buffer fed by every log call app-wide, cleared
  on restart and never written to disk or the database — a quick-triage
  convenience, not a replacement for `docker logs`/`podman logs`. A `?level=`
  filter narrows to a minimum severity (`info`, `warning`, or `error`); any
  other value is treated as no filter, so the rendered dropdown selection
  never diverges from what's actually shown. Notable activity is emitted at
  `info` (visible under the default/`info` filter): bookmarks saved, deleted,
  and bulk-deleted (delete all); Smart View and tag created/renamed/deleted;
  favicons cached or failed to cache; and bookmarks successfully archived to
  the Wayback Machine. Auth (login/logout) and admin user-management actions
  are deliberately *not* duplicated here — they already live in the DB-backed
  Audit Log (`/admin/audit`, §7.9).
- The Backup & Restore page (`GET /admin/backup`) covers full-instance
  disaster recovery/migration, distinct from the per-user Stash JSON
  export/import under `/app/settings` (§11). "Download instance backup"
  (`GET /admin/backup/download`) streams one JSON file with every account
  (username, password hash, TOTP secret, recovery-code hashes, role, active
  state, and the archive-new-bookmarks preference — so restoring keeps
  everyone's logins and 2FA working), their bookmarks and Smart Views, and
  the site's appearance settings (including footer links); it deliberately
  excludes refresh tokens (everyone simply signs back in), the favicon cache
  (regenerable), and the audit log (operational history, not user data). "Restore backup" (`POST
  /admin/backup/restore`, gated behind typing "restore" to confirm, the same
  typed-confirmation pattern as the danger-zone bulk delete) merges the file
  into the running instance keyed by username: an existing account's
  bookmarks/Smart Views are merged in (never deleted) while its own
  password/2FA/role/active state is left untouched, and a username not
  already present is created with its backed-up auth material written
  verbatim. Old backup files with the legacy `footerCustomLabel`/`footerCustomURL`
  fields are handled gracefully: the legacy values are migrated into the
  fourth footer link slot on restore. The currently signed-in admin's own
  account is therefore never modified by a restore, since it always already
  exists. Because the file
  carries password hashes and TOTP secrets, it's treated as sensitive
  throughout the UI, the same way a database dump would be.

---

## 13. Web Frontend (`/app`)

Session-based auth (`stash_session` cookie, path `/app`, in-memory,
SameSite=Lax). Any active user role can log in. Sessions don't survive a
container restart.

Every web page (`/app`, `/admin`, landing, and login) carries the Stash favicon:
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
  active search and tag filter; toggling archive on a filtered view shows that
  tag's archived items rather than dropping the filter, matching the native apps
- Pagination with prev/next links preserving active filters
- Two-column layout: bookmark list (left/main) + tag sidebar (right, 220px)
- Mobile (<768px): sidebar hidden, filter pills used instead
- Each row (and the detail page title) shows the domain's cached favicon via
  `<img src="/api/v1/favicons/{domain}">` (§7.8, §9.8), with an `onerror` handler
  that swaps to a static ribbon placeholder (`/favicon-placeholder.svg`) on a
  `404`, never a broken-image glyph. The `{domain}` is computed server-side
  per row.

### Bookmark Detail

- Actions are grouped rather than shown as one flat row of buttons, mirroring
  the native apps' sectioned list (§14): a top row with only the two most
  common actions (Open URL, Edit), an "Actions" card below listing the rest
  (Refresh favicon, View/Save to Wayback Machine, Archive/Unarchive) as
  stacked full-width rows — each conditionally shown per the same rules as
  before (favicon present, Internet Archive enabled, etc.) — and a separate
  "Danger zone" card (reusing the `.danger-zone` styling from Settings/admin
  User Detail) containing only Delete, so the destructive action is visually
  set apart rather than sitting in the same row as everything else.

### Favicons

- Served from Stash's domain-keyed cache (§7.8), not fetched from the origin site
  or Google by the browser. Computed once per domain at bookmark creation.
- The bookmark detail page (`/app/bookmarks/:id`) carries a small "Refresh
  favicon" button that POSTs to `/app/bookmarks/:id/refresh-favicon` (a thin
  session-auth wrapper that triggers the same re-fetch as the API's
  `POST /api/v1/favicons/:domain/refresh`). PRG redirects back with a
  `?ok=favicon_refreshing` banner ("Favicon refresh started. It may take a
  moment to update.").

### Internet Archive

- Only shown when the admin has Internet Archive submissions enabled
  instance-wide (§12); hidden everywhere (this button, the settings toggle
  below) when the admin has turned it off.
- The bookmark detail page (`/app/bookmarks/:id`) carries a "View on Wayback
  Machine" link, shown only once `waybackURL` is set (i.e. `waybackStatus ==
  archived`), pointing directly at the captured snapshot, and a "Save to
  Wayback Machine" button that always submits (or re-submits, capturing a
  fresh snapshot with the current date) regardless of the user's own
  auto-submit preference. The button POSTs to
  `/app/bookmarks/:id/save-to-wayback` and PRG redirects back with a
  `?ok=wayback_started` banner, or `?error=internet_archive_disabled` if the
  admin turned the instance switch off between page load and submit (the
  button itself is hidden on a fresh page load in that case, so this is a
  stale-page/direct-request edge case, not something normal navigation hits).
- New bookmarks auto-submit at save time only when both the instance switch
  and the user's own preference (Settings, below) are on.

### Tag Sidebar

- Right column, plain flex; scrolls with the page as one unit (no fixed/sticky
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
  or a split pill (accent "visible" left half, muted "hidden" (archived) right
  half) when the tag has archived bookmarks, so a tag whose bookmarks are all
  archived still appears (e.g. `0|5`). Synthetic parents and tags with no
  bookmarks show no badge.
- Active tag highlighted with accent color
- Aligned with the search bar via `margin-top`

### Add / Edit Bookmark

- Add form is two-step: "Fetch metadata" previews server-side; "Save" persists
- Add form accepts an optional `?url=` query parameter that pre-populates the
  URL field (e.g. `/app/bookmarks/new?url=https://example.com`). It only
  pre-fills; the user must still click "Save"; nothing is added automatically.
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
  bookmark), no inline reveal, so the table never re-renders in place
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

**Two-Factor Authentication:** enroll (QR via `otpauthURI` + manual key), disable
(requires current TOTP code; recovery codes shown once with "I've saved these"
confirmation).

**Internet Archive:** a checkbox, "Send new bookmarks to the Internet Archive"
(`archiveNewBookmarks`, default on), only shown when the admin has Internet
Archive submissions enabled instance-wide (§12). `POST
/app/settings/archive-pref` saves it and PRG redirects with `?ok=archive_pref`.
Turning this off doesn't affect existing submissions or remove the per-bookmark
"Save to Wayback Machine" button on the detail page (§13, Internet Archive) —
it only controls whether *new* bookmarks auto-submit at save time.

**Import & Export:**
- Import: file upload, format selector (Anybox JSON, Stash JSON), summary banner
  with imported/updated/skipped counts (plus a Smart Views count when the file
  carried any), collapsible error details. Upload body limit 16MB. A Stash JSON
  file also restores Smart Views, matched by name. After a successful import a
  detached backfill caches a favicon (§7.8) for each distinct imported domain.
- Export: "Download your bookmarks" → Stash JSON file download (bookmarks and
  Smart Views).

**Danger Zone:**
- "Delete all bookmarks": requires typing `delete all` (case-insensitive).
  Verified server-side. Resets `bookmarkCount` to 0. Redirects to `/app` with
  flash banner.

### Dark Mode

Three-way CSS resolution:
- `:root` → light values
- `[data-theme="dark"]` → explicit dark
- `@media (prefers-color-scheme: dark) :root:not([data-theme])` → auto

Inline flash-prevention script at top of `<head>` sets `data-theme` from
`stash_theme` cookie before first paint, no flash. Applies to both `/app` and
`/admin` (shared `layout.leaf`). iOS-style palette: bg `#1c1c1e`, surface
`#2c2c2e`, accent `#0a84ff`, danger `#ff453a`, success `#30d158`.

