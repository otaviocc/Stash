# Stash Decisions: Backend (API, migrations, site settings, favicons, admin tools, Internet Archive, instance management)

_Part of the Stash Decision Log. See [`DECISIONS.md`](../DECISIONS.md) for the index and the full list of topical files. Entries are in original chronological order within this file._

---

## M1: Auth foundation

The spec (§17.2) called for `vapor/auth` for "built-in RFC-compliant TOTP,"
but that package is Vapor-3-era: it doesn't exist for, or compile against,
Vapor 4. So I implemented RFC 6238 TOTP and Base32 myself on top of
swift-crypto (already a transitive dependency), in `Sources/App/Auth/`. Keeps
the backend dependency-light too, which fits the whole point of the project.
Everything else in §17.2 is used as listed.

Token strategy: the access token is an HS256 JWT, 15 minutes, carrying a
`scope` claim of `access`. The 2FA step gets its own 5-minute JWT with
`scope = "2fa"`, so a temp token can never be replayed as a real access
token. Refresh tokens are opaque 256-bit hex, stored only as a SHA-256 hash,
90-day expiry, rotated on every use (§8.1).

Passwords and recovery codes both use bcrypt at cost 12 (Vapor's default)
(§8.5). Recovery codes are eight `XXXX-XXXX` codes, normalized (dashes
stripped, uppercased) before hashing or verifying. Login is roughly
constant-time: even unknown usernames run a throwaway bcrypt verify so
response timing doesn't leak whether an account exists.

One thing that cost me about an hour to track down: I named the test boot
helper `withTestApp`, not `withApp`, on purpose. VaporTesting exports its own
generic `withApp`, and a single-expression test closure (just a `.test(...)`
call, say) infers a non-`Void` return and silently resolves to VaporTesting's
overload instead of mine, which skips my explicit `asyncBoot()` and leaves the
responder unbooted. Every route just 404s, with no obvious clue why. Renaming
it prevents that from happening again.

---

## M2: Bookmarks

Tags get stored twice, on purpose: the canonical `tags` field is a `[String]`
that maps to a JSON column so it works identically on SQLite and Postgres, but
hierarchical prefix matching (`tag=swift` matching `swift` and `swift/*`,
§7.5) can't be done portably against a JSON column. So there's a derived
`tags_search` text column holding a pipe-wrapped form (`|swift|swift/vapor|`),
and the filter becomes two portable `LIKE` clauses against it. `tags` stays
the single source of truth; `applyTags` keeps `tags_search` in sync.

I normalize tags on write: trimmed, lowercased, surrounding slashes
stripped, the pipe character removed, de-duplicated. The spec doesn't
explicitly call for lowercasing, but every example in it is lowercase, and
skipping it would fragment the tag tree into `Swift` and `swift` as separate
branches.

A duplicate URL returns 409 with the existing bookmark's id in the error
envelope (§9.3/§17.4), enforced by a pre-check plus a unique
`(user_id, url)` index as a race backstop, so a genuine race between two
concurrent saves still can't slip through.

Metadata fetching stays dependency-free and non-blocking: `MetadataFetcher`
uses Vapor's built-in HTTP client (5s timeout, no retry, §10) and a small
regex parser rather than pulling in a scraping library. It runs inline,
server-side. If it fails for any reason, the save proceeds with whatever the
client supplied (nothing blocks on it), and the title falls back to the URL
when both are blank.

Full-text search (`q`) originally used a plain `LIKE` across URL, title,
description, and tags, which meant it was case-insensitive on SQLite but
case-sensitive on Postgres, a nuance I left documented rather than fixed.
That held until M8, when a real client actually exercised it and I noticed
§9.3 explicitly calls for "ILIKE on PostgreSQL", case-insensitive on both.
So I superseded the original behavior and made it case-insensitive everywhere
(more on the fix itself under M8 below). Tags in `q` go beyond what the spec
asked for ("URL, title, description"); I added that on request, and applied
it consistently to both the API and the web list handlers so they don't
drift apart.

`bookmarkCount` is a denormalized counter on `User`, kept up to date on
bookmark create/delete (§7.1); the `makeBookmark` test helper maintains it
too, so tests see the same reality production would. Pagination uses Vapor's
`Page<T>` (§17.5), with `per` clamped to 1-100.

---

## M3: Admin API

`AdminMiddleware` sits after the access-token authenticator and guard, so an
authenticated non-admin gets a plain 403 rather than anything more exotic.
Along the way I needed a `username_taken` (409) error code that the spec's
code table didn't have; I added it, mirroring the existing `duplicate_url`
pattern.

Accounts are always created with the `user` role; any `role` field in the
create body is ignored. An earlier version of this actually accepted `role`
from the request, which meant a client could in theory create a second
admin; I tightened that so the only way to get an admin account is
first-boot seeding (§4).

Both self-deletion and self-suspension are blocked (`400 cannot_delete_self` /
`400 cannot_suspend_self`): an admin should never be able to lock themselves
out. That's enforced on both the JSON API (a `PUT` with `isActive: false` on
your own id) and the web dashboard, where the "Suspend account" button is
hidden on the signed-in admin's own detail page using the same `isSelf` flag
that hides Delete.

Suspension and admin-triggered password resets both revoke every refresh
token for the account: any change to an account's security posture forces
re-authentication. Hard delete cascades explicitly (bookmarks, then refresh
tokens, then recovery codes, then the user) instead of relying on a database
`ON DELETE CASCADE`, so it behaves identically whether it's running against
SQLite in tests or Postgres in production, regardless of how each enforces
foreign keys. Per-user stats reuse the same denormalized `bookmarkCount` that
`/me` reads, so admin stats and a user's own count never disagree.

---

## M5: Web admin dashboard

The admin dashboard authenticates with a session cookie
(`stash_admin_session`) that's completely separate from the JWT API (§11),
backed by an in-memory session store, fine for a single self-hosted
instance, though it does mean sessions don't survive a restart. It never
touches `/api/v1/*`.

Rather than reach for `ModelSessionAuthenticatable`, I store the admin's user
id as a plain string in the session and reload it in `AdminSessionMiddleware`;
that sidesteps some uncertainty around `UUID: LosslessStringConvertible`.
On any failure (missing session, expired, the account got suspended or
demoted since login), the middleware just redirects to `/admin/login` instead
of returning a JSON error, and calls `req.auth.login` so downstream handlers
can use `req.auth.require` normally.

HTML forms can't issue `PUT`/`DELETE`, so destructive actions like suspend,
reset, and delete are `POST` sub-routes, and a successful one follows
Post/Redirect/Get with a `?ok=` confirmation banner. Web handlers render
error states or redirect rather than throwing, since throwing would emit the
JSON error envelope instead of an HTML page.

One small implementation snag: rendering a response with a non-200 status has
to be built from `view.data` directly, because the async
`View.encodeResponse` overload wasn't resolving cleanly: `req.view.render`
needed an explicit `let view: View = …` type annotation to pick the async
overload at all.

---

## Backend: reorganized `Sources/App/` by surface (API / Web / Core)

The backend source tree used to be organized by kind: `Controllers/`,
`DTOs/`, `Models/`, `Services/`, which meant the JSON-API code and the Leaf
web-UI code were interleaved inside every folder, distinguished only by a
`*WebController`/`*WebDTOs` filename suffix. I switched it to three
top-level buckets instead: `API/` for the JSON `/api/v1` contract the
clients actually depend on (controllers plus wire DTOs, mirroring
`Public/openapi.yaml`), `Web/` for the session-auth Leaf UIs, and `Core/` for
the shared domain both surfaces use, which keeps its existing
kind-based subfolders (`Models/`, `Migrations/`, `Services/`, `Auth/`,
`ImportExport/`, `Extensions/`, `Middleware/`, `Errors/`). Along the way I
also cleaned up a `Services/` grab-bag: three files that weren't actually
services (a version-file reader, a stateless URL→domain parser, and a value
type holding theme palettes) moved into a new `Core/Support/`, leaving
`Core/Services/` holding only genuine services.

This was purely organizational: `App` is a single Swift module, so SwiftPM
compiles everything recursively regardless of folder structure, and the move
needed no `Package.swift` change, no import changes, and no `openapi.yaml`
edit, since the actual HTTP surface didn't change at all. It's plain `git
mv`s, verified by a clean build and all 162 tests still passing. The split
doesn't enforce any real boundary, since Swift has no folder-scoped imports;
its only value is making the tree easier to navigate. I left the Leaf
templates where they were (a separate resource directory Leaf's config
already expects) and left the sprawling `AppWebController` alone for now,
since breaking that up is a separate piece of work.

## Backend: decomposed `AppWebController` into per-domain controllers + presenters

