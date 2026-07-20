# Stash Decisions: Web Frontend & Admin Dashboard

_Part of the Stash Decision Log. See [`DECISIONS.md`](../DECISIONS.md) for the index and the full list of topical files. Entries are in original chronological order within this file._

---

## M11: User-facing web frontend

The frontend gets its own session cookie (`stash_session`, scoped to `/app`),
separate from the admin dashboard's but sharing the same in-memory store
underneath, and admits any active account regardless of role: suspended
accounts are rejected either way. Both web sections reuse one base
`layout.leaf` template with inline CSS; the page title prefix just switches
between "Stash Admin" and "Stash" depending on which section is rendering.

The add-bookmark flow is two buttons and no JavaScript: "Fetch metadata"
previews the title and description via an inline server-side fetch, "Save"
persists (auto-fetching any fields still blank). A duplicate URL shows an
inline error linking to the existing bookmark. The edit form deliberately
doesn't allow changing the URL at all: that sidesteps duplicate-handling
there entirely.

2FA setup shows the `otpauth` URI and a manual setup key rather than a
scannable QR code: rendering a QR server-side would need a QR-encoding
dependency, and CoreImage isn't available on Linux, which conflicts with
keeping the backend dependency-light. Manual entry is fully functional; a QR
image is a possible later addition.

Two Leaf gotchas I ran into and wrote down so I wouldn't relearn them:
`#if(count(x))` doesn't coerce an `Int` to `Bool` (`count 0` reads as
truthy, so it always needs to be `#if(count(x) > 0)`), and inline
conditionals require the colon (`#if(cond): … #endif`).

---

## Frontend improvements (post-M11)

Self-service 2FA disable requires a current TOTP code, not just a password:
that proves the user still controls their authenticator before 2FA comes
off. An admin-triggered 2FA reset also revokes the user's refresh tokens now,
since their account's security posture just changed and that should force a
re-login; self-reset is still allowed with no extra confirmation, since the
admin action itself is confirmation enough.

Tag autocomplete on the web needed zero new requests: the user's existing
tags are embedded as a JSON array in a `data-known-tags` attribute on the
create/edit forms (single-quoted, so Leaf's HTML-escaping of the JSON quotes
survives and the browser can entity-decode it before `JSON.parse`), and a
small, dependency-free vanilla JS block filters the comma-segment under the
cursor against it. I later fixed the matching itself: the original filter only
matched when the typed fragment prefixed the *whole* tag string, so typing
`music` never surfaced `kind/music-gear`. It now splits each candidate on `/`
and matches if any segment starts with the fragment: deliberately
segment-prefix, not a free substring search, so it stays aligned with the
`/`-delimited hierarchy the rest of Stash is built on. One line changed in
`layout.leaf`; the edit form shares the same script and got the fix for free.

The add-bookmark form also learned to accept an optional `?url=` query
parameter that pre-fills the URL field, useful groundwork for a browser
bookmarklet that opens Stash with the current page ready to save. It only
pre-populates; nothing auto-submits, so a crafted link can't silently add a
bookmark on its own; the user still has to click Save.

---

## Import / Export

The importer/exporter architecture is a pluggable registry: both protocols
expose static metadata (identifier, display name, file extension, MIME type
for exporters) plus one instance method each, and a singleton
`ImportExportRegistry` holds whatever's registered. The settings UI and the
import/export routes are driven entirely off that registry, so adding a new
format is conforming a type and adding one registration line: no controller,
route, or template changes needed. Each importer owns its own data
consistency end to end: validation, duplicate handling, and bumping the
denormalized bookmark count, so the controller stays a thin orchestrator and
behavior doesn't depend on the caller.

I split failures into two tiers: a file that can't be parsed at all throws
and the settings page re-renders with an inline error, while individual bad
records (a missing or invalid URL, say) are counted and described rather than
thrown, surfaced afterward in a collapsible details block. Preserving
`createdAt` on import took a small workaround, since Fluent's create path
unconditionally touches timestamps on insert, so a pre-set `createdAt` gets
overwritten, and I restore it with a follow-up save (an update only touches
`updatedAt`, leaving the re-set `createdAt` alone). Duplicate-URL updates
never touch `createdAt` for the same reason.

