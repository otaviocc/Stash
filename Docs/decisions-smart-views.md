# Stash Decisions: Smart Views

_Part of the Stash Decision Log. See [`DECISIONS.md`](../DECISIONS.md) for the index and the full list of topical files. Entries are in original chronological order within this file._

---

## Smart Views

Each Smart View carries a match mode, `all` (AND) or `any` (OR), mirroring
macOS Music's "Match all/any of the following rules." There's still no
per-rule grouping or a full boolean-expression parser; one global combinator
covers the large majority of "saved query" use cases without needing a query
DSL. The non-archived default is applied as an outer AND regardless of match
mode, so an `any` Smart View can't accidentally leak archived bookmarks just
because one OR-branch happens to match: surfacing archived results still
requires an explicit `isArchived` condition. That logic lives in exactly one
place, shared by both the web results page and the API, so the two can't
drift.

Conditions are stored as a JSON array of `{ type, value }` objects: a
discriminated union where every value is a string (dates ISO-8601,
`isArchived` as `"true"`/`"false"`), which means adding a new condition type
is a code-only change with no schema migration. Adding the `hasTags`
condition later was exactly that: no migration, no StashKit change, just
reusing the existing derived tags column. One real production bug here: I
initially stored the conditions array directly, which worked fine against
the SQLite test database but failed against real PostgreSQL, since Fluent's
Postgres encoder serializes a top-level Swift array differently than a
`jsonb` column expects: a textbook case of the SQLite test database not
catching something Postgres would reject. Wrapping the array in a one-field
container struct made Fluent emit a single valid document on both drivers; I
verified the fix against a real PostgreSQL instance, not just the test
suite, specifically because the test suite was what had missed it in the
first place.

Text conditions (`urlContains`, `titleContains`, `descriptionContains`)
reuse the same portable case-insensitive `LIKE` helper full-text search
already uses. The `tag` condition reuses the bookmark list's exact
prefix-match semantics, so a Smart View tag filter behaves identically to
the sidebar's tag filter, matching a tag and its descendants the same way.
Smart Views render in the sidebar with no count shown at all: a count would
mean actually running every saved query on every page render, which isn't
worth it for a convenience list. Management lives as its own top-level nav
item between Tags and Settings; I'd initially tucked it under Settings, but
promoted it once it was clear Smart Views are a first-class browse/organize
surface alongside Bookmarks and Tags, not a settings tweak. StashKit's
addition here followed the same thin-package rule as always: DTOs and a
request factory, no client-side state, no CLI or native-app surface added in
this pass.

---

## Smart View import / export

Smart Views ride the existing Stash JSON export as an optional sibling array
next to bookmarks, rather than a new file format: the node is optional on
import, so older exports without it still import fine, and the format
version doesn't need to bump at all. A Smart View whose name already exists
for the user gets updated in place; otherwise it's created, mirroring how
bookmark dedup works by URL, which makes re-importing the same file
idempotent. Validation is reused rather than reimplemented: the importer
calls the exact same validation the API uses, so an imported Smart View is
held to identical rules as one created directly. A Smart View with an empty
name or no valid conditions gets counted and reported rather than thrown,
the same parse-failure-vs-bad-record split bookmarks already use.

The CLI reaches parity here over the public API: `stash export` folds Smart
Views into its local export document, and `stash import` submits each one
via create or update, matched by name. Like bookmarks, the CLI can't
preserve a Smart View's original `createdAt` timestamp over the public API:
the same accepted limitation from M7. One thing I had to get right on the
CLI side: per-record validation failures should be reported and skipped, but
a connectivity or auth failure partway through an import should abort the
whole batch rather than silently counting every remaining record as
"skipped": that would make a recoverable failure look indistinguishable
from bad data. A shared error classifier now splits the two cases correctly,
applied consistently to both bookmarks and Smart Views on the CLI.

---

## Smart Views on the CLI and native apps (consumption-only)