That 1,349-line `AppWebController` monolith eventually did get split, into
one `RouteCollection` per domain, mirroring how the API side was already
organized: `AppAuthWebController` for login/logout, `BookmarkWebController`
for the bookmark list and detail routes, `SmartViewWebController`,
`TagWebController`, and `SettingsWebController`. `AppWebController` itself
is gone; `routes.swift` builds the `/app` session and auth-middleware group
once and registers each per-domain collection onto it, the same shape the
API side already used. Splitting it also gave me a chance to properly
separate three roles that had been tangled together: controllers stay thin
request orchestrators, pure presentation logic moved into `Web/Presenters/`
namespaces with no request or database access at all, and cross-controller
glue (a shared render helper, flash-message copy, the sidebar loader, the
tag-autocomplete JSON helper) moved into `Web/Support/`. I'd originally
planned a dedicated `BookmarkListPage` type to share logic between the
bookmark list and Smart View results pages, but in practice the only things
they genuinely share are the sidebar load and row mapping: everything else
legitimately differs between a search/tag filter and a saved query, so a
shared page type would have just been a wide pass-through of parameters, and
I used the loader and presenters instead. `AdminWebController` got the same
de-duplication treatment in the same pass, since its private render helper
was byte-identical to the one I'd just extracted. Purely organizational
again: one Swift module, unchanged routes and rendered output, verified by
a clean build and all 162 tests passing (booting the full app in tests
already proves route registration).

---

## Site Settings & Admin Customization

`SiteSettings` is a single-row table that's never deleted: always exactly
one row, seeded on migration, with a single accessor that recreates the row
if it's somehow missing, so nothing downstream ever has to handle an empty
table. The selected accent theme gets injected into every page as a small
server-side CSS block overriding the `--accent` custom property, so every
existing `var(--accent)` reference in the stylesheets picks it up
automatically with no per-template changes. There's no per-request database
query involved: the values live in a lock-guarded, app-level cache loaded
once at boot and refreshed in place whenever the admin saves the appearance
form.

That cache needed one correctness fix: a refresh should only ever mutate the
lock-guarded snapshot, never write back into `Application.storage`, which is
an unsynchronized dictionary that would data-race the concurrent page-render
reads if touched at runtime. There was a leftover fallback branch that did
exactly that unsafe write in a case that was actually unreachable in
practice; I removed it, so a missing cache holder now just logs and falls
back to default values until the next boot, rather than risking a race.

I also settled a small API-design question here: page contexts pass chrome
(the footer, accent, and about text) as one nested `chrome` field rather
than flattening it into the top-level context. A generic wrapper that
flattens an arbitrary page context's keys alongside a `chrome` key looked
appealing, but Leaf's encoder crashes on a second container at the same
encoding level, so the "encode the page then splice in a key" trick that
works fine with `JSONEncoder` doesn't work under Leaf. Threading one nested
field through every context is more verbose, but it's reliable, and the
chrome lookup itself is synchronous and never throws: a missing cache just
falls back to defaults so a page render is never blocked by a
misconfiguration.

The Stash identity itself (the name, the Ko-fi link, the Mastodon link)
was hardcoded directly in the footer template rather than passed through
context, specifically so it can't be accidentally omitted, overridden, or
removed by an admin. *Superseded:* all footer links are now editable by
the admin through four label+URL slots stored in `footerLinks`; only the
name and logo remain hardcoded. See the Editable footer links entry below. The version string is read from a `VERSION` file at
startup and falls back to `"dev"` if that file is missing or empty. The
theme picker itself needs no JavaScript at all: just visually-hidden radio
inputs with CSS drawing the active ring around whichever swatch is checked.

---

## Favicon Caching

Favicons are cached per domain, not per bookmark or per user, since a
favicon genuinely belongs to a domain rather than to any one person's
private collection: one row keyed by a normalized, lowercased,
`www.`-stripped domain is shared across every user and every bookmark on
that host. The practical win is that the cache grows in proportion to
unique domains rather than bookmark count, which scales far better for a
large collection. The domain key deliberately keeps an explicit port, since
without it two different services running on the same LAN host (the
documented `http://192.168.1.x:8080` deployment case) would collide on one
cache row and show each other's icon.

Fetching tries three sources in order: the page's own declared icon link
(already discovered by the metadata fetch that ran at bookmark creation), a
`/favicon.ico` guess at the domain's origin, and Google's favicon service as
a last resort. The `/favicon.ico` guess is built from the bookmark's actual
origin rather than a hardcoded `https://`, since an http-only LAN box would
never answer an https probe.

Images are stored as a binary database column rather than on a filesystem
volume: one thing to back up, no extra Docker volume to configure, which is
a reasonable trade-off since favicons are tiny; anything over 100KB gets
rejected outright as "not a favicon." The content type has to start with
`image/` and specifically can't be SVG, since SVG is active content and the
serve endpoint returns bytes from the Stash origin: an SVG with an embedded
script, opened directly, would execute in that origin. The response also
carries a `nosniff` header as defense in depth, so a mistyped `image/*` body
can't get MIME-sniffed into something it isn't. A favicon is fetched exactly
once, when its domain is first encountered, and never automatically
re-fetched afterward: no background polling, no scheduled refresh. A site
changing its icon is rare enough that a user-triggered manual refresh
endpoint is sufficient, and it's open to any active user, not just whoever
saved the first bookmark on that domain, since favicons are shared rather
than privileged.

The actual fetch runs detached after the bookmark save already responded, so
it never blocks bookmark creation: the same non-blocking philosophy as
metadata fetching. Deduping concurrent first-time fetches for the same
domain works by inserting a `pending` row first and letting the database's
unique index make the first writer win; the insert failure path is narrowed
specifically to a constraint violation, so a transient database error can't
be mistaken for "already in flight" and silently swallowed. The serve
endpoint itself is unauthenticated, since favicons aren't sensitive and
`<img>` tags can't easily attach a bearer token anyway: a cached row
returns the bytes with a month-long cache header so the browser caches it
too, and anything failed, pending, or missing just returns a 404 that the
web UI handles by hiding the broken image entirely rather than showing a
broken-image glyph.

New bookmarks no longer write the old per-bookmark `faviconURL` field at
all (the web UI resolves favicons by domain at render time instead), but I
left the column itself in place rather than running a destructive migration
for no real benefit. Bulk imports backfill favicons too: a successful web
import walks the user's bookmark URLs, dedupes down to distinct domains, and
fetches each one sequentially in a single background sweep, rather than
firing one detached task per bookmark: that bounds the outbound fetch
concurrency a large import would otherwise unleash, and already-cached
domains cost one rejected insert and no actual HTTP request. There's no rate
limiting on the manual refresh endpoint, which I'm noting here as an
accepted gap for a self-hosted, small-team tool rather than something I
fixed; worth revisiting if abuse ever becomes a real concern.

The native apps moved onto this same cached endpoint too, rather than
hitting Google directly the way they used to. The domain-key computation has
to be duplicated in Swift on both the backend and the app, since no shared
module spans both sides of that boundary and StashKit is deliberately kept
logic-free, so the client-side version carries a comment pointing back at
the server as the source of truth. Favicons render on an always-light
backdrop on both native and web, regardless of the active color scheme,
since a lot of favicons are designed for white backgrounds and look poor
sitting on a dark surface.

---

## OpenAPI specification

The API spec (`Backend/Public/openapi.yaml`) is hand-written, not generated
from any code-scanning tool: authored directly from the product spec, the
API docs, and the backend's actual response types, with zero new
dependencies or build step involved. Because nothing generates it
automatically, I hold myself to a hard rule: any change to the `/api/v1/`
surface (a new or removed endpoint, a renamed field, a changed status
code, a new error case) has to update this file in the same commit, and I
treat a spec that's fallen out of sync with the code as a bug in its own
right, not a documentation nice-to-have. It's served as a plain static
asset, no new route needed, and a Swagger UI page at `/docs.html` loads a
CDN copy of the viewer and points it at the spec: no bundled library, no
build step there either. The spec deliberately reflects the API as actually
implemented rather than the original plan where the two diverge, and I
validate it with a schema linter after every edit.

## Release images: build natively per-arch instead of via QEMU

The release workflow's arm64 image was originally cross-compiled under QEMU
emulation on an x86 runner, and emulating the full Swift compiler through
an entire Vapor/NIO release build crashed it outright, not as an occasional
flake but as a hard failure on every single arm64 build attempt. A
same-week stopgap (pinning a specific QEMU image version) papered over a
related but distinct emulation crash without touching the actual compiler
crash, and was quickly superseded once I found the real fix: build each
architecture natively on its own matching runner instead of emulating one
of them, pushing each architecture's image to the registry separately, then
stitching both into one proper multi-architecture manifest afterward, with
the version tags applied to that combined manifest rather than to either
individual architecture's image. QEMU is no longer part of the release
pipeline at all.

## Admin health page, kept separate from the public `/health` probe