Anybox's actual export shape turned out to differ from what I'd assumed
writing the spec, which I only caught by testing against a real export file.
`tags` is actually `[[String]]` (arrays of `[namespace, value]` pairs), not
a flat `[String]`; each pair joins with `/` into a hierarchical Stash tag,
which happens to be a natural fit for Stash's own slash-hierarchy (a plain
`[String]` is still accepted as a fallback, and the original decoder just
threw a confusing type-mismatch error before this fix). And the date field is
`dateAdded`, camelCase, an ISO-8601 string, not `date_added` as a Unix
integer, though that's accepted as a fallback too, with the current time used
if it's missing altogether. I verified all of this against a real
211-bookmark export: everything imported, and re-importing the same file was
idempotent.

Export is the native format and deliberately complete: a versioned
`{ version, exportedAt, bookmarks[] }` payload with every bookmark including
archived ones, sorted by `createdAt`. A successful import redirects with
Post/Redirect/Get and flashes the full result (including the skipped-record
descriptions, too large for a query string) through a one-shot session
value. I had to raise the upload body limit for the import route, since
Vapor's default 16KB collected-body cap would reject any real export file.
Registering the Stash-JSON importer for backup restore and round-tripping was
a genuine one-line change in the registry, which was a nice validation that
the pluggable design actually works the way I intended.

---

## Tag sidebar (bookmark list)

Leaf has no clean recursion, so the tag tree is built server-side into a flat
list carrying a depth per row, and the template just indents each row
proportionally. Sorting all tag slugs by their `/`-split path components
turns out to already be a pre-order depth-first traversal for free: a parent
always precedes its subtree, siblings stay alphabetical at every level. If
only `swift/vapor` exists, `swift` still gets synthesized as a parent node
with a zero count (hidden in the template) so children always have something
to nest under, and it stays clickable, since `?tag=swift` still prefix-matches
everything under it. Counts are exact literal-tag counts, matching `/app/tags`
rather than a prefix aggregate, reusing the same bookmark query the page
already runs rather than a separate aggregate query.

Getting the sidebar's positioning right took a couple of false starts. I
tried `sticky` first, which scrolled away once past its parent's height, then
`fixed`, which needed brittle viewport-anchored offsets and felt detached
from the content. What I actually wanted was much simpler: a normal
two-column layout where both columns scroll together as one unit, so the
final CSS has no `position`/`overflow`/`max-height` rules on the sidebar at
all, just a plain flex row. The "Tags" heading gets a `margin-top` derived
from the page's own pinned heading metrics (not a guessed number) so it lines
up with the search field instead of the page's `h1`.

The "Untagged" filter works through an internal sentinel,
`?tag=__untagged__`, special-cased ahead of the normal prefix path to filter
on an empty `tagsSearch`; "Today" and "This Week" followed the same pattern
for recency filtering, reusing the existing `tag` query parameter rather than
inventing a new one, which meant they inherited all the existing pagination
and filter-banner plumbing for free. Week start is Monday, computed with one
shared date-boundaries helper so the filter and the sidebar's own counts can
never disagree with each other.

One bug worth recording: the `__untagged__` sentinel was honored by the web
UI but not the JSON API. The macOS app's "Untagged" sidebar entry correctly
requested it, but the bookmark controller had no sentinel branch and just
fell into the normal prefix path, where the sentinel got normalized into a
literal tag no bookmark actually carries, so the API always returned empty,
silently, while `/app` worked fine. The two controllers only shared the
sentinel *constant*, not the filter *expression*, which is exactly what let
them drift apart. I fixed the immediate bug by adding the missing branch to
the API controller, and later closed the underlying gap for good when I added
the recency sentinels: the whole sentinel-plus-prefix filter now lives in one
shared query-builder helper that both controllers call, so there's no
duplicated expression left to drift.