Smart Views already existed on the backend, in StashKit, and on the web.
This pass brought them to the CLI and the iOS/macOS apps as a
consumption-only first step: list Smart Views and open their live
results: deliberately leaving create/edit for later, since anyone who wants
to author one can still do it on the web or round-trip it through Stash JSON
import/export. No backend or StashKit change was needed at all; everything
required was already in place.

On the CLI, `stash smart-views` prints a table of name, match mode, and a
condition summary, with the full UUID last rather than truncated, since it's
the direct input to the next command; `stash smart-views bookmarks <id>`
runs the saved query and prints results in the same shape `stash list`
already uses. On the apps, a small `SmartViewRepository` mirrors the
existing tag repository: a shared, cached, per-user list rather than a
paginated query, reset on sign-out alongside the tag cache.

The biggest design decision here was reusing the existing bookmark list view
rather than building a second screen. It gained a `source` (either a tag
filter or a Smart View) with everything else about it (rows, pagination,
context menu, detail navigation, empty state) staying identical; in Smart
View mode the title becomes the view's name and the search field, archived
toggle, and add button all hide, since none of those make sense against a
saved query's live results. The sidebars on all three native surfaces gained
an optional Smart Views section between Views and Tags, shown only when the
user actually has at least one, matching the web's same "only appears when
non-empty, no count shown" convention.

---

## Smart View create / edit / delete in the native apps

The previous pass left Smart Views consumption-only on the apps; this one
adds full authoring (create, edit, delete) to iOS and macOS. The CLI stays
consumption-only, since a condition-builder CLI felt like lower value when
import/export already covers authoring there. Once again, no backend or
StashKit change was needed.

Management lives in Settings rather than inline in the sidebar, reached
through a shared management screen with New/Edit/Delete. The sidebars
themselves weren't touched at all: because the shared repository's cache
updates in place on every write, the always-mounted sidebar section reflects
edits and deletes live with zero sidebar code changes. Writes update that
cache directly rather than triggering a refetch: create, update, and delete
all map the domain model to its wire shape, run the request, then
insert/replace/remove the cached entry and re-sort by name, mirroring the
same optimistic-update pattern the bookmark repository already uses.

One shared form sheet handles both create and edit, pre-filling from the
existing Smart View when editing. Condition rows model every editor kind: a
text field, a tag field reusing the same autocomplete chips the bookmark
forms use, a date picker, or a Yes/No picker, switching what's rendered
based on the condition's type while preserving whatever was typed in each
field even as the type selector changes. One contract subtlety that would
have quietly produced a generic validation error if I'd missed it: the web
form's controller normalizes a bare date into full ISO-8601 server-side, but
the JSON API does no such normalization, so the native form has to format
the picked date as full ISO-8601 itself before sending it. Client-side
validation also pre-empts the server's generic error message entirely: the
form validates locally and disables Save until everything's actually valid,
so a user essentially never sees the collapsed, unhelpful server-side
validation string.

---

## Smart View relative date conditions (olderThan / newerThan)

Two new Smart View condition types, `olderThan` and `newerThan`, filter by
age relative to right now rather than a fixed date, joining the existing
absolute before/after conditions without replacing them. The value is a
compact duration string (a positive integer plus a unit suffix for days,
months, or years) parsed and validated the same strict way a malformed
ISO-8601 date already was, rejecting anything ambiguous like a missing unit
or a negative number. The cutoff is computed fresh every time the query
actually runs, using real calendar arithmetic rather than fixed-second
multiples, so "older than 1 month" means an actual calendar month and stays
correct as time passes rather than being frozen at the moment the Smart
View was created. Since the conditions column already stores arbitrary
typed values, adding this was purely code-only: no schema migration, the
same precedent set when the `hasTags` condition was added earlier. The web
and native forms both got their own compound value editor (a number plus a
unit picker) that assembles into the same wire string underneath.

## Smart View form: condition row buttons follow-up (native apps)

A small icon-only follow-up: the condition row's add/remove buttons in the
Smart View form switched from generic bordered buttons to proper SF Symbol
icon buttons: a neutral minus-circle for remove, an accent-colored
plus-circle for add, which reads more consistently with the rest of the
app's iconography. No behavior change.