I added a new `GET /admin/health` page to the admin web dashboard showing
version, database connectivity, process uptime, disk usage, and total
users/bookmarks — all useful operational context for an admin, none of it
appropriate to expose on the existing public, unauthenticated `GET /health`
liveness probe. I deliberately left that endpoint and its `HealthResponse`
DTO completely untouched: it's documented in the OpenAPI spec with a fixed
`{ "status": "ok" }` contract, used by monitors and container orchestrators
that only care about "is the process alive," and adding fields to it (or
requiring auth) would both be a breaking change to that contract and an
unnecessary information disclosure to anyone who can reach the endpoint
without logging in. The two surfaces now serve two different audiences by
design: `/health` for machines that only need a liveness bit, `/admin/health`
for a signed-in human who wants to see what's actually going on.

The database check runs a bare `SELECT 1` through `SQLDatabase.raw(...)`
rather than anything Fluent-model-specific, so it stays truthful even if a
particular table migration is broken — it only asserts "can we talk to the
database at all," which is the right question for a health page. Driver name
(Postgres vs. SQLite) is derived from `app.environment == .testing`, the same
condition `configure.swift` already uses to choose the driver, rather than
re-deriving it from `DATABASE_URL` a second time and risking the two checks
drifting apart later. `SQLDatabase` needed an explicit `import SQLKit` in
`AdminWebController.swift`; it isn't visible transitively from `Fluent`
alone in this controller, the same reason `CreateDeletedBookmarks.swift`
already imports it directly for its own raw-SQL index creation.

Uptime required one small addition: there was no existing "process start
time" recorded anywhere, so I added a `BootDateKey: StorageKey` (mirroring
the existing `AppVersionKey` pattern in the same file/directory) and set it
once in `configure(_:)` at boot. Disk usage uses
`FileManager.attributesOfFileSystem(forPath:)`, which works fine on the
Linux deployment target already documented for the Docker image; a failed
read (e.g. an unusual filesystem) degrades to an "unavailable" label rather
than crashing the page, since disk stats are a nice-to-have, not essential
to the page's usefulness.

The web-UI tests for this page went into `AppearanceTests.swift`, not
`AdminTests.swift`: that name looks like the obvious home, but it turned out
to hold only the JSON `/api/v1/admin/*` controller tests, while the existing
pattern for testing session-cookie `/admin` web pages (the `adminWebSession`
login helper) already lived in `AppearanceTests.swift` alongside the
dashboard/appearance page tests. Matching the existing test's actual
location mattered more than matching its name.

## Admin database maintenance: a manual VACUUM button

Stash's hard-delete paths (single bookmark delete, the "delete all
bookmarks" danger zone, and the admin's cascade delete-user) leave dead
tuples behind that Postgres's autovacuum eventually reclaims on its own, but
on a small self-hosted instance autovacuum can be slow to trigger or
effectively idle if write volume never crosses its threshold. I added a
single manual "Run database optimize" button on a new `/admin/maintenance`
page rather than a scheduled job, since Stash has no background job
scheduler infrastructure at all, and adding one just for this would be a
disproportionate amount of new complexity for what's fundamentally an
occasional, low-frequency maintenance action. An admin clicking a button
once in a while is an acceptable v1 answer; a scheduled background VACUUM is
a reasonable follow-up if an instance ever needs it.

Postgres refuses to run `VACUUM` inside a transaction block, so the handler
calls `sql.raw("VACUUM").run()` directly against `req.db` cast to
`SQLDatabase`, never wrapped in `req.db.transaction { ... }`. This is the
one thing in this feature I was most careful about, since SQLite (what the
test suite runs against) is more permissive here: a transaction-wrapped
VACUUM would pass every test and only fail at runtime in production against
Postgres, exactly the kind of asymmetry that slips past CI. I also only ever
run plain `VACUUM`, never `VACUUM FULL`: FULL rewrites the whole table and
takes an exclusive lock for the duration, which would let a routine
admin-panel button take down the app for every user while it runs; plain
VACUUM reclaims dead-tuple space without blocking reads or writes, the right
trade-off for a click-any-time action. There's no UI option for FULL.

Nothing about past runs is persisted — no "last optimized at" timestamp, no
history list. The page shows the elapsed time of the *most recent* run in a
one-off flash banner, passed through the redirect's `?ms=` query parameter
rather than baked into `FlashMessage.admin(for:)` itself, since that
function takes only the `ok` slug and giving it a way to carry dynamic data
would ripple into every other call site. Persisting a real "last run"
history would need a new column or table for a feature whose entire value
is "reclaim space now," not "track maintenance history"; deferred until an
admin actually asks for it.

## Feature: Favicon Cache Management (admin tool)

A new `/admin/favicons` page shows `favicon_cache` stats (total/cached/
pending/failed counts, total bytes) and two bulk actions: clear the whole
cache, and re-scan every known domain. Both actions compose entirely from
existing primitives: clearing is a plain `FaviconCache.query(on:).delete()`,
and re-scanning is a new `FaviconFetcher.refreshAll(on:)` that calls the
existing `refresh(domain:on:)` (delete row, kick off a detached re-fetch)
for every distinct domain. No new model, migration, or JSON API surface:
this lives entirely under `/admin`, the same session-cookie-auth surface as
`/admin/appearance` and `/admin/maintenance`, so `openapi.yaml` is
untouched.

`refreshAll`'s domain list is the union of every domain already in
`favicon_cache` **and** every domain referenced by an existing
`Bookmark.url`, not the cache table alone. The first version read only from
`favicon_cache`, which made "Clear cache" followed by "Re-scan" a no-op: the
clear emptied the very table re-scan read its domain list from, so the
stats page kept showing 0 total/cached/failed/pending no matter how many
bookmarks existed. Union-ing in the bookmarks' domains means re-scan can
always rebuild the cache from scratch after a clear, independent of what's
currently in `favicon_cache`. I caught this by actually clicking through
the two buttons in sequence rather than testing them in isolation, which is
exactly the kind of interaction-order bug that per-action unit tests don't
surface.

`refreshAll` loops sequentially rather than firing every domain's fetch
concurrently. Each `refresh` call is cheap (a DB delete plus spawning a
detached `Task`), so the loop itself completes fast, but doing this
sequentially still staggers when each domain's real HTTP fetch actually
starts, rather than firing them all in one unthrottled burst at external
providers, including Google's `s2/favicons` service, whose rate limits I
don't control. A bounded-concurrency `TaskGroup` would be the efficient
middle ground, but this is an infrequent, admin-triggered maintenance
action, not a hot path, so I kept v1 simple and would only add bounded
concurrency if a real instance's domain count made the sequential loop
noticeably slow.

The total-bytes stat is computed with a single `FaviconCache.query(on:).all()`
plus a Swift-side tally (byte sum and per-status counts in one pass), not a
raw SQL `SUM(LENGTH(image_data))`. Postgres's `LENGTH`/`octet_length` on
`bytea` and SQLite's `LENGTH` on `BLOB` aren't guaranteed to agree in every
configuration, and getting that silently wrong on a diagnostics page is
worse than the minor inefficiency of pulling every row into memory once, for
what's expected to be at most a few thousand distinct-domain rows on a
self-hosted instance. The raw integer is formatted into a human-readable
`B`/`KB`/`MB`/`GB` string (reusing and extending the health page's existing
`formattedBytes` disk-usage helper down to the byte/kilobyte range, since a
favicon total can plausibly sit anywhere from a few bytes to low megabytes,
unlike disk usage which never drops below the megabyte range) rather than
showing a raw byte count like `1104690 bytes`, which is accurate but not
something an admin can parse at a glance.

Clearing the cache uses a plain `confirm()` JS dialog, not the typed
confirmation-phrase pattern used for "delete all bookmarks." That heavier
pattern exists because deleting bookmarks destroys real, unrecoverable user
content; clearing the favicon cache destroys nothing irrecoverable. Re-scanning
gets no confirmation dialog at all, since it isn't destructive either.