The sidebar eventually got split into two labeled sections: "Views" over the
smart filters (All, Untagged, Today, This Week) and "Tags" over the
hierarchical tree, since they'd grown into one undifferentiated list that
mislabeled the filters as tags.

---

## Dark mode (web frontend + admin dashboard)

Theme preference (light, dark, or auto, defaulting to auto) lives entirely
in a one-year `stash_theme` cookie at path `/`, so it covers both `/app` and
`/admin` with no model field or migration at all; it's a pure presentation
concern. The cookie is deliberately not `HTTPOnly`, since an inline
flash-prevention script needs to read it before first paint and set
`data-theme` on `<html>` synchronously: otherwise there'd be a visible flash
of the wrong theme on load. All colors became CSS custom properties, with
dark values defined under both an explicit `data-theme="dark"` selector and a
`prefers-color-scheme: dark` media query for auto mode, so an explicit choice
always wins over the OS preference. Because both web sections share
`layout.leaf`, this theming applies to `/admin` automatically with no
admin-specific work: it's only ever *settable* from `/app/settings`. The
dark palette follows iOS's dark mode rather than pure black: background
`#1c1c1e`, surface `#2c2c2e`, accent `#0a84ff`.

---

## Danger zone: delete all bookmarks

The confirmation phrase ("delete all") is re-checked server-side on submit,
not just gated by disabling the button client-side until the input matches:
that client-side check is a convenience, never the actual gate. Deleting is
scoped to bookmarks only: it resets the bookmark count to zero but leaves the
account, password, 2FA, and any tag metadata (which is derived from
bookmarks anyway) untouched.

---

## Tag renaming

Both the JSON endpoint and the web form call the same `TagRenamer.rename`,
so behavior can't drift between them. Renaming finds candidates via the
`tags_search` prefix match, then a pure transform renames the exact tag and
rewrites every `from/x` to `to/x`, de-duplicating so merging into an
existing `to` never stores the same tag twice. On the web, each tag row gets
an inline rename form revealed by a small toggle, with a Post/Redirect/Get
banner built from the response. Tag renaming isn't actually in `PRODUCT.md`;
I added it on request, beyond the original spec.

## Tag deletion

Mirrors renaming exactly: shared `TagDeleter.delete` logic behind both the
JSON `DELETE` endpoint and a web `POST` sub-route (since HTML forms can't
issue `DELETE`), the same prefix-match candidate query, and a pure transform
that drops the exact tag and any children while leaving a look-alike like
`foo-barbaz` untouched, since there's no slash boundary there. A bookmark
whose only tag gets deleted survives with an empty tag list: bookmarks are
never deleted, only their tags. Same web pattern as renaming: an inline
confirmation toggle, PRG, a banner built from the response. Also beyond the
original spec, added on request.

## Editable server URL on the login screen

A self-hosted instance reached by IP can change address, and there was no
in-app way to fix that on iOS once the app was configured but pointing at an
unreachable server: logging out just returned to a login screen that only
*displayed* the URL as footer text. `LoginView` now carries its own editable
server field. It's edited locally and only committed to `AppSettings` on
actual sign-in, rather than bound directly: binding it straight to the
persisted setting would have flipped `isConfigured` to false the instant the
field was cleared mid-edit, bouncing the user back to first-launch setup.
Nothing needed to change further down the stack, since the client provider
already rebuilds its cached client whenever the persisted URL changes.

---

## Cross-links between the `/app` and `/admin` web navs

The user-facing frontend's nav gained a "Dashboard" link to `/admin`, so an
admin browsing their own bookmarks can cross over without retyping the URL:
shown only when the signed-in user is actually an admin, since the admin
section is role-gated and would otherwise be a dead end for a regular user.
The reverse link, an "App" entry in the admin nav pointing back to `/app`,
needed no such gating at all: only admins ever reach the admin dashboard in
the first place, and every admin also has their own regular `/app` account
since both web UIs share one user table, so that link is never a dead end.

---

## Appearance theme swatches respect dark mode

