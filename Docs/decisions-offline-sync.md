# Stash Decisions: Offline Sync (native apps)

_Part of the Stash Decision Log. See [`DECISIONS.md`](../DECISIONS.md) for the index and the full list of topical files. Entries are in original chronological order within this file._

---

## Offline Sync: Phase 1 (backend sync endpoints + StashKit)

This is the first phase of native-app offline sync: just the two backend
endpoints and the StashKit additions a future sync engine will need, with no
client behavior change yet. The native apps, web frontend, CLI, and browser
extension are all untouched in this pass.

The core problem this solves is deletions: a hard delete just removes the
row from the bookmarks table, so a simple "what's changed since" query can
never report that something was deleted: a client that was offline during
the delete would keep that bookmark forever. A new tombstone table records
every hard delete (who, which bookmark, when), kept indefinitely for now
with no cleanup, and, importantly, recorded on every single hard-delete
code path that exists, not just the API, since a synced user could trigger
a delete from the API, a single web delete, or the web's bulk "delete all"
action. A shared one-line helper keeps that consistent across all three call
sites, deliberately excluded from the admin's "delete user" cascade, since a
deleted account's tombstones are meaningless once the account itself is
gone.

The changes endpoint returns every bookmark (archived included, unlike the
regular list endpoint, since a sync needs both halves in one stream) with
an `updated_at` after the given timestamp, sorted stably so incremental
pagination doesn't skip or repeat rows. Omitting the timestamp entirely
returns everything, which is how an initial full sync bootstraps. The
deletions endpoint returns a flat, unpaginated list of tombstones, since
they're tiny, keyed by the deleted bookmark's own id so a client can match
it straight against its local copy. Both endpoints parse the timestamp as a
plain string and try a couple of ISO-8601 variants, rather than relying on
Vapor's ambiguous date-decoding strategy for query parameters: a malformed
timestamp is a proper validation error rather than silently behaving as "no
filter." StashKit's addition here is exactly what the M6 thin-package rule
would predict: one new DTO and two new factory methods, nothing stateful.
This phase deliberately stops at the backend: no SwiftData, sync engine,
connectivity monitoring, or UI yet; the apps behave exactly as before, and
the backend alone is fully deployable on its own.

## Offline Sync: Phase 2 (SwiftData local store)

Phase 2 gives the native apps a persistent local copy of the user's
bookmarks and switches the bookmark repository to read from it. Still no
delta sync, no offline write queue, and no sync UI: just local persistence.

The local store and its model live entirely under the app-only source
group, not the shared one, specifically so the Share Extension never links
SwiftData at all and stays online-only as intended. The brief for this phase
sketched writes as purely local: mark a record pending, no API call, with
the real push queue arriving in the next phase, but shipping that as a
deployed phase would have meant creates, edits, and deletes silently
wouldn't reach the server at all until Phase 3 landed. I checked with the
product owner and changed the approach: every write still calls the API
first exactly as before, and the authoritative server result gets mirrored
into the local store afterward, so nothing is ever lost and the store stays
consistent with the server throughout this phase. (This write path was
itself later superseded; see Optimistic writes below.)

Reads filter entirely in memory rather than through SwiftData's native
predicate system, since that system can't express the hierarchical
tag-prefix matching, the multi-column case-insensitive search, or the Smart
View rule evaluation this app needs, and the dataset is just one user's
bookmarks, so an in-memory pass is both simpler and exact. The filtering
logic deliberately mirrors the backend's own query logic line for line, so
local results and server results never disagree. Smart Views specifically
are now evaluated locally against the local store, while their definitions
still come from the API.

The first launch after this ships does one full seed fetch of the user's
whole library, gated behind a flag so it only happens once; if that seed
fails (say, the device is offline at first launch), the app still opens
with an empty list rather than hanging, and the next launch just retries.
Signing out wipes the local store and clears that flag, so the next person
to sign in gets a clean re-fetch rather than inheriting anyone else's data.

## Offline Sync: Phase 3 (SyncEngine, connectivity, background refresh)

Phase 3 is where sync actually becomes real: a delta pull-then-push cycle
with last-write-wins conflict resolution, an offline write queue,
connectivity-triggered syncing, and iOS background refresh. The sync state
itself (whether it's syncing, when it last succeeded, any error, how many
changes are pending) is published starting here but not yet shown in any
view: that's the next phase.