One nuance worth being precise about, since an earlier pass of this feature's
own UI copy got it wrong: a cleared favicon does **not** silently regenerate
just by browsing `/app` and looking at a bookmark for that domain.
`FaviconFetcher.enqueue` — the only thing that populates `favicon_cache` outside
an explicit refresh — only runs when a *new* bookmark is saved for that domain
(§10 / `DECISIONS.md`'s Favicon Caching section); viewing or editing an existing
bookmark never calls it. So after "Clear cache," a domain's favicon only comes
back via "Re-scan all favicons," a new bookmark saved for that domain, or that
bookmark's own per-row "Refresh favicon" button — never by merely browsing.
The page copy, the confirm-dialog text, and the `favicons_cleared` flash message
were corrected to say this rather than implying automatic regeneration on view.

---

## Feature #6: Audit log

Added a narrow, best-effort audit trail covering only auth events (login
success, login failure, logout) and admin user-management actions (create,
suspend, unsuspend, password reset, TOTP reset, delete, and site-appearance
changes). Deliberately excluded bookmark, tag, and smart-view CRUD — those
are high-volume and low audit value for a first version, and including them
would flood the "last 50 rows" viewer with noise that pushes the
security-relevant events off the page almost immediately. The three
genuinely independent auth surfaces (JSON API, admin web dashboard, app web
frontend) and the two independent admin-action surfaces (JSON admin API,
admin web dashboard) each needed their own hooks — there's no shared login
or user-mutation helper in this codebase to hook once, which made this a
wide, mechanical change rather than a deep one. Writes are best-effort and
non-throwing from the caller's side by design: a real login or a real
user-delete must never fail because an audit row failed to save, so
`AuditLogger.record` swallows and logs its own errors rather than
propagating them. Client IP is read from `X-Forwarded-For` first, falling
back to the raw socket address, because Stash's documented deployment runs
behind a Caddy reverse proxy that sets that header — using the raw socket
address unconditionally would have recorded Caddy's own container address
on every row in that topology, making the IP column useless. This does mean
a Stash instance exposed directly to the internet without a reverse proxy in
front could have its audit IPs spoofed by a malicious client; that's an
accepted trade-off given the documented, expected deployment shape. The
viewer itself is intentionally minimal: no pagination, no filtering, no
export, just the most recent 50 rows — matching the same "ship the smallest
useful admin tool" approach used for Feature #7's Active Sessions viewer.

---

## Feature #7: Active Sessions

Added a read-only-turned-actionable admin tool at `/admin/sessions` (plus a matching
JSON API under `/api/v1/admin/sessions`) that lists every live web session — both
the admin dashboard and the app frontend — and lets an admin revoke all of them or
just one user's. The whole feature is a thin `ActiveSessionLoader` enum that reads
and writes `app.sessions.memory.storage.sessions` directly: Vapor's `MemorySessions.Storage`
exposes that as a public, mutable `[SessionID: SessionData]`, and — since both
`/admin` and `/app` are configured off `app.sessions.driver` (`configure.swift`,
`routes.swift`) — it's the *same* dictionary for both surfaces, distinguished only
by whether a session's data carries `AdminSessionMiddleware.sessionKey` or
`UserSessionMiddleware.sessionKey`. This meant no new table, no migration, no
login/logout tracking hooks, and no custom `SessionStore`. An earlier draft of this
plan assumed Vapor's in-memory driver had no public iteration/deletion API and
proposed exactly that machinery (a login-hooked `ActiveSessionTracker` singleton
mirroring the refresh-token pattern); that assumption turned out to be wrong once
checked against the vendored Vapor source, and reading it directly before
implementing avoided building the unnecessary tracker.

The trade-off inherited from `SessionData` being a thin `[String: String]` wrapper:
no IP address, user-agent, or creation timestamp are available, so the table can't
show them. This is acceptable because (a) revoking a compromised session works
correctly regardless of whether IP/UA is displayed, and (b) adding that data would
mean persisting sessions to a DB table on every request — a much bigger change
better suited to a follow-up milestone. Revocation is immediate and correct without
any of that: `revokeAll` and `revokeForUser` mutate the shared dictionary directly
(not `req.session.destroy()`, which only ever affects the *current* request's own
session), and both also delete the affected refresh tokens so JSON API access dies
alongside the web session. The viewer itself, like Feature #6's audit log, stays
intentionally minimal: no pagination beyond a username filter, no polling/live
refresh — an admin reloads the page to see current state.

One subtlety the web handlers do need to account for: `SessionsMiddleware` reads
the request's own session into a request-local cache *before* the route handler
runs, and writes that cached copy straight back into the store when the response
is sent — regardless of what the handler did to the store in between. So an admin
revoking all sessions (or revoking their own account by name) from the sessions
page would otherwise see their own dashboard session silently resurrected right
after the wipe, since the response phase re-inserts it. Both web handlers call
`req.session.destroy()` on that self-referential path (all-revoke always; the
by-user revoke only when the target is the acting admin), which flips the
request's cached session to invalid so the middleware deletes it instead of
rewriting it. The JSON API endpoints don't need this: admin API requests
authenticate over the bearer token, not a session cookie, so there's no
request-local session to resurrect.

---

## Feature #8: System Logs

### Ephemeral, capped, in-memory by design

The `/admin/logs` page reads from a fixed-capacity (1000-entry) in-memory
ring buffer that is never written to disk or the database. It is emptied
on every restart. This mirrors a trade-off this project has already made
and documented once before: the M5 web admin dashboard entry (above, in
this file) explicitly accepts that the admin session store is in-memory
and "does not survive a restart," calling that "fine for a single
self-hosted instance." System logs get the identical treatment for the
identical reason — Stash targets self-hosted, typically single-instance
deployments where losing a rolling window of recent log lines on restart
is an acceptable cost, and where the alternative (a DB table with a
retention/cleanup job, or a log file with rotation) is meaningfully more
machinery for a feature whose whole purpose is "quick triage without
opening a shell." If a durable, searchable, larger-scale log history is
ever needed, that's a distinct follow-up feature (a persisted
`SystemLogEntry` table with a pruning job), not a v1 requirement here.

### Why a `MultiplexLogHandler` instead of replacing console logging

Rather than swap out Vapor's console logging for something new, this
feature adds a second `LogHandler` (`RingBufferLogHandler`) alongside the
existing one via `MultiplexLogHandler`, wired up in `entrypoint.swift` by
calling the `LoggingSystem.bootstrap(from:_:)` overload with a custom
factory instead of touching `--log`/`LOG_LEVEL` parsing at all. `docker
logs`/`podman logs` output (stdout, via the same `ConsoleLogger` +
`Terminal()` construction Vapor's default `bootstrap(from:)` already used)
remains byte-for-byte the primary and durable log surface; the in-app
`/admin/logs` viewer is strictly a convenience for quick triage without
reaching for a shell, not a replacement for real log aggregation. I
deliberately did not use `Logging.StreamLogHandler` (a tempting shortcut
since it's the best-known "simple" handler) because it is not what this
app's console output actually uses today — it would have silently changed
the format/coloring of stdout logs, which the console-preservation
requirement explicitly ruled out.

### Why `sharedLogBuffer` is a module-level constant, not `Application.storage`

`LoggingSystem.bootstrap` runs before `Application.make(env)` is called in
`entrypoint.swift`, so there is no `Application`/`app.storage` to put
anything into at the point the ring buffer needs to exist and be captured
by the log-handler factory closure. A plain top-level `let sharedLogBuffer
= LogRingBuffer()` constant, declared alongside the bootstrap code, is
reachable both there and later from `AdminWebController.logsPage` (same
module, no plumbing needed) without inventing a workaround for storage not
existing yet.

---

## Feature: Internet Archive (Wayback Machine) submission

A long-requested feature: when a bookmark is saved, also submit its URL to
the Internet Archive so there's a durable off-site snapshot, independent
of Stash's own `isArchived` inbox flag (deliberately named `wayback*`
everywhere — model fields, routes, buttons — to avoid colliding with that
unrelated existing flag).

### Anonymous `/save`, no credentials

Submission goes through `https://web.archive.org/save/<url>` (a plain
`GET`), not the authenticated SPN2 API. That keeps the feature
dependency-light and config-free (no API keys to provision), at the cost
of tighter, undocumented rate limits — which is exactly why this needed a
serial, self-throttling queue rather than firing requests inline.

### A persisted, serial queue — not `FaviconFetcher`'s fire-and-forget shape

`FaviconFetcher` (favicon caching) is a stateless `enum` that dispatches
`Task.detached` work with no durable queue: if the process dies mid-fetch,
that fetch is simply lost, and it's fine because a favicon reappears for
free the next time any bookmark on that domain is saved. Wayback
submission doesn't have that safety net — a lost submission means a
bookmark silently never gets archived — so `WaybackSubmitter` persists
queue state on the bookmark itself (`waybackStatus`: `none` / `pending` /
`archived` / `failed`) instead of relying purely on in-memory
`Task.detached` work. Enqueuing is just: flip the status to `pending`,
save, and wake the drain worker; the worker discovers work by querying for
`pending` rows rather than tracking an in-memory list, so a crash mid-drain
self-heals — `WaybackSubmitter.bootstrap(on:)` re-sweeps at every boot by
just calling `kick()`, which picks up any row still `pending` from before.

The drain itself is an `actor` (`WaybackWorker`), not another stateless
enum: it must never run two drains concurrently, since the anonymous save
endpoint's rate limit is tight enough that a second concurrent drain
starting while one is already in flight would burst it. The actor holds a
single `isDraining` flag and processes one `pending` bookmark at a time
with a deliberate delay between submissions (longer than the favicon
queue's, since `/save` is far more rate-limit-sensitive than favicon
providers), sleeping via `Task.sleep(for:)` between each. It's seeded once
at boot into `Application.storage` behind a `StorageKey`
(`WaybackWorkerKey`), the same seeded-holder pattern `SiteSettingsCache`
already uses, rather than being constructed per-request.

The anonymous save endpoint is also markedly slower than a favicon fetch
(it has to actually crawl and archive the live page), so `submit(...)`
sets a per-request timeout on the outbound `ClientRequest`
(`request.timeout = 30s`) rather than relying on the app's global 5-second
outbound-HTTP timeout (`configure.swift`), which is tuned for the favicon
queue's guess-and-check requests.

### Migration gotcha this surfaced: SQLite rejects multi-column `ALTER TABLE`

Adding `wayback_status` / `wayback_url` / `wayback_archived_at` to
`bookmarks` in one chained `.field(...).field(...).field(...).update()`
(the shape `AddSmartViewMatchMode` uses for its single column) produced a
SQLite syntax error, because — unlike Postgres — SQLite only supports one
`ADD COLUMN` per `ALTER TABLE` statement; FluentKit happily batches
multiple `.field()` calls into one comma-separated `ALTER TABLE`
statement, which is valid SQL for Postgres but not SQLite. `AddBookmarkWayback`
now issues three separate `.update()` calls, one per column, each its own
statement — worth remembering for any future migration that adds more than
one column at once.

### Migration gotcha this surfaced: seeding a row via the live `Model` type at migration time

Adding `internetArchiveEnabled` to `SiteSettings` broke every single test
in the suite, not just the new ones, with a bewildering "table
`site_settings` has no column named `internet_archive_enabled`" — from
`CreateSiteSettings`, the *original* migration, not the new one.
`CreateSiteSettings.prepare()` had always eagerly seeded the one-row table
by constructing a live `SiteSettings(accentTheme:)` and calling `.save()`
on it; once that struct gained the new field (with a default), Fluent's
model-based save serializes *every* current `@Field`, including
`internetArchiveEnabled` — straight into a table whose schema, as built by
that same historical migration, doesn't have that column yet (the `Add*`
migration that adds it runs later in the list). Constructing a versioned
app-level `Model` inside an old migration is a trap: the model always
reflects *today's* shape, not the shape the migration itself built. Fixed
by deleting the eager seed entirely — `SiteSettingsService.current(on:)`
already lazily creates the row if missing, and it's called via
`loadAndCache` right after every migration has run during `configure()`,
so the row still always exists by the time the app finishes booting, now
with no schema-version mismatch possible. Any future `SiteSettings` field
addition is safe by construction.