Every accent theme carries both a light and a dark hex value, but the
appearance picker's swatches were hardcoded to always show the light value,
so in dark mode the circles displayed the wrong colors while the rest of the
page was dark around them. The fix mirrors the same three-way resolution
already used for the injected accent override elsewhere: each swatch now
sets both light and dark custom properties inline, and CSS resolves which
one to actually show based on the active theme, so the preview always
matches what the app actually renders.

---

## Tags & Smart Views web UI: table layout and delete confirmation

The Tag Browser page now renders as a table matching the Smart Views
management page's layout, so the two read as one consistent surface instead
of two different visual patterns for what's conceptually the same kind of
page. One small CSS wrinkle: a table with only short cells stretches its
last column and leaves an awkward gap after the action buttons, which the
Smart Views table never showed because its wide conditions column already
absorbed the slack: the fix was just pinning the tag column to take the
slack instead, no layout change needed on the Smart Views side.

Delete also switched from an inline-reveal confirmation form to a native
`confirm()` dialog on both pages, the same pattern already used for deleting
a bookmark. The old inline-reveal approach mutated the table in place and
reflowed the row while open, which felt like something shifting underfoot;
a native confirm dialog never touches the table before the actual submit.

---

## Public landing page at `/`

Before this, the root path just returned a bare 404: the only real entry
points were `/app` and `/admin` directly. The landing page that replaced
that 404 is a straightforward product pitch reflecting the self-hosted,
data-ownership philosophy: a hero line, two calls to action (sign in, or the
admin dashboard, the latter visually secondary), and a small feature grid
that collapses to one column on narrow screens. It reuses the shared layout
template wholesale rather than inventing new chrome: the nav header is
already gated on whether a username is set, which is never true for an
anonymous visitor, so the layout degrades gracefully with no extra work.

One bug I introduced and then reverted: I initially tried to redirect a
signed-in visitor straight to `/app` from the landing page, by reading the
session cookie at `/`. That backfired badly: the session cookie is
path-scoped to `/app`, so a browser never actually sends it to `/` in the
first place, but merely *reading* the session there created a fresh empty
one, and the sessions middleware then wrote that empty session's cookie back
with `Path=/app`, silently overwriting the visitor's real session. Visiting
the homepage was quietly logging people out of the app. I removed the
redirect and all session access from the landing route entirely: it's now
a pure, stateless render for everyone, signed in or not. The trade-off is
that a signed-in user who navigates to `/` sees the landing page instead of
bouncing straight to `/app`, which felt like the safer choice compared to
the alternative of widening the session cookie's path just to power a
cosmetic redirect.

The admin's optional "about this instance" text does double duty here too:
the same field that already populates the shared footer also renders as a
card on the landing page when set, with no new settings field needed. The
feature grid itself got a refresh once the page had fallen behind the
shipped product: it originally only mentioned four things and never
name-checked the CLI, the browser extension, 2FA, import/export, or
theming, so it grew to six cards covering all of it, plus a third CTA once
the OpenAPI docs became browsable, linking straight to `/docs.html`.

---

## Web CSS and JS extracted to static assets

Every style used to live inline in `<style>` blocks scattered across the
Leaf templates: one large shared block plus several per-page blocks that
had accumulated as pages were built. I moved all of it into static `.css`
files served by a `FileMiddleware`, registered once and falling through to
the router when no file matches, so the API and web routes stay completely
unaffected. The shared stylesheet is linked once in the layout's `<head>`;
each page that needs extra styles provides them through a small
Leaf import/export slot, and pages that don't need one just render nothing
there: Leaf silently drops an unmatched import rather than erroring, which
I confirmed against the Leaf source before relying on it.

The one thing that deliberately stays inline is the accent-theme CSS
override, since it's templated per request from the site settings cache and
genuinely can't be a static file; same story for the flash-prevention
script that sets the theme attribute before first paint, which has to run
inline and un-deferred or the whole point of preventing a flash is lost.
Every other inline `<script>` block moved to static JS files the same way:
none of them actually referenced Leaf template variables, they all just read
DOM attributes or queried the DOM directly, so externalizing them was
mechanical. All the extracted scripts load with `defer`, in document order,
so the shared tag-autocomplete script (which several page scripts depend
on) always finishes loading before anything that needs it.