The sync engine pulls pages of changes since the last cursor and applies
each one by matching on the server's id: insert if new, apply if the
server's version is newer than the local one, but keep the local version if
there's a pending local edit newer than what the server just sent (so a
push can still deliver it). It then removes anything the deletions endpoint
reports as tombstoned. Push sweeps every locally pending record and issues
the matching create, update, or delete call, clearing that record's pending
flag on success. The whole cycle is single-flight, the same coalescing
pattern used for token refresh elsewhere in the app.

The sync cursor itself absorbed what Phase 2's one-time seed flag used to
do: when there's no cursor yet, a pull just omits the "since" parameter
and fetches the whole library, which is exactly the old seed behavior, so
the separate seed flag and its bootstrap function were removed entirely in
favor of just running a sync. One subtlety worth recording: the cursor
advances to the *start* time of a sync cycle, not the end, and only after
both the pull and the push succeed: using the start means any change that
races the cycle itself gets safely re-pulled next time (applying it twice
is harmless, since applying an update is idempotent), whereas using the end
time could silently skip it.

The offline write queue itself replaces Phase 2's pure write-through
approach, per what that phase's brief had actually called for: online, a
write still goes straight to the API first and mirrors the result locally,
just as before; offline, or when the API call fails with what looks like a
connectivity problem rather than a real rejection, the write applies
locally and gets queued for the next push instead. (This online/offline
branch was itself later dropped in favor of a simpler, uniformly-optimistic
write path; see Optimistic writes below.) Push-side conflicts get handled
explicitly: a duplicate-URL conflict on create means the URL already exists
server-side, saved from another device, so the local content wins and gets
applied as an update onto the existing server record instead; a 404 on
update or delete just means the bookmark is already gone server-side, so
the local record gets removed to match. A genuine connectivity failure
partway through a push aborts that cycle without advancing the cursor, so
the same delta gets retried next time, while any other per-record failure
just skips that one record rather than wedging the whole sweep.

A network path monitor drives both reconnect-triggered syncing and the
initial "assume online, correct on the first real path update" startup
state. Sync itself fires on first launch or login, on reconnect, and on
returning from the background. Background refresh itself is iOS-only in
this phase, built on SwiftUI's own background-task scene modifier rather
than the older, more manual scheduler API: it's simpler in a multiplatform
SwiftUI app and avoids a launch-time crash risk if the task identifier were
ever misconfigured.

## Offline Sync: Phase 4 (sync status UI), feature complete

Phase 4 surfaces the sync state the engine has been publishing since Phase
3: no new sync behavior at all, just the banner, the pending indicator, and
a settings section. This is the phase that completes the whole offline-sync
feature.

The offline banner is a slim, muted strip pinned to the top of the main
content area, shown only while the app is actually offline, rather than a
toolbar item (which would shift other toolbar content around inconsistently)
or a modal (far too heavy-handed for a fully-supported, informational
state). A pending-sync indicator (a small muted icon, not a numbered
badge) appears on any row or detail view for a bookmark with unpushed local
changes; a numbered badge would have implied something needs the user's
attention, when really this is purely informational and never blocks
interaction at all: a pending bookmark can still be opened, edited,
archived, or deleted normally. Sync status itself lives in Settings rather
than as a persistent toolbar element, since it's a background concern, not
a primary action: showing last-synced time, a pending-changes count when
there are any, and a "Sync Now" button. Sync errors show as a small,
dismissible inline notice rather than a modal alert, since a sync failure
is genuinely non-blocking: the user can keep working offline regardless,
so interrupting them with a modal would be the wrong call.

One platform note worth recording: I evaluated adding a macOS-specific
background scheduling mechanism to complement the iOS one, and deliberately
didn't: macOS apps are rarely fully quit, and the existing launch,
return-from-background, and reconnect triggers already cover every
practical sync scenario there. An entitlement for the iOS-only background
framework had briefly and mistakenly been added to the macOS build too; it
has no effect there and was just noise during provisioning, so I removed
it. macOS background sync is complete as-is, with no additional mechanism
planned.

## Offline Sync: Code review fixes

A post-feature code review turned up three real issues, fixed in a
targeted pass with no broader refactoring.

The most serious one: an involuntary auth failure (the session getting
cleared because a refresh definitively failed, not because the user chose
to sign out) was wiping the *entire* local store, including any bookmarks
with unpushed offline changes queued against them. That's a real data-loss
bug: someone who edited bookmarks offline and then had their session
expire before reconnecting would lose those edits entirely. The fix scopes
that wipe to only the clean records, explicitly preserving anything with a
pending change queued (including offline soft-deletes), so a subsequent
sign-in's full re-pull merges back in around the preserved pending work
rather than stomping it, and those preserved records push normally on the
first sync cycle after re-login.