### Instance switch lives on its own admin page, not Appearance

`internetArchiveEnabled` (default on) could have been one more checkbox on
`/admin/appearance` alongside the accent theme, but that page has no
concept of operational state — it's pure presentation config. Internet
Archive submission has real operational state worth surfacing (how many
bookmarks are queued, archived, failed, never submitted), so it got its
own `/admin/internet-archive` page instead, modeled directly on
`/admin/favicons`: the same stats-grid layout, the same bulk-action card
row (here, "Retry failed" and "Queue all" instead of "Clear cache" and
"Re-scan"), and the same `FlashMessage.admin` PRG-banner wiring. The
enable/disable switch itself lives at the top of that page rather than on
Appearance, since it's operational control over this feature, not a
cosmetic site setting.

### Auto-submit gating: instance switch AND per-user preference, evaluated at create time

A bookmark auto-submits on create only when *both* the admin's
instance-wide switch and the user's own `archiveNewBookmarks` preference
(default on, a genuinely new per-user settings column — the first one;
previously the only per-user "preference" was the `stash_theme` cookie,
which isn't even a database column) are on, checked via
`WaybackSubmitter.isInstanceEnabled(on:)` at the same call site in both
`BookmarkController.create` and `BookmarkWebController.createBookmark`,
right next to the existing `FaviconFetcher.enqueue` call. The manual
"Save to Wayback Machine" button and its API/`app` route counterparts
bypass the user's auto-submit preference by design (that's what makes
"send this one bookmark even though auto-submit is off" and "re-submit
with a fresh date" both possible), but still respect the instance switch —
there's no way to submit anything when the admin has turned the feature
off, whether through auto-submit or the manual button.

### Code review follow-up: the admin bulk actions had slipped past the instance switch

A review pass on the first draft caught that `retryFailedInternetArchive`
and `queueAllInternetArchive` re-queued bookmarks and kicked the drain
worker without ever checking `WaybackSubmitter.isInstanceEnabled(on:)` —
every other submission path (auto-submit on create, both manual-submit
routes) checked it, but the two bulk actions were added by mirroring the
favicon admin page's "Clear cache"/"Re-scan" handlers, which have no such
switch to respect, and the gate was simply never carried over. The
practical effect: an admin could turn Internet Archive submissions off,
then still click "Retry failed" or "Queue all" and have bookmarks actually
submitted to the real `web.archive.org`, directly contradicting the
disabled state and the doc comment's own claim that "the admin bulk
actions gate on this first." Fixed by extracting both handlers into one
`requeueInternetArchive(matching:flashKey:req:)` helper that checks the
switch first and PRGs with `?error=internet_archive_disabled` when it's
off — collapsing the near-duplicate handlers and closing the gap in the
same change, so there's now exactly one place that could regress instead
of two.

The same pass found the auto-submit gate (`isInstanceEnabled &&
archiveNewBookmarks`) duplicated verbatim between the API and web create
handlers; that became `WaybackSubmitter.enqueueIfAllowed(_:for:on:)`, a
single static method both call sites invoke, for the same reason: one
place to update if the rule ever changes.

Two smaller things surfaced alongside: the instance-switch toggle was
logging its audit action as `"appearance_updated"` (copy-pasted from the
accent-theme form it was modeled on), which would have made "who toggled
Internet Archive" indistinguishable from "who changed the theme" in the
audit log — renamed to its own `"internet_archive_toggled"` action. And the
web "Save to Wayback Machine" button, when clicked while the admin had
disabled the feature, silently redirected with no flash message at all
(unlike its API sibling, which returns a proper `409`) — now redirects with
`?error=internet_archive_disabled`, reusing the same `FlashMessage.appError`
pattern the tag browser already uses for inline error banners on `/app`
pages. Both are edge cases in practice (the button and admin bulk-action
UI are hidden/disabled-in-spirit once the switch is off), but worth being
correct about since the audit log and the flash-message convention are
exactly the kind of thing other features build on.

One efficiency-only cleanup from the same pass: `WaybackWorker.drain()` had
been running a second `COUNT` query after every submission purely to decide
whether to keep looping, when the very next loop iteration's own fetch
already answers that (empty result = done). Dropped the extra query. The
admin Internet Archive page's five separate `COUNT` queries (one per status
plus an unfiltered total) had the same shape of redundancy — `WaybackStatus`
has exactly four cases, so the total is always the sum of the other four —
fixed by summing instead of querying a fifth time.

### Production finding: the anonymous save endpoint rate-limits far more aggressively than planned for

The first real deploy's "Queue all" run failed every single bookmark. Two
things made this hard to diagnose and worth fixing regardless of the root
cause: `submit(...)` logged nothing on failure — every non-2xx response and
every thrown error silently became `waybackStatus = .failed` with zero
trace of *why* — and there was no distinction between a genuine failure and
a `429`, which is really "try again later," not "give up." Both are fixed
now: every non-success path logs the response status or error via
`db.logger`, and a `429` leaves the bookmark `.pending` (so the next drain
cycle retries it automatically) instead of marking it `.failed`, with the
worker backing off 5 minutes before its next attempt instead of the normal
30-second pace.

Testing the anonymous endpoint directly (`curl` against
`https://web.archive.org/save/<url>`) confirmed the root cause: it returned
`429` on the very first request, with no `Retry-After` header, and again on
a second request roughly a minute later. This is consistent with widely
reported behavior — Internet Archive's anonymous, unauthenticated `/save`
capture endpoint throttles automated/non-browser traffic heavily, and
noticeably harder for datacenter/hosting IPs than residential ones, which
is exactly the kind of IP a self-hosted Stash instance runs from. The 30s
pace and 5-minute 429 backoff are a best-effort mitigation, not a guarantee:
if an instance's egress IP is persistently rate-limited or blocked by IA,
anonymous submission may just never succeed from that IP, no matter how
patient the queue is. The `.pending`-not-`.failed` retry-on-429 behavior at
least means it keeps trying quietly in the background rather than needing
a human to notice and click "Retry failed" repeatedly. If this turns out to
be a persistent problem in practice, the documented alternative is
Internet Archive's authenticated SPN2 API, which has much more generous
rate limits for legitimate automated capture — a bigger change (needs
admin-configured credentials) deliberately not built for this v1, since
the anonymous approach was the explicit, no-config-required starting
point.

### Native apps: "View on Wayback Machine" (read-only, one field wired through)

The native apps had never picked up the Wayback fields at all:
`StashKit.BookmarkDTO` already carried `waybackStatus`/`waybackURL`/
`waybackArchivedAt` (added when the API surface was extended), but the app's
SwiftData persistence entity (`LocalBookmark`) and domain `Bookmark` struct
silently dropped all three on every sync — confirmed by reading
`LocalBookmark.init(from:userID:)`/`apply(_:)`, which read every other DTO
field but not these. Since there's no `VersionedSchema`/`SchemaMigrationPlan`
anywhere in the app (the SwiftData store is treated as a disposable cache,
already wiped and fully re-synced on any container-open failure), adding a
new optional column needed no formal migration.