---

## Offline Sync: landing page copy

The public landing page predated offline sync entirely and still described
the native apps with no mention of local storage or syncing at all. I
updated the hero copy to say the apps "work offline," and rewrote the
platform feature card to spell out the actual differentiator: a full local
copy of the library, browsing and saving while offline, automatic sync on
reconnect. I folded this into the existing platform card rather than adding
a seventh feature card, specifically to keep the feature grid's balanced
three-by-two layout intact.

## Visual polish: bookmark list mirrors the native row (web frontend)

The web bookmark list picked up the same content-first row hierarchy the
native apps got: a presentation-only pass on the existing template, no new
fields or backend changes. The prominent full-URL line under each title is
gone, replaced by a quieter domain line (favicon plus domain) sitting above
the title instead, mirroring the native row's domain-as-anchor treatment,
while the title still links through to the bookmark's detail page and the
domain itself links straight out to the URL. Tags in the row lost their
filled capsule background in favor of plain muted text, matching the
native row's quieter list-context treatment: the capsule style itself is
untouched everywhere else it's used, like the tag browser. Per an explicit
product decision, the web row keeps its bordered card container and keeps
showing the date the native row omits, since the web is
inherently a denser reading surface than a phone screen.

## Instance management: landing page copy

The same "the feature grid fell behind the shipped product" gap the
offline-sync entry above describes repeated itself here: the "A real admin
toolkit" feature card still only listed the pre-existing admin pages (health
checks, database optimize, favicon cache, audit log, sessions, logs) with no
mention of the update checker or instance backup/restore. Folded both into
that existing card rather than adding an eighth, for the same
balanced-grid reason as the offline-sync entry. Updated in two places: the
live `Backend/Resources/Views/landing.leaf` template and the static mirror
committed to the `gh-pages` branch (`index.html`, used for GitHub Pages
hosting since it can't run Vapor) — the two aren't automatically kept in
sync, so a shipped feature-grid change always needs a matching edit on
`gh-pages` or the public landing page silently drifts from the one the
backend actually serves.

## WebUI favicon placeholder

When a favicon isn't cached for a domain, the API returns 404 and the
bookmark list row showed nothing — just the domain text with no icon. The
`onerror` handler now swaps the `<img>` src to a static ribbon placeholder
SVG (`/favicon-placeholder.svg`) instead of hiding the element. This keeps
every bookmark row visually consistent regardless of favicon status. The
backend intentionally stays unchanged: returning a placeholder from the API
would risk clients caching a temporary icon, so the fallback lives purely
in the WebUI layer.

## Accent-aware button text contrast

`--btn-text` was hardcoded to `#ffffff` everywhere, which broke light
accent themes (sunny, gold, coral): white text on a pale yellow or orange
background has far too little contrast.

The first attempt used `oklch()` relative color syntax to derive
`--btn-text` from `--accent` in pure CSS:
```css
--btn-text: oklch(from var(--accent) calc(l > 0.6 ? 0.15 : 0.95) c h);
```
This was silently discarded by browsers that don't support the spec yet —
the declaration vanished without error, leaving `--btn-text` at its
inherited `#ffffff` and producing no visible change.

Replaced with a small synchronous inline script in `layout.leaf` that
reads the computed `--accent` (which already reflects the admin-configured
theme and the active light/dark mode), computes WCAG relative luminance,
and sets `--btn-text` to `#1a1a1a` or `#ffffff`. The script runs after
the accent-override `<style>` block and before paint, so there is no
flash of wrong text color.

A secondary fix was needed for `.secondary` and `.danger` buttons: the
base `button` rule sets `color: var(--btn-text)`, and those variants only
overrode `background`. The contrast calculation for the accent produced a
dark text color that was wrong for their dark-gray and red backgrounds.
Added explicit `color: #ffffff` to both variants, since their backgrounds
are always dark regardless of the accent theme.

---

## Anybox exporter and an explicit default format

Added an Anybox JSON exporter as the inverse of the existing importer, which
confirmed the pluggable registry claim a second time: a single
`register(exporter:)` line, no controller/route/template change. The export is
deliberately lossy — Anybox has no archived-bookmark or Smart View concept, so
`isArchived` is dropped and Smart Views are omitted, and tags are written as a
plain `[String]` (e.g. `topic/swift`) rather than reconstructing Anybox's
`[[namespace, value]]` pairs. That plain shape is exactly the fallback the
importer already accepts, so a Stash → Anybox → Stash round-trip preserves tags;
splitting back into pairs would guess a namespace boundary that Stash doesn't
actually store.

Registering a second exporter exposed a latent bug in the format selectors: the
default was purely positional (the first `<option>`), and the options render in
`displayName` alphabetical order. With only "Stash JSON" registered that was
harmless, but "Anybox JSON" sorts first, so it would have silently become the
default for both import and export. Made the default explicit instead — the
settings context now carries `defaultImporter`/`defaultExporter` (both
`stash-json`) and the template marks the matching `<option selected>`, the same
pattern the logs page already uses. Stash JSON is the sensible default: it is
the lossless, round-trippable, restore-from-backup format; Anybox is a
migration convenience.

I also backfilled the first import/export tests here (there were none): both
importers, both exporters, and an export→import round-trip for each format,
which is what caught the positional-default regression before it shipped.

---

## Bookmark detail: preserve list return context (`returnTo`)

The bookmark detail page's "← Back to bookmarks" link and its Delete redirect
were hardcoded to `/app`, so opening a bookmark from a tag or Smart View and
going back (or deleting it) dropped the user onto the unfiltered list instead
of where they came from. Scope was explicitly widened beyond just back/delete:
the return context now survives every detail-page action (Edit, Refresh
favicon, Wayback, Archive/Unarchive), not just the first page load, so the
back-link keeps pointing at the originating list for as long as the user stays
on that bookmark.

Implementation carries the originating list URL as a `?returnTo=` query
param, reusing existing building blocks rather than inventing new ones:
`BookmarkPresenter.listURL` / `SmartViewPresenter.smartViewListURL` (already
used for pagination) build the raw URL, and `TagPresenter.queryValue` (already
used for sidebar tag hrefs) percent-encodes it for embedding in another query
string. Every link/form into or within the detail page carries `returnTo` in
its URL; every handler reads it back via `req.query` — no new hidden form
fields or `Content` structs needed, since POSTs can carry their own query
string on the `action` URL independent of the form body.

Since `returnTo` is user-controlled and used as a redirect target, added a
`safeReturnTo` guard — the first redirect-target validation in this codebase,
as none of the existing hardcoded `req.redirect(to:)` calls needed one. Falls
back to `/app` on anything that doesn't look like a local `/app` path.

A code review of the first version turned up four real issues, all fixed:

- `safeReturnTo` separately rejected values containing `//` or `://` on top of
  requiring the `/app` prefix. That extra check was actually redundant (a
  string starting with `/app` can never be an absolute or protocol-relative
  URL — neither can start with a single `/`) *and* actively harmful: a bookmark
  search for a URL-shaped term (`?q=https://example.com`) produces a
  perfectly safe, locally-scoped `returnTo` that still contains the substring
  `://`, so the guard silently discarded it and fell back to `/app` — the
  exact context loss this feature exists to fix. Removed the `//`/`://` checks
  entirely; the `/app` prefix requirement alone is sufficient.
- The guard had no defense against embedded control characters, so a crafted
  `returnTo` could inject a CR/LF into the eventual redirect `Location`
  header. Added an explicit rejection — but the first attempt
  (`!raw.contains("\r"), !raw.contains("\n")`) missed a *combined* CRLF
  sequence entirely: Swift merges `"\r\n"` into a single extended grapheme
  cluster, so a `Character`-based `contains("\r")` doesn't match it (neither
  `Character` equals the cluster). A test exercising exactly this payload
  caught it; the fix scans `unicodeScalars` instead, which sees the raw CR and
  LF code points independently of grapheme clustering.