I also audited a suggested fix to preserve the sync cursor across a
sign-out/sign-in cycle, on the theory that a full re-pull might stomp
pending writes, and concluded the premise didn't actually hold, since the
last-write-wins merge logic already protects pending edits regardless of
whether the pull is a full one or a delta. Preserving the cursor would have
introduced a worse bug instead: if a different user signs in on the same
device, they'd inherit the previous user's cursor and get a delta pull
instead of their own full library. So the cursor still clears on reset, and
a full pull on every fresh sign-in stays correct and safe.

Two smaller robustness fixes rounded out the pass: pull results now save to
disk immediately after the pull completes and before the push begins, so
server-side changes are durable even if the push fails or the app gets
killed mid-cycle; and a corrupt or schema-incompatible on-disk store no
longer crashes the app on launch: it deletes the broken store file once,
recreates a fresh one, and triggers a full re-pull to rebuild it, since the
local store is fundamentally a disposable cache and degrading to a
clean re-seed beats a hard crash.

### Explicit logout vs involuntary expiry

The fix above deliberately preserves pending writes on an involuntary
session clear, but that raised a new question: what should happen to those
pending writes when the user explicitly signs out and a *different* person
signs into the same device? Preserving them there would mean the next
user's offline queue pushes the previous user's edits into their own
account: clearly wrong. So session-clearing now splits into two distinct
paths: an involuntary expiry (token revoked, account suspended) preserves
pending records exactly as the fix above describes, while an explicit
"Sign Out" tap wipes everything, pending changes included, since the next
person on that device must never inherit someone else's unsynced data. No
new user-facing method was needed, both Settings screens already called
one shared logout function, so the split lives entirely behind that
existing call.

| Scenario | Wipe behavior | Result |
|----------|------|--------|
| Token expired/revoked | Preserving | Pending writes survive, push on next login |
| Account suspended | Preserving | Pending writes survive, push when unsuspended |
| User taps "Sign Out" | Full wipe | Clean slate, no pending records left behind |

### Follow-up: serverID uniqueness + backend sync tests

Two loose ends from that review round. First, the local store's server-id
field (the key used to match a local record against its server
counterpart) became a database-enforced unique constraint rather than
relying purely on "fetch before insert" application logic, making the model
self-enforcing. Adding a uniqueness constraint to an existing field isn't a
migration SwiftData can apply automatically, but the store already has a
wipe-and-recreate recovery path for exactly this kind of incompatible-schema
situation, so no separate migration plan was needed: an existing local
store on upgrade just gets rebuilt from a fresh full sync once.

Second, the backend test suite gained coverage for the gaps the review
actually found: that tombstones get recorded on the web's single-delete and
bulk-delete paths, not just the JSON API; that the changes endpoint's
results are properly ordered for cursor pagination to work at all; that its
page size is correctly clamped; and that a malformed cursor is rejected
with a proper validation error rather than silently ignored.

## Offline Sync: Optimistic writes (supersedes write-through)

The write-through approach from Phases 2 and 3 awaited the API on the UI
path whenever the network path looked reachable, but a network path
monitor reports whether Wi-Fi is up, not whether the actual server behind
it is reachable. With the server down but Wi-Fi up, a create or delete
would block on a full request timeout (tens of seconds) before falling
back to the offline queue. In practice that meant the add-bookmark sheet
just sat there instead of dismissing, and a row appeared or disappeared
only after that long timeout instead of instantly. Connectivity-based
routing genuinely couldn't fix this, since the only way to be instant
regardless of server state is to simply not wait on the network at all on
the UI path.

So writes became optimistic-first across the board: every create, update,
archive, or delete now applies to the local store and returns immediately:
the UI updates instantly whether online or offline, and a background sync
picks up the queued change and reconciles it with the server's
authoritative result afterward (the real server-assigned id, normalized
tags, fetched metadata). The per-write API call and the online/offline
branch both came out of the repository entirely; pushing changes is now
purely the sync engine's job. One thing that had to be preserved carefully
in this move: an online create still needs server-fetched metadata, so the
local record now remembers whether metadata fetching was requested, and the
background push honors that flag when it finally reaches the server: the
row shows local values first and then updates to the server's normalized
version once the push completes, a brief accepted flicker rather than a
correctness problem.