Scope deliberately stayed to the one field the UI needs: only `waybackURL`
was threaded through `Bookmark` → `LocalBookmark` → `Bookmark.init?(local:)`,
not `waybackStatus`/`waybackArchivedAt`. Nothing on mobile needs those yet
(no "queued"/"failed" indicator, no manual-submit action was asked for);
adding them later if a future feature needs them is a small, isolated change
given the pattern is already established.

The button reuses the exact same `@Environment(\.openURL)` action "Open in
Browser" already used, rather than a new mechanism — which turned out to
matter more than expected: iOS/iPadOS has an `openURL` environment override
(`.inAppBrowser()`) that routes `http`/`https` opens through an in-app Safari
sheet honoring the user's Reading settings (In-App vs. Default Browser,
Reader mode). Reusing `openURL` meant "View on Wayback Machine" picked up
that same in-app-browser routing for free, with no extra plumbing — a
different mechanism (e.g. a raw `UIApplication.shared.open` or a second
`Link`) would have silently bypassed it.

Added to both the detail view's actions section and the row's context menu
(per the existing convention that every action appears in both places),
positioned right after Share… and before Archive/Unarchive in each, matching
the equivalent ordering on the web frontend.

### Smart View condition: `isWaybackArchived`

A new boolean condition, `isWaybackArchived`, filters bookmarks by whether
they've been submitted to the Internet Archive — same `{type, value}`
discriminated-union pattern as every other Smart View condition, added
mechanically alongside `isArchived`/`hasTags` in the one place each layer
defines its condition set (the backend's `SmartViewCondition` enum, its web
presenter/Leaf form, and the native app's `SmartViewConditionType` enum).

The semantics needed a decision: `true` could mean "a submission was ever
attempted" (`waybackStatus != .none`, i.e. pending/archived/failed all count)
or "a real snapshot exists" (`waybackStatus == .archived` only). Chose the
latter — `false` then covers `none`, `pending`, *and* `failed`, which is the
more actionable filter in practice ("show me what still needs archiving")
rather than a fairly useless "was this ever queued" split. This choice also
kept the native app change smaller: it already threads `waybackURL` (non-nil
exactly when `waybackStatus == .archived`) into its offline `Bookmark`
model from the earlier "View on Wayback Machine" work, so
`bookmark.waybackURL != nil` is already the correct offline-evaluation
equivalent — no need to additionally thread the four-case `waybackStatus`
enum through `LocalBookmark`/`Bookmark` just for this one boolean.

### Production finding: a rate-limited bookmark could block the entire queue forever

A real deployment surfaced `www.amazon.com` getting rate-limited (`429`)
every 5 minutes with no end in sight. Investigating turned up a worse bug
than "this one URL never succeeds": on a `429`, `submit(...)` never saved
the bookmark, so Fluent's `on: .update` `updatedAt` timestamp never
advanced. `WaybackWorker.drain()` always fetches the *oldest* `pending` row
(`sort(\.$updatedAt).first()`), so a persistently rate-limited bookmark
stayed the oldest forever and **starved every other bookmark queued behind
it** — the whole queue stalled, not just the one URL.

Fixed with a new `Bookmark.waybackRetryCount` column (internal bookkeeping,
not exposed via the API/DTOs — nothing external needs it) and two changes
to `submit(...)`:
- Save the bookmark on *every* `429`, not just when it eventually gives up.
  This alone fixes the starvation: bumping `updatedAt` moves the row behind
  other pending bookmarks, so the queue naturally round-robins between all
  of them instead of hammering the same stuck one. No changes needed to
  `drain()`'s query or pacing — the fix is entirely in what gets persisted.
- Cap consecutive rate-limited attempts at 3 (~15 minutes at the existing
  5-minute backoff): past the cap, give up and fall back to the existing
  `.failed` state rather than retrying forever, exactly like any other
  submission error — retryable later via the admin "Retry failed"/"Queue
  all" actions or a manual per-bookmark resubmit, never automatically
  again. `waybackRetryCount` resets to `0` on every terminal transition
  (`archived`, or `failed` via either path) so a fresh manual retry always
  starts the counter clean rather than inheriting a stale count.

### Follow-up: queue-status visibility, and the switch not stopping in-flight work

Adding a queue-status line to `/admin/internet-archive` (idle, paused with
a pending count, submitting a URL, running, or rate-limited-and-retrying)
surfaced a related gap: toggling `internetArchiveEnabled` off never stopped
a drain loop already running. `WaybackWorker.drain()`'s loop had no check
of its own — it only relied on `enqueueIfAllowed`/the manual-submit routes
refusing *new* work, so anything already `.pending` when the switch flipped
kept getting submitted for real. That silently contradicted the documented
"when off, submission is unavailable everywhere, instance-wide" — the
status display would otherwise have had to describe an inconsistent state
("Disabled" while a submission was still in flight).

Fixed by checking `WaybackSubmitter.isInstanceEnabled(on:)` at the top of
every `drain()` iteration, not just at entry, so disabling mid-run stops
the loop before its next fetch/submit and leaves any remaining `.pending`
rows untouched. Also added a `QueueState` enum (`idle`, `submitting(url:)`,
`waitingNormalPace`, `waitingAfterRateLimit(url:attempt:maxAttempts:)`)
recorded on the actor at each phase transition, exposed via a
`currentState()` getter, and a manual "Resume queue now" button
(`POST /admin/internet-archive/resume`) that just calls the existing
idempotent `kick()` — safe to press whether or not the worker is already
running.

### Dashboard redesign: turn `/admin` into a hub, and trim the nav bar

The admin nav bar had grown to 11 flat links (Dashboard, Users, New user,
Appearance, Audit log, Sessions, Health, Maintenance, Favicons, Internet
Archive, Logs) plus App and Log out, while the Dashboard itself did almost
nothing — two stat tiles and a per-user table that just duplicated the Users
page.

Rebuilt the Dashboard as the admin hub: a KPI strip (users with an
active/suspended split, bookmarks, live sessions, Internet Archive queue
depth — all gathered concurrently via `async let`, same pattern as
`renderInternetArchive`), a grid of navigation cards to every other admin
page (each with a description and a cheap live detail where one exists), and
a recent-activity feed reusing `AuditLogRowContext` from the Audit Log page
at a smaller limit (8 vs. 50). The old per-user table was dropped — it now
lives only on `/admin/users`.

With the Dashboard now a real launcher, trimmed the shared nav in
`layout.leaf` down to Dashboard / Users / App, since every other page is one
click away via its card. Nothing is orphaned: the trim was verified with a
dedicated test asserting the `<nav>` no longer lists the removed items while
the dashboard's card grid still links to all of them.

### Add `info`-level activity logs so `/admin/logs` is actually useful

Auditing the codebase found that **nothing logged at `info`** — the only
lines ever reaching `/admin/logs` were a couple of Wayback `notice` lines, the
first-boot admin `notice`, and `error`s. In normal operation the page was
near-empty.

Added concise `info` lines for notable user/system events: bookmark saved,
deleted, and delete-all; Smart View created/updated/deleted; tag
renamed/deleted; favicon cached/failed; Wayback snapshot saved. `info` was
chosen over `notice` deliberately — the logs-page `?level=` dropdown only
offers `info`/`warning`/`error` (`AdminWebController.logsPage`,
`selectableLevels`), so a `notice` line is only visible in the unfiltered
view, which would make it easy to miss.

Centralized the message text in a new `ActivityLog` enum
(`Core/Support/ActivityLog.swift`, alongside the existing `StashUserAgent`)
rather than inlining strings at each call site, for two reasons: the API and
web surfaces each save bookmarks/Smart Views independently with no shared
controller, so a helper is the only way to guarantee identical wording across
both; and the ring buffer is wired up only in `entrypoint.main`, not the test
harness, so the helper's pure strings are the actual testable seam (see
`ActivityLogTests.swift`) — there's no way to assert on captured log lines
from an integration test.

Deliberately left out of this pass: bookmark edit/archive-toggle (too
frequent to be useful signal) and login/logout/startup — auth and admin
actions are already captured in the DB-backed Audit Log
(`AuditLogger`/`/admin/audit`), and duplicating them to the ops log would be
redundant rather than additive.

### Regroup the web bookmark detail page's actions

The detail page (`app-bookmark-detail.leaf`) had accumulated up to 8 buttons
in one flat `.row-actions` flexbox (Open URL, Edit, Refresh favicon, View on
Wayback Machine, Save to Wayback Machine, Archive/Unarchive, Delete), each a
different width and wrapping unpredictably — noticeably more cluttered than
the native apps' grouped `Section`-based action list (§14).