- The "Add bookmark" page's duplicate-URL conflict link ("View the existing
  bookmark →") was the one entry point into the detail page this diff missed
  — carried no `returnTo`, unlike every other link/form into it. Fixed the
  same way as the rest: `AppNewBookmarkContext` now carries `returnURL`/
  `returnToParam`, threaded through both the initial GET and the POST
  re-render-on-conflict path.
- Backfilled test coverage for the whole mechanism (none existed): the back
  link honoring/rejecting `returnTo`, the `://`-in-search-text and CRLF cases
  above, delete redirecting to the preserved list (with and without
  `returnTo`), and an action (archive) re-attaching `returnTo` to its
  detail-page redirect.

A follow-up cleanup pass (still no correctness bugs, just quality) replaced
`detailRedirect`'s manual `"?" + items.joined(separator: "&")` string-building
with `URLComponents`/`URLQueryItem`, matching the pattern `BookmarkPresenter`/
`SmartViewPresenter` already use, and added a `returnContext(_:)` helper to
stop deriving the `(returnURL, returnToParam)` pair separately at each of its
4 call sites. Also considered and declined: a Leaf partial to enforce
`returnTo` on every future detail-page link (real gap, but needs new
Leaf-tag infrastructure — out of scope for a cleanup pass); extracting the
new tests' repeated Given-block setup (checked against `WaybackTests.swift`
and confirmed it matches this repo's existing test-file convention of
explicit, un-factored Given blocks).