## Offline Sync: Live list refresh after an external sync

Each visible list owns its own repository instance, refreshed only by its
own triggers and its own writes. That meant a sync triggered *somewhere
else* (a manual "Sync Now" in Settings, a reconnect, or a background
refresh) correctly updated the shared local store but left an already
visible list's rows stale: add a bookmark while the server's down, bring
the server back, tap "Sync Now," and the row kept showing its pending badge
even though the push had actually succeeded. The fix has a visible list
observe the sync engine's own busy state and refresh itself the moment any
sync cycle finishes, regardless of what triggered it: while carefully
preserving the current scroll position and page window rather than
resetting back to the first page the way a full reload would.

## Offline Sync: "Last synced" ticks live

A small but noticeable bug: the "Last synced" time in Settings was computed
against the current moment only when the view happened to re-render for
some unrelated reason, so with nothing else changing on screen it would
visibly freeze, stuck at "5 seconds ago" long after five seconds had
passed. Wrapping that one label in a periodically-ticking timeline view
fixed it, so it now advances once a second the way a relative timestamp
should.

## Offline Sync: Cross-user data integrity fixes

Two more serious bugs turned up in a full-feature review, both genuinely
cross-user issues.

The critical one: nothing in the local store actually recorded *which
user* a pending write belonged to. Combined with the earlier fix that
preserves pending writes across an involuntary session clear, that opened a
real path for one user's queued offline change to get pushed into a
completely different account: if user A's pending write survived a
session clear and user B then signed into the same device, a sync cycle
could push user A's change using user B's credentials. The fix tags every
local record with its owning user's id at creation time, read synchronously
from the access token itself with no network round-trip needed, and scopes
the actual push sweep to only the current user's records, so even when a
previous user's pending writes are sitting preserved in the store, they can
never be picked up and pushed under a different user's session. That scoped
push is the real, airtight fix; adding the user id to existing local
records required the same wipe-and-rebuild schema migration path used
elsewhere.

The second, related bug: canceling a sync cycle on sign-out had a race
where an already-in-flight cycle could still finish and save its results
*after* the wipe had already run, effectively resurrecting rows the sign-out
had just deleted and letting the next user browse the previous user's
bookmarks. The fix makes a reset actively cancel any in-flight cycle rather
than just ignoring it, with the sync engine's pull and push loops checking
for cancellation at safe points so a canceled cycle aborts cleanly before
it ever saves anything or advances the cursor. A related, narrower race,
a canceled cycle's cleanup accidentally clearing a *newer* cycle's
in-flight marker and letting two cycles run concurrently, got closed with
a simple generation counter, so a stale cycle's completion handler can tell
it's no longer the current one and does nothing.

One residual gap I explicitly left out of scope here: while pushes are now
correctly scoped to the current user, *reads* from the local store still
aren't user-filtered, so a previous user's preserved or pulled records
could theoretically still be visible in a freshly-signed-in user's list
until the store gets cleared. The push-side leak (actually writing to the
wrong account) is fully closed; fully closing the read-side visibility gap
would touch more of the read path than this pass covered, so it's logged
as a follow-up rather than bundled in here.

## Offline Sync: Sync correctness fixes (#4 + #8)

Two more correctness bugs from that same review.

First: a bookmark created offline and then archived while still offline
lost its archived state the moment it finally pushed to the server, since
the create request the sync engine sent had no way to carry an archived
flag at all: the backend always created new bookmarks unarchived, and
applying the server's response back onto the local record then stomped the
local archive flag with that default. The fix threads an optional archived
flag through the create request end to end, defaulting to `false` so every
existing client that doesn't send it is unaffected, and the duplicate-URL
merge path picks up the same flag so it's preserved on that route too.

Second, and more subtle: the changes endpoint used offset-based pagination
over a sort key that can change while pagination is in progress. A
concurrent edit shifting rows mid-pagination could cause a row to be
silently skipped entirely: invisible to a client, and never re-fetched,
since the sync cursor had already moved past it. I replaced offset
pagination with proper keyset pagination: each page's request carries the
exact position it left off at (both the timestamp and a tiebreaking id), so
a row that gets bumped during pagination simply reappears on a later page
instead of vanishing, and applying it twice is harmless since applying an
update is idempotent. One deliberate deviation from a more "obvious"
design: that keyset cursor is transmitted as an opaque string the client
echoes back verbatim rather than as a typed date, specifically because the
API only serializes timestamps at whole-second precision, round-tripping
through a truncated date could make a keyset comparison never advance at
all if enough rows shared the same second (a bulk tag rename touching
hundreds of bookmarks at once, for instance), which would have caused an
infinite pull loop.