Regrouped rather than reaching for a dropdown/"more actions" menu: the top
row keeps only the two most common actions (Open URL, Edit); a new "Actions"
card lists the rest as stacked full-width rows (new `.action-list`/
`.action-row` CSS — block-level, bordered dividers between rows, a
`--surface-2` hover); and Delete moved into its own "Danger zone" card,
reusing the `.danger-zone` styling already used on the Settings and admin
User Detail pages rather than introducing a new visual pattern. Chose this
over a kebab/dropdown menu because it needs no new JS interaction pattern
(the web UI's stated philosophy is plain HTML/vanilla JS, no build step) and
keeps every action visible rather than hidden behind a click, which matters
more on a page that isn't visited often enough to make a hidden menu
muscle-memory. Conditional visibility (favicon present, Internet Archive
enabled, `waybackURL` set, archived vs. not) is unchanged — only the layout
grouping changed, not which buttons show when.

### Code-review follow-up: Wayback/dashboard hardening (8 findings fixed)

A review pass over the six Wayback-era commits surfaced eight actionable
findings, all fixed:

- **StashKit version-skew (the two that mattered most):** `BookmarkDTO.waybackStatus`
  and `UserDTO.archiveNewBookmarks` were non-optional with synthesized
  Codable, so a newer app talking to a not-yet-upgraded self-hosted backend
  failed to decode entire bookmark lists / user profiles the moment the key
  was missing. Both now use a hand-written `init(from:)` with
  `decodeIfPresent` + the server-side default (`.none` / `true`), following
  the existing `SmartViewDTO.matchMode` precedent. Covered by new
  `DTOBackwardCompatibilityTests` decoding old-server JSON fixtures.
- **Wayback HTTP client followed redirects:** AsyncHTTPClient's default
  `RedirectConfiguration` is `.follow(max: 5)`, which made `submit()`'s
  `.movedPermanently`/`.found` handling and `Location`-header snapshot
  extraction dead code, and risked marking a captured bookmark `.failed` if
  a followed hop returned non-2xx. The dedicated client is now built with
  `redirectConfiguration: .disallow` so the 3xx handling actually runs.
- **DB-save misattribution in `submit()`:** the success-path save lived in
  the same `do/catch` as the network call, so a transient DB error recorded
  an actually-captured snapshot as `.failed`. The catch now wraps only the
  HTTP request; state saves go through a `persist()` helper that logs (never
  propagates) persistence failures.
- **404-before-409 ordering:** the API's `submitToWayback` gated on the
  instance switch before `requireBookmark`, returning 409 for nonexistent or
  foreign IDs while disabled — contradicting the OpenAPI contract and the
  web handler's order. Reordered (ownership first) + regression test.
- **`enqueue()` defense in depth:** it now refuses when the instance switch
  is off, so the "nothing goes `.pending` while disabled" invariant lives in
  the chokepoint rather than only at each call site (callers still check
  first to report the refusal to the user).
- **Dashboard favicon counts:** replaced the full-table `.all()` load
  (which pulled every cached favicon BLOB per dashboard view) with two
  filtered `.count()` queries, matching the Internet Archive count pattern.
- **Test cleanup:** deleted `AppearanceTests`' private copy of the
  admin-session login helper in favor of the shared
  `Application.adminWebSession()`.

Reviewed-and-rejected (not bugs): the `/web/2/` snapshot fallback (verified
live: it resolves to the *newest* capture), the 3-attempt rate-limit budget
(matches the approved design), and hiding the user's archive preference
while the instance switch is off (documented intended behavior).

---

## Feature: Instance management — update checker + full instance backup/restore

Requested as the Jellyfin/Navidrome-style instance-operator conveniences
Stash was missing: a "new version available" nudge, and a real disaster-
recovery/migration path beyond the per-user Stash JSON export. Both live
entirely under the existing session-cookie `/admin` surface, so
`openapi.yaml` needed no changes at all.

### Update checker

`UpdateChecker` mirrors `SiteSettingsService`'s app-level-cache pattern
(a lock-guarded `UpdateStatusCache` behind a `StorageKey`, seeded at boot)
and `WaybackSubmitter`'s detached-refresh pattern, rather than introducing a
third shape for "background thing with a cached result." It checks GitHub's
`releases/latest` API through the shared `app.client` (a GitHub API call
comfortably fits the app-wide 5s timeout; no dedicated `HTTPClient` needed,
unlike Wayback's `/save` endpoint), decoding just `tag_name` and `html_url`.
A container can't self-update, so the feature only ever surfaces "an update
exists" — the actual upgrade is still the same `docker/podman compose pull
&& up -d` documented in `Docs/backend-docker.md`; the Health page just
repeats that command inline once an update is detected.

`compareSemver` is a small pure function (parses `v1.2.3`/`1.2.3` into a
`(major, minor, patch)` tuple and compares) deliberately kept dependency-free
rather than pulling in a semver package for three integers. A `current`
version of `"dev"` (no `VERSION` file — a from-source build) never reports
an update, since there's no real released version to compare against, and an
unparseable tag on either side fails closed to "no update" rather than
risking a false positive.

Checking is on by default (`SiteSettings.updateCheckEnabled`, a new column
via `AddSiteSettingsUpdateCheck`, the same one-migration-per-column pattern
`AddSiteSettingsInternetArchive` already established) with an admin toggle on
the Health page, for the fully offline/air-gapped deployment case the
`192.168.1.x` local-network use case (§18) already anticipates elsewhere.
Both the dashboard and the Health page call `refreshIfStale` on render
(cheap: it's a no-op once a check is fresh, in flight, disabled, or under
`.testing`), so there's no need for a scheduled job — the same "only refreshes
when an admin is actually looking" trade-off the favicon cache already
accepted. `forceCheck` (the "Check now" button) is suppressed under
`.testing` for the same reason every other outbound call in this codebase is:
the test suite must never make a real network request.

### Full instance backup / restore

Deliberately a separate service (`InstanceBackupService`) from the existing
per-user `ImportExportRegistry`, since the two solve genuinely different
problems: `StashJSONExporter`/`Importer` are `userID`-scoped and reachable
from `/app` by any user, while this is instance-wide and admin-only. It does
reuse the per-user dedup rules verbatim (bookmark upsert by URL preserving
`createdAt`, Smart View upsert by name, `SmartViewController`'s existing
validators) so a restored library behaves identically to one built up
through normal use, and a bad individual record is counted in `skipped`
rather than aborting the whole restore — the same two-tier split
`StashJSONImporter` already established.

The backup file is deliberately more than a "personal export": it carries
password hashes, TOTP secrets, and recovery-code hashes verbatim (never
re-hashed on restore, since they're already hashed), because a backup that
didn't preserve logins wouldn't actually be useful for migrating to a new
server. That makes the file sensitive in a way the per-user export isn't;
the UI says so explicitly, and it's gated behind an authenticated admin
session, never exposed unauthenticated the way favicons are. Refresh tokens,
the favicon cache, and the audit log are deliberately excluded: the first is
session state (everyone just signs back in), the other two are regenerable
or purely operational.

Restore is a merge keyed by `username`, never a destructive replace — nothing
absent from the backup is ever deleted. The one property I was most careful
to get right: an **existing** user's account fields (password hash, TOTP,
role, active state) are never touched by a restore, only their
bookmarks/Smart Views are merged in. That single rule is what makes the
currently signed-in admin's own account self-lockout-proof by construction,
with no special-cased "is this the acting admin?" branch anywhere in the
restore loop — their account always already exists, so it can never fall
into the "new user, write auth fields verbatim" branch. A **new** username,
by contrast, is created with its backed-up role/active-state/password/2FA
written as-is, which does mean a restore can introduce a second admin
account or reactivate a suspended one — an accepted trade-off, since that's
exactly what a cross-instance migration needs to actually work.

The restore confirmation reuses the exact `DeleteAllBookmarksForm`-style
"type a word to confirm" pattern (`confirm == "restore"`, checked
server-side, never just a disabled button), and the upload route reuses the
same `body: .collect(maxSize: "16mb")` override the `/app` import route
already needed to raise past Vapor's default 16KB body cap.

### Code-review follow-up: transaction safety, batched queries, and misleading feedback

A review pass over the update-checker and instance-backup commits surfaced
several real issues, all fixed.

The most serious: `InstanceBackupService.restore` ran as a plain sequence of
individual saves with no transaction, and the web handler only caught its own
`InstanceBackupError`. Any other failure partway through (a dropped DB
connection, a constraint violation) left a half-restored instance committed,
surfaced as a raw 500 instead of a friendly banner, and left no audit-log
entry recording what had happened. The whole merge now runs inside one
`app.db.transaction { db in ... }`, so a failure anywhere rolls back every
write the call made; `SiteSettingsService.refreshCache` still runs after the
transaction commits, since it's an app-level cache update, not a DB write.

Restore also had its own version of the N+1 pattern this project has
deliberately avoided elsewhere: one dedup-lookup query per bookmark and per
Smart View, fully synchronous inside a single HTTP request — fine for one
user's import via `/app`, but this runs across every user in the backup at
once, and a real migration could plausibly carry thousands of records. Both
`export` and `restore` now preload each user's existing rows into an
in-memory dictionary once (keyed by URL / by name) instead of querying per
item; `restore`'s dictionary is kept up to date as new records are created
within the same call, so two records sharing a URL in one backup file still
merge correctly rather than hitting the unique constraint on the second
insert. `export` batches its three per-user queries (bookmarks, Smart Views,
recovery codes) into three total queries across every user, grouped in
memory, the same shape the transaction-scoped restore lookups now use.

Two smaller correctness fixes: the "Check now" button on `/admin/health`
always flashed "Update check complete," even when `UpdateChecker.forceCheck`
silently no-opped because checking was disabled or a check was already in
flight — `forceCheck` now returns whether it actually ran, the button hides
itself once checking is disabled, and a genuine skip gets its own distinct
flash rather than claiming success. And `UpdateChecker`'s semver `parse`
took only the leading numeric prefix of the patch component
(`Int("3rc".prefix { $0.isNumber })` → `3`), which could make a
qualified/pre-release tag silently compare as equal to a real release
instead of failing safe to "unparseable"; it now requires the whole
component to be a clean integer.

Two reuse cleanups: the GitHub repository path had been hardcoded twice with
inconsistent casing (`otaviocc/Stash` in `UpdateChecker`, `otaviocc/stash` in
`StashUserAgent`'s backlink); both now derive from one `StashRepo.path`
constant. And `InstanceBackupService` had its own private copy of the
ISO-8601-with-fractional-seconds parsing fallback, a third copy of a pattern
already duplicated between `StashJSONImporter` and `BookmarkController`; the
new copy was extracted into a shared `FlexibleISO8601.date(from:)` used by
`InstanceBackupService`. The other two pre-existing copies were left as-is —
both predate this feature and have no test coverage of their own, so
consolidating them was out of scope for this pass; `InstanceBackupService`'s
doc comment instead explicitly cross-references `StashJSONImporter` as the
sibling implementation its upsert rules deliberately mirror, so a future
reader knows to check both sides.

## `Script/bump-version.sh`: one script, three version numbers

Three version strings need to move together on every release and don't share
a format: `Backend/VERSION` (`major.minor.patch`, read at runtime by
`AppVersion.read` and baked into the Docker image), `CFBundleShortVersionString`
in the four `StashApp/Config/*-Info.plist` files (`major.minor`), and
`Extension/manifest.json`'s `version` field (Manifest v3 wants a
dotted-integer string; kept `major.minor.0` to mirror the app version rather
than tracking the backend). Hand-editing three files with three different
shapes on every bump is exactly the kind of thing that drifts, so
`Script/bump-version.sh --backend X.Y.Z --app X.Y` does all three in one run.

The app version is bumped in the committed Info.plist files, **not** the
`MARKETING_VERSION` build setting in `project.pbxproj`. `StashApp/Stash.xcodeproj`
sets `GENERATE_INFOPLIST_FILE = NO` for every target, so Xcode never
synthesizes `CFBundleShortVersionString` / `CFBundleVersion` from
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` — it just uses the checked-in
Info.plist verbatim, which makes that build setting dead weight and the
plist the actual source of truth. This also keeps the script consistent with
the existing rule against scripting `.pbxproj` rewrites (see the XcodeGen
removal entry above): it never touches the project file at all. The script
edits the version line with a targeted `sed`, not `PlistBuddy -c Set` —
PlistBuddy rewrites and alphabetizes the *entire* plist on save, turning a
one-line version bump into a large, unreviewable diff.

It deliberately does **not** touch `CFBundleVersion` (the build number) —
that increments independently of the short version, so bumping it is a
separate, manual step. It also doesn't tag or commit anything; see
`Docs/releasing.md` for the tagging step that follows.

---

## Editable footer links

The footer previously showed three hardcoded links (GitHub, Mastodon, Ko-fi)
plus one optional custom link (`footerCustomLabel` + `footerCustomURL`). The
hardcoded approach was originally chosen so the Stash identity couldn't be
accidentally omitted or overridden by an admin (see the "Site Settings &
Admin Customization" entry above), but in practice every instance that isn't
the original developer's wants its own links — a different GitHub repo, a
different support link, no Ko-fi at all — and the only way to change them was
editing the Leaf template directly.

All footer links are now fully editable by the admin through four label+URL
slots, stored as a JSON array in a new `footerLinks` column on `SiteSettings`.
The migration (`AddSiteSettingsFooterLinks`) provides backward-compatible
defaults: GitHub, Mastodon, Ko-fi, and one empty custom slot. The
`FooterLink` struct (`label: String`, `url: String`) is a simple Codable
value type, not a new model — it lives entirely inside `SiteSettings` as a
JSON column, same pattern as Smart View conditions. URLs are validated for
`https://` on save; empty slots (both label and URL empty) are hidden from the
rendered footer.

The admin appearance page now shows four editable rows in a grid layout
matching the about-text and theme sections, each with label and URL fields.
Backup restore handles old backup files that still carry the legacy
`footerCustomLabel`/`footerCustomURL` fields: those values are migrated into
the fourth footer link slot on restore, so restoring from a pre-editable-links
backup doesn't silently lose the custom link.

## Appearance audit log: record actual changes

The audit log entry for appearance updates previously always logged
`"accent theme: {theme}"` regardless of what the admin actually changed. An
admin who only edited the about text or footer links still appeared to have
changed the accent theme. The detail now records what actually changed:
`"accent theme: {theme}"` when the theme changed, `"{n} footer links updated"`
when footer links changed, and `"about text updated"` when the about text
changed, with `"no changes"` logged when nothing actually differed. This
follows the same principle as other audit entries: the detail should let an
operator understand what happened without needing to inspect the
before/after state.

## Public `GET /api/v1/instance` endpoint

The accent theme was resolvable only inside a web request, via
`Request.siteChrome()` reading the `SiteSettingsCache` — fine for Leaf
templates, useless for the native apps, which never render Leaf and have no
concept of `Request`. Rather than build a client-side theme picker duplicating
the backend's `AccentTheme` catalog, I added one small public endpoint,
`InstanceController` at `GET /api/v1/instance`, returning the same resolved
`{ theme, light, dark }` the web chrome already computes — reusing
`AccentTheme.theme(for:)` against the same `SiteSettingsCacheKey` snapshot, so
it costs no extra database hit and stays in lockstep with whatever the admin
last saved.

It's deliberately unauthenticated, registered on `api` next to the favicon
route rather than behind `AccessTokenAuthenticator`: the accent is instance
chrome, not user data, and an unauthenticated read lets even the login screen
(and native apps before sign-in) pick up the instance's branding. The response
nests the theme under an `accent` key (`{ accent: { theme, light, dark } }`)
rather than flattening it, so the endpoint can grow to cover other instance
chrome later (about text, footer links) without a breaking shape change.

## Bug: unchecking a form's only checkbox 422'd instead of saving

Turning Internet Archive submissions off from `/admin/internet-archive`
(and, it turned out, the update-check toggle and the per-user archive
preference — the same pattern, three places) failed with a JSON
`validation_failed` / `422 Unprocessable Entity` instead of saving. The
handlers themselves were fine: `req.content.decode(...)` into a
`Bool?`-only form and coalescing a missing key to `false` correctly
handles an unchecked checkbox that simply isn't present in the submitted
fields. The bug was one level down — when a checkbox is a form's *only*
field, unchecking it means the browser POSTs a **completely empty** body
(zero bytes), not a body missing just that key. Vapor's `Request.content.decode`
guards on `request.body.data` before invoking any decoder and throws
`Abort(.unprocessableEntity)` with no reason when the body is empty, which
`StashErrorMiddleware` (applied globally, including `/admin` and `/app`
HTML routes, not just the JSON API) serializes as
`{"code":"validation_failed","message":"Unprocessable Entity"}` — a
generic, unhelpful message that gave no hint the real cause was an empty
body, not a validation rule.

The existing test for the toggle (`adminToggleDisables`) never caught this
because it encoded a dummy `_unused` field to avoid sending a truly empty
body — accidentally testing a request shape a real browser never sends.
Reproducing the bug required posting with no body at all (but the real
`Content-Type` header a browser always sets even on an empty POST).

Fixed at the request layer, not the template: a new `Request.decodedCheckbox(named:)`
helper (`Request+RenderHTML.swift`) checks `body.data`'s byte count before
decoding, treating a zero-byte body the same as a body that decodes but is
missing the key — both mean "unchecked". This is more robust than the
alternative (adding a hidden dummy field to each Leaf form so the body is
never empty): it fixes the three existing single-checkbox forms in one
place and any future one, without depending on every form remembering to
carry a decoy field. The three now-unused `Bool?`-only DTOs
(`InternetArchiveToggleForm`, `UpdateCheckToggleForm`, `ArchivePrefForm`)
were deleted along with the switch to the helper. Added a genuinely-empty-body
regression test alongside each of the three existing toggle tests, since the
existing ones (with their dummy field) would keep passing even if this
regressed.