---

## Add-bookmark page: return context via Referer, plus tag pre-fill

The "Add bookmark" page's own "← Back to bookmarks" link was fixed to read
`returnURL` in the pass above, but never actually received one: neither entry
point into `/app/bookmarks/new` — the global nav "Add" link (`layout.leaf`,
present on all 24 web-app pages) nor the list's empty-state "Add your first
bookmark" link — carried `?returnTo=`. The user also wanted the active tag
pre-filled into the new bookmark's tags field, since the page now knows what
was being browsed.

`layout.leaf` only receives `title`/`appUsername`/`appIsAdmin`/`chrome`/
`adminUsername` — no page-specific state. `chrome` (`SiteChrome`) is
confirmed instance-wide cached config built from admin `SiteSettings` with no
request access, so it's the wrong seam for per-request nav state. Threading a
new field through every context struct that extends layout (~25 structs,
~33 construction sites, only 1 of which — `app-bookmarks.leaf` — has any tag
concept) would be disproportionate to fixing one link.

Instead, `safeReturnTo` now falls back to the `Referer` header when no
`returnTo` query param is present (`returnToCandidate(_:)`, extracting
`path` + `query` from `Referer` via `URLComponents`, then running through the
same validation). The nav "Add" link is a plain same-origin `<a href>`, so
the browser already sends the right `Referer` with zero template changes.
Considered — and rejected — making `Referer` the *only* mechanism, dropping
`returnTo` entirely: `Referer` only names the immediately preceding page, so
it works for a single hop (list → new-bookmark) but breaks the detail page's
own actions, whose `Referer` is the detail page itself after the first hop,
permanently losing the original list. The two mechanisms are complementary,
not redundant: explicit `returnTo` for anything that must survive multiple
hops (the detail page), `Referer` fallback for single-hop links that would
otherwise need context threaded through unrelated pages. Also explicitly
decorated the empty-state link (it already has `returnToParam` in scope) as a
fallback for browsers/extensions that strip `Referer`.

Tag pre-fill (`tagFromReturnURL(_:)`) extracts the `tag` query item from the
resolved return URL and normalizes it via `Bookmark.normalizeTagQuery`,
excluding the three sentinel filters (`__untagged__`/`__today__`/
`__this_week__` — not real tags). A Smart View return URL has no `tag` item
at all, so nothing is pre-filled there, correctly — a Smart View doesn't
correspond to one tag. Only wired into the initial GET (`newBookmarkForm`);
`createBookmark`'s conflict/preview re-render already carries forward
whatever the user submitted in the `tags` field, so the pre-filled value
round-trips for free once it's a real form value.