## Offline Sync: Sync correctness fix (#3)

The last correctness bug from that review: a pending write that hit a
*permanent* server rejection (a validation error, a forbidden response)
kept retrying forever on every single sync cycle, with the pending count
staying stuck and no error ever surfacing, and no way for the user to clear
it short of signing out entirely and losing all their other pending work
too.

The fix adds a proper distinction between recoverable and permanent push
failures. Connectivity problems, auth failures, and even a transient
server error all stay recoverable and keep retrying, since a momentary
server hiccup shouldn't cost someone their offline change, but a
deterministic rejection like a validation failure now marks the record as
permanently failed and stops retrying it, surfacing a small "Failed to
sync: N bookmarks" row in the sync status section with a Clear action that
lets the user explicitly accept losing that particular unrecoverable
change. The pending-sync icon itself also gained a visually distinct failed
state: an orange warning variant instead of the usual muted pending
icon, so a failed write actually looks different from one that's simply
still in flight.

## Offline Sync: Cleanup sweep

A handful of no-behavior-change cleanups fell out of the review too: a
couple of genuinely dead local-store methods with no remaining callers got
deleted; a write-triggered sync was needlessly running a full pull-then-push
cycle when the device had literally just produced the change itself and had
nothing to pull, so it now runs a push-only cycle instead, saving a
redundant round-trip on every single write; some duplicated favicon-domain
derivation logic that had drifted into two places got consolidated into
one; and a stale doc comment describing behavior the optimistic-write
refactor had already removed got corrected.

## Offline Sync: Sync correctness fix (#5)

Every hard delete recorded the actual row deletion and its tombstone as two
separate, unrelated database calls with no transaction wrapping them. A
crash or dropped connection in the narrow gap between the two would leave a
bookmark gone from the server with no tombstone recorded at all: a synced
client would never find out it was deleted through either sync endpoint,
orphaning the local copy forever with no way to reconcile. The fix wraps
the delete and its tombstone write in a single database transaction across
all three hard-delete code paths (the API, the web single delete, and the
web bulk delete), so either both happen or neither does. The one thing I
couldn't cleanly add was a rollback-on-failure test, since there's no clean
way to inject a mid-transaction failure in the current test harness without
a fragile, test-only hook: the atomicity here rests on the database
transaction wrapper itself rather than an explicit test proving the rollback
path.

## Offline Sync: Refresh button triggers a sync

Before offline sync existed, the bookmark list's Refresh button re-fetched
from the server. After the repository moved to reading entirely from the
local store, that same button silently became a no-op: it just re-read
whatever was already sitting on screen, reaching nothing remote at all. I
repointed both the Refresh button and its keyboard shortcut at an actual
sync cycle, the same one the Settings "Sync Now" button already used, while
deliberately leaving the plain local reload alone for the cases that
genuinely should stay local-only: a search submit, clearing a filter,
switching sources. iOS's pull-to-refresh gesture had the exact same dead
behavior and got removed entirely rather than rewired, since the toolbar
button and shortcut are now the one clear "get fresh data" affordance.

## Offline Sync: macOS foreground sync trigger

Saving a bookmark from the browser extension or the macOS Share Extension
(both of which write straight to the backend and never touch the app's local
store) and then switching back to an already-open Stash window on macOS
didn't show the new bookmark until an explicit refresh or a relaunch. The
live-list-refresh wiring from earlier was already in place and working; the
actual problem was that no sync cycle was firing at all when this happened,
because none of the existing triggers covered it.

The root cause turned out to be a real gap in a Phase 4 assumption: SwiftUI
scene-phase tracking only reaches its background state when every window of
an app is actually hidden or minimized, not when the app simply loses key
focus because the user clicked over to a browser. So switching back to a
still-visible Stash window never produces the transition the return-from-
background trigger was watching for: that trigger genuinely does cover
this case on iOS, but not on macOS, correcting what I'd assumed back in
Phase 4. The fix adds a macOS-only observer on the app becoming active
again (not merely visible), running through the same shared sync helper as
every other trigger, single-flight as always so it safely coalesces with
anything already in progress.
