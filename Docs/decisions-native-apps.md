# Stash Decisions: Native iOS/macOS Apps & Share Extension

_Part of the Stash Decision Log. See [`DECISIONS.md`](../DECISIONS.md) for the index and the full list of topical files. Entries are in original chronological order within this file._

---

## M8: iOS app (core)

Scope for this milestone was a working app: authentication, the bookmark
list, adding a bookmark. I deliberately deferred the Share Extension (M9),
full settings, tag rename/delete, and edit/delete screens.

I generated the project with XcodeGen rather than checking in a `.xcodeproj`:
`StashApp/project.yml` was the source of truth, and `xcodegen generate`
recreated the (gitignored) project, the same way the package targets avoid
committing build artifacts. (This later got reversed; see the M10-era
decision to commit the Xcode project and retire XcodeGen.) It was a single
multiplatform SwiftUI target, iOS 17 minimum, bundle id `cc.otavio.stash`,
App Group `group.cc.otavio.stash`, both iPhone and iPad. macOS wasn't added
until M10, so this milestone's target was iOS-only.

I vendored `KeychainStore` from an earlier project of mine (Triton) and
extended it with an optional `accessGroup` parameter, so the same store could
later share an item with the Share Extension over the App Group in M9; for
this milestone both token stores are created without an access group, so M8
works standalone with no extra entitlement. One real deviation from the spec
here: both the access and refresh tokens live in the Keychain, not just the
refresh token as the memory-only-access-token plan called for. That's what
lets the Share Extension reuse the access token directly in M9, and it means
a cold app launch restores the session without an immediate refresh
round-trip, worth the deviation.

`TokenManager` decodes the JWT `exp` claim by hand, the same dependency-free
approach as the CLI. A token that's absent or unparseable is treated as
expiring, so the caller refreshes rather than sending a request that would
just get rejected.

The repository pattern maps StashKit's DTOs to local domain models:
`AuthRepository`, `BookmarkRepository`, `TagRepository` are `@MainActor
@Observable` classes that views observe directly. Since StashKit stops at
DTOs, the repositories own the DTO→domain mapping and all session-stateful
concerns, including the in-memory tag cache I'd deliberately kept out of
StashKit back in M6: `TagRepository` caches the tag list for synchronous
local autocomplete and invalidates it after any write that might change tags.
Silent refresh is centralized in `AuthRepository` behind a narrow
`SessionRefreshing` protocol, so the bookmark and tag repositories can ensure
a fresh token without owning auth state or creating a reference cycle. The
app also needs a direct `MicroClient` dependency, same reason as the CLI:
the 2FA login branch can't be expressed through StashKit's typed request.

A single `@MainActor @Observable` `AppEnvironment` builds everything once at
launch: token stores, `TokenManager`, `StashClientProvider`, the three
repositories, and `RootView` routes between setup, login, and the main app
based on configuration and auth state. Layout branches on size class:
`NavigationSplitView` with a tag sidebar on iPad, a tab bar on iPhone, both
driven by the same `BookmarkListView`.

Verification: American English, doc comments only on types, no inline
comments, formatting and linting both clean, the app builds without warnings
for the iOS 17 simulator, and I walked Setup → Login live against the
running Docker backend. No app unit tests (§18.7): the networking path was
already covered by StashKit's mocked tests and proven end-to-end by the CLI
against the same backend.

### M8 follow-ups (first device testing)

A few things only showed up once I actually ran the app on a device rather
than the simulator. `AppSettings.serverURL` was originally
`@ObservationIgnored @AppStorage`, per the spec, but that's excluded from
`@Observable` tracking, so setting it from `SetupView` persisted the value
correctly but never notified `RootView`, and the app looked stuck on Setup
("Continue does nothing"); it only routed correctly if the value was already
present at launch. I replaced it with a plain tracked property whose
`didSet` writes through to the same UserDefaults key, so the same persistence
now actually triggers reactive routing.

`AppEnvironment` originally held one shared `BookmarkRepository`, which meant
the Bookmarks tab, a Tags-tab drill-in, and the iPad detail column all
mutated the same array: browsing a tag in the Tags tab left the Bookmarks
tab showing that tag's results too. I switched to a
`makeBookmarkRepository()` factory (sharing the client and session, but not
the array), with each list view owning its own repository instance, so lists
are properly independent. `AuthRepository` and `TagRepository` stay shared
singletons, since auth state and the tag cache are intentionally global.

Bookmark navigation also needed fixing: `BookmarkListView` declared its own
`navigationDestination(for: Bookmark.self)`, but the view gets reused at
multiple stack depths (root of the Bookmarks tab, pushed under Tags, the iPad
detail column), and SwiftUI only honors the outermost declaration: tapping a
bookmark from the Tags flow re-pushed the list instead of showing the detail.
I switched bookmark rows to closure-based `NavigationLink { Detail }` and
dropped the `navigationDestination` entirely, since closure links resolve at
any depth with no registration.

Two smaller fixes from the same round: the search field now disables
autocapitalization and autocorrection (`.searchable` defaulted to
sentence-case, so typing `casio` became `Casio` and matched nothing), and
full-text search itself became genuinely case-insensitive on the backend:
Postgres `LIKE` is case-sensitive and §9.3 wants "ILIKE on PostgreSQL", so I
replaced it with a shared `QueryBuilder<Bookmark>.filterFullText(_:)` helper
that compares `lower(column) LIKE lower(term)`, portable across SQLite and
Postgres, used by both the JSON API and the web list handler so they can't
drift apart. This is the fix the M2 entry above points forward to.

### M8 follow-ups (SwiftUI review)

I ran the app against a SwiftUI-focused review pass (state management,
performance, view composition, navigation, list patterns) and made a few
changes as a result. Each bookmark row's tags had been a nested horizontal
`ScrollView`, which meant a scroll container and gesture recognizer on every
cell in a hot list; I replaced it with a non-scrolling row showing the first
three tags plus a `+N` overflow count (the detail screen keeps its scrolling
tag row, since it's not in a list and should show everything). `AppSettings`
became `@MainActor`, matching the other observable types. The empty state
got context-aware: previously "Tap + to save your first bookmark" showed even
when a search or tag filter simply matched nothing, implying an empty
library that wasn't actually empty; it now distinguishes an active search,
an active tag filter, the archived view, and true first-run. And the
add-bookmark URL field's paste button switched from raw `UIPasteboard.general`
(which trips the system's paste-permission banner on every tap) to
`PasteButton`, which the system enables only when there's text on the
pasteboard and pastes without prompting (and drops the `import UIKit` the old
approach needed). The login flow's 2FA push also got a proper `LoginRoute`
enum instead of driving the navigation stack with a raw `[String]` and the
temp token as the route value.

A few things I considered changing here but left alone: the add sheet's tag
suggestions stay a computed property rather than a `@State` cache, since a
cache keyed on the text would miss the async tag-load completing mid-typing,
and the data's small enough that it doesn't matter. Favicon images stay plain
`AsyncImage`: `URLCache` already covers the downloads, and an in-memory
decode cache would be a bigger, optional change for a marginal win. And the
size-class swap between split view and tab bar stays as two distinct layouts
rather than one adaptive view, since the iPhone tab information architecture
genuinely differs from the iPad sidebar.

---

## M9: iOS Share Extension

Scope: save a URL to Stash from Safari (or any app) via the system share
sheet, with the same add-bookmark UX as the app and a confirm-with-undo step.
No login flow inside the extension itself: the user has to authenticate in
the main app first.

I added a `StashShareExtension` app-extension target to the XcodeGen
`project.yml` (still the source of truth at this point), activation limited
to a single web URL, and the same `MicroClient` + local `StashKit`
dependencies as the app. The app target gained a dependency on it so the
`.appex` embeds under `PlugIns/`.

Whatever the extension genuinely needed (`KeychainStore`, `TokenManager`,
`StashClientProvider`, the domain models, error mapping,
`TagSuggestionView`, and a new `AddBookmarkView`) moved out into a
top-level `StashApp/Shared/` folder compiled into both targets, so nothing's
duplicated across the two binaries; app-only code (repositories,
`AppEnvironment`, the root views) stayed under `Stash/`.

Sharing state across processes needed two different mechanisms. Tokens go
through a Keychain access group: a single `AppGroup` enum owns the group
identifier and both token keys, and the app now builds its Keychain stores
with that access group (the placeholder I'd left for this back in M8 became
real here), so the extension reads exactly what the app wrote. The server URL
needed a different fix, since `UserDefaults.standard` isn't visible across
processes: both the app and the extension now read/write it through the App
Group's shared `UserDefaults` suite instead. One consequence: because tokens
now live in the access group and didn't before, an existing M8 install has to
sign in once more after this change, a planned, one-time transition.

The extension is process-isolated, so it can't share the app's live
`@Observable` repositories: it builds its own lightweight versions instead
(`ExtensionBookmarkRepository` for create/fetch-metadata/delete only, no list
or pagination; `ExtensionTagRepository`, load-once with local autocomplete
and no cache invalidation, since the extension is too short-lived to need
it). Both go through an `ExtensionSession` that mirrors
`AuthRepository.refreshIfNeeded()`: rotating the access token before each
request if it's expiring soon, and writing the pair back to the shared
Keychain.

`AddBookmarkView` (the actual form) got extracted from the M8
`AddBookmarkSheet` into a shared view depending only on two narrow protocols
(`BookmarkCreating`, `TagAutocompleting`), so both the app's repositories and
the extension's conform without the view caring which is which. It reports
results through callbacks instead of dismissing itself, so each host decides
what happens next; the extension passes the URL in as read-only (it came
from the share sheet) and fetches metadata automatically on load.

The extension's own UI is a small three-state machine: a brief loading state
while it reads tokens and resolves the shared URL, a signed-out state
("Open Stash to sign in before saving bookmarks.") when there's no
configured server, no refresh token, or no URL could be extracted, and the
add state itself. The shared URL is pulled from the extension's input items,
preferring a proper URL attachment and falling back to the first link found
in plain text.

Saving advances to a confirmation state ("Saved to Stash ✓") with an Undo
button; a three-second timer auto-dismisses the extension unless Undo is
tapped, in which case the timer cancels, the view returns to the add form,
and the just-saved bookmark gets deleted so the user can re-save with
different tags or just cancel outright.

Same verification bar as everywhere else: formatting and linting clean, no
warnings on a full build, no unit tests per the testing policy (§19.6).

---

## M10: macOS app (and a deployment-target bump to 26)

Scope: a native macOS app sharing the iOS source tree, a macOS Share
Extension, and a bump of both platform minimums to iOS 26 / macOS 26 (which
adopts Liquid Glass automatically just by building against the newer SDKs).

Rather than a second entry point, the app stays a single `@main App` that
branches its scene body with `#if os(macOS)`: macOS adds a `Settings` scene
and window sizing. `RootView` routes the authenticated state to `MainView` on
iOS and a new `MacContentView` on macOS.

The brief sketched a three-column layout with an optional inspector panel for
macOS; I went with a two-column split instead that reuses the exact same
`BookmarkListView` already shared with iPad, since that maximizes code
sharing for very little practical loss: the inspector would have needed a
selection-driven variant of the shared list and more platform divergence for
not much gain, so I didn't build it. Platform differences elsewhere are
concentrated in a small set of cross-platform style helpers and a few
whole-view `#if` shells (`MainView`/`TabContainerView` on iOS,
`MacContentView`/`MacSettingsView` on macOS); the shared leaf views stay
plain SwiftUI. Since SwiftUI has no cross-platform clipboard API, there's one
free function that's the sole place `UIPasteboard`/`NSPasteboard` get
touched.

Edit, delete, and archive all became shared behavior surfaced per platform: a
right-click/long-press context menu on each row (Open in Browser, Copy URL,
Copy Markdown URL, Share…, Archive/Unarchive, Delete), the same actions in
the detail view, and keyboard shortcuts (⌘N new, ⌘E edit, ⌘R refresh, ⌘⌫
delete with confirmation).

One SwiftUI wrinkle worth recording: I wanted Esc to pop the bookmark detail
back to the list. There's no view-level "run this closure on Esc" API in
SwiftUI: `.keyboardShortcut` is deliberately bound to a control, so the
idiom is a hidden, zero-opacity button carrying the shortcut, the same trick
already used for ⌘F. I bound it to `.cancelAction` rather than a raw escape
key specifically so layering falls out for free: when an edit sheet or a
delete confirmation is on top, that presentation captures Esc first, and the
detail only pops when nothing is layered above it. It's live everywhere, not
`#if os(macOS)`-guarded, since it's simply inert on iOS/iPadOS unless a
hardware keyboard is attached (there's no on-screen Esc). I considered
`.onKeyPress(.escape)` and a `Commands`/`CommandMenu`, but the former is
focus-scoped and unreliable inside a `Form`, and the latter is macOS-only and
lives at the wrong altitude for a per-view action.

The macOS `Settings` scene (⌘,) got three tabs (General, Account, and
Appearance) which drove a few StashKit and repository additions (a change-
password request, TOTP setup/verify/disable methods) and a cross-platform
`QRCodeView` built on CoreImage, since both platforms have it. Appearance
itself lives in plain `UserDefaults` rather than a cookie, since the native
clients have no browser to store one in; `serverURL` stays in the App
Group's shared suite since the extension needs to read it too.

The macOS Share Extension reuses essentially all of the iOS one's SwiftUI:
the shared view, session, and repositories are all plain SwiftUI/Foundation
with nothing UIKit-specific, so only the principal controller differs
(`NSViewController` vs `UIViewController`), both `#if`-guarded in the same
source folder. Same three-state UI, same confirm-with-undo.

---

## Token refresh: concurrent-refresh race (macOS spurious logout)

This one was a genuinely tricky bug, and worth writing up in full because
the fix ended up touching three separate layers.

Refresh tokens are single-use: the backend rotates on every refresh call
and deletes the one just presented. The app fires a refresh check before
every authenticated request, but originally had no serialization around it:
if two requests started at the same moment with an already-expired access
token, both read the same refresh token from the Keychain and both POSTed
it. The server honored whichever arrived first and deleted it; the second
request then presented a token that no longer existed, got a `401
token_invalid` back, and the app responded by clearing the session
entirely: dropping the user straight to the login screen, even though
their session was, moments earlier, perfectly valid.

It took a while to figure out why this only ever hit macOS and iPad, never
iPhone. The auth code itself is shared across platforms, so the bug had to
be in the navigation shell instead: the macOS and iPad layouts render both
the sidebar and the detail column at launch, so the sidebar's tag load and
the detail column's bookmark load fire two authenticated requests
*simultaneously*: that's the race. iPhone's tab-based layout lazy-loads
each tab, so only one authenticated request ever fires at cold start. The
bug was also intermittent even on the affected platforms, since it only
triggers when the cached access token is already expired at launch: the
app has to have been idle for a while first, which made it feel like a
flaky backend-restart issue at first before I traced it properly.

The actual fix has three parts. First, silent refresh became single-flight:
`AuthRepository` (and the Share Extension's equivalent) now hold an
in-flight refresh task, and the first caller stores it while every
concurrent caller just awaits that same task instead of starting its own:
safe without locks because both types are main-actor isolated. Second, only
a genuinely definitive auth failure clears the session now; the old code
cleared on *any* refresh error, so a transient network blip or a 5xx during
refresh logged someone out even though their refresh token was still valid
server-side; now it only clears on the specific auth-failure error codes,
and rethrows everything else with the session left intact so the caller can
retry. And third, since the app and the Share Extension are separate
processes sharing one single-use refresh token through the Keychain access
group, there's a cross-process version of the same race: if both refresh at
nearly the same instant, the loser presents a token the winner already
rotated away, and without a guard the old code would clear the session even
though a perfectly valid successor token was sitting right there in the
Keychain. The fix compares the refresh token this call attempted with
against whatever's currently in the token manager: if it's unchanged, the
refresh genuinely failed; if it changed underneath the call, another process
rotated it legitimately, so the failure is rethrown for this one request
instead of clearing the session, and the next refresh check picks up the
already-rotated token. Relatedly, whether the app considers itself
authenticated at launch is now seeded from the presence of the *refresh*
token, not the access token: the refresh token is what actually sustains a
session, so an expired-but-present access token should still restore
successfully via a refresh on launch.

One more layer sits on top of all this: even with proactive refresh working
correctly, a token the client believes is still valid can be rejected by the
server anyway: clock skew, a backend secret rotation, or the cross-process
race above, and without a fallback that would surface as a hard "session
expired" error even when the session was actually recoverable. I looked at
using `MicroClient`'s own retry strategy for this and rejected it: it
retries on *any* thrown error, so it would replay a 422 or 409 pointlessly,
has no backoff, and critically re-reads the same rejected token between
attempts with no way to actually refresh first, so it would just resend the
same bad token repeatedly. Instead there's an explicit `AuthorizedClient`
wrapper with the exact same `run(_:)` signature as the underlying client:
on a retryable auth failure it forces one refresh and replays the request
exactly once. That replay is safe because the auth middleware rejects an
unauthenticated request before the route ever runs, so a 401 has no side
effects; even a POST or DELETE is safe to repeat. This wrapper lives in
three places rather than one shared spot: the app, the Share Extension, and
the CLI each have their own copy, because StashKit is deliberately kept
free of refresh logic, the same reason the refresh code itself was already
duplicated between the app and the CLI.

---

## macOS Share Extension: three platform-specific fixes

The Share Extension worked fine on iOS but always landed on the "Sign In to
Stash" screen on macOS, even with a fully signed-in app. It turned out to be
three separate, macOS-only defects stacked behind that one symptom, each one
masking the next; I found and fixed them in sequence. iOS was never
affected by any of the three.

The first was Keychain sharing. `KeychainStore` shares the token pair with
the extension through an App-Group access group, which works on iOS because
the data-protection keychain is the only keychain that exists there, but
macOS defaults to the legacy file-based keychain, which doesn't honor
App-Group access-group sharing at all. The extension's read was silently
returning nothing, so it looked exactly like "no refresh token" rather than
"wrong keychain." Adding one flag to opt both processes into the modern,
data-protection keychain on macOS fixed it: a no-op on iOS, where that's
already the default. One real cost: tokens previously written to the legacy
keychain became invisible after this change, so existing macOS users had to
sign in once more. Acceptable for a self-hosted app.

With auth working, the same screen still persisted, because the bootstrap
logic conflated "not signed in" with "no shareable URL found": both fell
back to the same signed-out screen. The actual cause was macOS Safari
delivering the shared URL as `Data` or a plain `String`, not as an `NSURL`
the way iOS does, so the existing cast just silently failed on macOS. I
widened the coercion logic to accept all three shapes, and iOS kept working
exactly as before.

With the URL now loading, the form appeared, but had no Save or Cancel
buttons at all. The shared form puts its actions in a navigation-stack
toolbar, which the chrome-less hosting controller macOS uses for its share
popover just doesn't render anywhere. The fix was a macOS-only bottom action
bar, gated behind a flag that only the extension sets: the app's own
sheet already renders the toolbar correctly on macOS, so an unconditional
bar would have doubled the buttons there.

I verified the whole thing end to end through Safari's actual share sheet on
macOS: sign-in from the shared session, URL extraction, and a save via the
new inline button, with the iOS share flow completely unchanged throughout.

---

## Bookmark detail: consistent macOS Form action buttons

The macOS bookmark detail page's three action rows had visibly mismatched
styles: "Open in Browser" rendered as a plain system-blue link, while
Archive and Delete picked up macOS's default bordered push-button chrome, a
gray rounded rectangle sitting inside an otherwise plain form row. iOS never
showed this, since a grouped form there renders links and buttons
identically.

My first instinct was to restyle the two buttons to match the link, but that
failed: macOS renders a `Link` in its native system link color, which
isn't the app's accent color and can't be overridden. So I went the other
direction instead: "Open in Browser" became a button too, driving the
environment's URL-opening action, making all three rows the same control
type sharing one small macOS-only styling helper that gives them a
consistent full-width, whole-row-tappable, accent-colored appearance. It's a
no-op on iOS, where the grouped form already renders buttons this way:
keeping the shared detail view itself as plain SwiftUI, with the platform
divergence concentrated in one helper, the same pattern established back in
M10.

---

## iOS account settings: password change + 2FA at macOS parity

The account settings screen (change password, enroll or disable two-factor)
shipped with the macOS Settings window but was entirely wrapped behind a
macOS-only guard, so the iOS app's settings screen only ever offered server
URL and sign out. A parity pass across all the clients flagged this as the
single highest-impact native gap: iOS users genuinely couldn't change their
password or manage 2FA from the app at all, only from the web frontend or
macOS.

The fix was un-gating the existing screen rather than writing a new one,
since every dependency it needed was already cross-platform: including the
QR code view, which renders through Core Image rather than any
platform-specific image type, so the enrollment QR just worked on iOS
unchanged once the guard came off. Only genuine window chrome stayed
platform-specific: a fixed sheet size and some outer padding that only make
sense in a floating macOS settings window, pushed behind a couple of small
shared helpers so the divergence stayed at the edges rather than spreading
through the view itself. On iPhone, the entry point is a plain navigation
link from the existing settings screen; the iPad sidebar previously had no
settings surface at all, not even sign out, so it gained a toolbar button
presenting settings in a sheet, closing that gap too.

---

## Native apps: hierarchical tag sidebar (iOS + macOS)

The web sidebar had a proper nested, indented tag tree; the native apps
still showed a flat tag list with barely more than an All/Untagged
distinction. This work brought the apps up to web parity.

The tree is built client-side, ported directly from the web's own tree
algorithm, since the tags endpoint only ever returns a flat list with counts:
every `/`-delimited ancestor becomes a node, synthetic parents that exist
purely to nest their children carry no count of their own, and children sort
alphabetically at each level. Unlike the web's flattened representation (which
carries an indentation depth per row), the native version is genuinely
nested, since SwiftUI's disclosure-group view wants real recursive structure
rather than a pre-flattened list.

I initially made the tree collapsible, with native disclosure triangles,
since it felt more idiomatic than a faithful flat-indented port and composed
well with the existing list and navigation types. That turned out to be the
wrong call in practice: collapsed by default meant the full tree was never
actually visible, which undercut a tag picker's search, so I later reversed
it back to the same always-expanded, indented style the web uses.

Getting full parity with the web's Views section (All, Untagged, Today, This
Week) actually required a backend change, since the JSON API had only ever
honored the untagged sentinel: Today and This Week had been left as
web-frontend-only conveniences. I extracted the whole sentinel-plus-prefix
tag filter into one shared query-builder helper that both the API and the
web frontend now call, so there's no duplicated filter expression left to
drift apart the way it had once before (see the tag sidebar section above).
The sentinel constants themselves live once in StashKit rather than being
redeclared as string literals in the app.

One performance fix along the way: the tree was originally being rebuilt
from scratch on every SwiftUI body evaluation, including every single
sidebar tap, since building the tree was called directly inside a view
body. Moving that computation into the repository, computed once and cached
after each load, fixed it.

---

## App icon: the bookmark-ribbon mark (native apps)

The app originally shipped with stock treasure-chest artwork; I replaced it
with the same bookmark-ribbon mark the browser extension already used, so
the app and the extension share one visual identity instead of looking like
two different products. The icon is generated, not hand-drawn, mirroring
the extension's own icon generator: the same ribbon shape, rendered as a
white glyph on a transparent square canvas at high resolution and then
resized down, so the source of truth is a script rather than a hand-edited
PNG that could drift.

The actual app icon uses Xcode 26's newer icon-composer format rather than a
traditional flat icon set, which is what supplies the color, the indigo
background, and the glass effect: the glyph itself stays flat and gets
composed by the system.

This same mark then propagated outward to the rest of the product: the web
UI had no favicon at all before this and now serves the identical app mark,
generated by a third sibling script so every surface's icon assets trace
back to one consistent generation approach; and the browser extension's
icon generator was updated to render size-appropriately: the small
toolbar-button sizes keep a transparent-background ribbon so it blends into
both light and dark browser toolbars, while the larger store/management
sizes switch to the full app-icon look with the indigo background. Liquid
Glass itself is an Apple-only rendering effect and can't be reproduced in a
flat PNG or SVG, so the web and extension marks intentionally match the
app's look minus the glass sheen.

---

## Accent palette: added the Terracotta theme

I added a tenth accent theme, Terracotta, a muted clay-orange that, unlike
most of the other themes, uses the identical hex value for both light and
dark mode, since that particular tone reads well on either background. I
picked the name to match the palette's existing evocative one-word style
(Ocean, Aurora, Dusk, Slate) rather than something literal like "Orange,"
since the actual tone is softer than a pure orange. No other code changes
were needed: the admin picker, the validation, and the swatch CSS all
derive from one central theme list, so adding an entry there was enough to
make it selectable, valid, and correctly previewed everywhere automatically.

---

## Tag picker (native apps)

The add and edit bookmark forms used to edit tags through a plain
comma-separated text field with autocomplete chips: functional, but very
much a keyboard-first design bolted onto a touch app. Both forms now show a
read-only summary of the current tags plus an "Add Tags" button that
presents a proper picker sheet: a touch-first surface where existing tags
are picked directly from the hierarchical tree, no keyboard required unless
you're creating a brand new tag. The old comma-field machinery is gone
entirely from the bookmark forms: it's the sole tag-editing surface there
now. (The Smart View condition editor's single-tag field is a different use
case, still genuinely suited to inline autocomplete, so that one keeps its
own separate chip-based picker.)

The picker's search field doubles as tag creation: it filters the tree
live, and when the typed query doesn't match any existing tag path, a
"Create" row appears at the top: tapping it adds the tag and clears the
field without closing the sheet, so several new tags can be added back to
back in one sitting. Filtering itself is parent-visible: a node survives the
filter if its own label matches or *any* descendant does, so a matching
child keeps its ancestors visible and the hierarchy stays navigable rather
than collapsing into an unrelated flat list of matches. Every tap toggles a
tag immediately rather than staging changes behind a separate Cancel/Done:
consistent with how iOS pickers generally behave, and simpler than tracking
two parallel states. The picker is shared with the Share Extension too,
which derives its own tag tree on the fly since its process is too
short-lived to bother caching one, and degrades gracefully to a "No Tags
Yet" empty state with just the create option when there's no tag data
available at all.

## Tag pills mirror the web's hierarchy rendering (native apps)

The web frontend already presents a hierarchical tag with a middot
separator rather than the raw stored slash (`swift › server` instead of
`swift/server`), which reads far more naturally. The native apps now match
that presentation exactly, through the one shared tag-pill component, so
the change lands on bookmark rows, the detail view, and the add/edit tag
summary all at once. This is presentation-only: the actual stored tag, the
filter query, and every request still use the raw slash form; only the
displayed text changes. The indented tag-tree rows deliberately keep
showing just the leaf segment of each tag rather than the full path, since
the tree already conveys hierarchy through nesting and indentation, so a
separator there would be redundant.

## Flat-indented (web-parity) tag tree (native apps)

All four of the native tag trees (both sidebars, the iPhone tags tab, and
the tag picker) started out as native collapsible, disclosure-triangle
trees, collapsed by default with no way to open everything at once. That
turned out to actively undercut the picker's own search: narrowing the list
still left matching children hidden behind a closed triangle above them,
so a search that should have surfaced a result visually hid it instead. I'd
briefly considered making the trees expand by default, which would have
needed replacing the native disclosure-group view with a hand-rolled
recursive wrapper across all four call sites: more machinery for the
payoff than I wanted. What I actually did instead was simpler than either
option: replace the collapsible tree with a flat, indented list (mirroring
exactly what the web sidebar already does) so the whole tree is visible at
once with indentation conveying the hierarchy, and it's genuinely *less*
code than the disclosure-group approach would have been, not a workaround.
The underlying nested tree model itself didn't change at all; only how it's
rendered did, and the flattened form is cached the same way the nested one
already was, so a sidebar tap doesn't pay to re-walk the whole tree on every
redraw.

## Drag-and-drop tagging (native apps)

Dragging a bookmark row directly onto a sidebar tag to tag it works on iPad
and macOS, the two layouts where the tag sidebar and the bookmark list
genuinely share the same screen: it's deliberately not available on
iPhone, where tags live on a separate tab entirely and there's no on-screen
drop target for the gesture to land on, and it would compete with the row's
existing long-press context menu anyway.

Making a bookmark draggable needed a dedicated, custom transferable type
rather than generic JSON, specifically so a tag row can't be tricked into
accepting arbitrary dropped data from somewhere else. That type has to be
explicitly declared in both apps' configuration: without that declaration
the drag still visually lifts off the row, but the drop target silently
can't resolve the type and rejects every drop with no visible error at
all, which took a bit of tracing to pin down since "intra-app drags need no
extra declaration" turned out to be a wrong assumption. The drop itself
reuses the same optimistic update path every other tag edit already goes
through: no new write API needed for this at all. The three sidebar
sentinels (Untagged, Today, This Week) live in a separate section from the
tag tree entirely, so they're never accidentally valid drop targets: only
real tag nodes are.

## Native share (bookmark row menu + detail actions)

Both the bookmark row's context menu and the detail view's actions section
gained a native Share entry, placed after the copy actions and before the
mutating archive/delete actions so the ordering groups read-only actions
above destructive ones. It uses SwiftUI's built-in share link rather than a
hand-rolled platform-specific helper, which is genuinely cross-platform and
needs no `#if` branch at all, unlike the clipboard helper elsewhere in the
app: sharing just the bookmark's URL, which is what was actually asked for.

## Visual polish: bookmark list, detail, empty states (native apps)

A content-first visual polish pass on the bookmark row, the detail header,
and the empty states: no new features, no navigation or data changes,
just refinement. The look I was chasing is closer to Things or Craft:
structured, generous whitespace, chrome that gets out of the way. Each row
now reads as a clear three-level hierarchy: a primary title, a secondary
domain line, and tertiary tags, using only semantic text styles throughout
rather than hardcoded point sizes, so Dynamic Type and dark mode keep
working automatically. The domain became the row's real visual anchor
(favicon plus domain, not the full URL), which is both more scannable and
more meaningful than a raw URL string; the detail view still shows the full
URL, just demoted to a quiet secondary line below the domain. Tags in the
list row dropped their capsule background in favor of plain quiet text,
while the detail view and add/edit summary keep the more prominent styled
capsule treatment: same underlying component, just a plainer mode for the
row context. The favicon's loading/failure placeholder became a calm
letter-monogram of the domain's first character instead of a generic broken
link icon. And every context-specific empty state (first run, archived,
filtered by tag, a Smart View) now shares one component with copy that
actually names the active filter and suggests what to do next, rather than
a handful of separately-worded messages.

## Add/Edit Bookmark: custom layout (native apps)

Both the add and edit bookmark screens moved off SwiftUI's grouped form
style entirely, replaced with a plain scrolling stack of field groups:
removing the table-cell chrome (inset rounded sections, system separators)
in favor of spacing and thin dividers doing the structural work, the same
Things/Craft direction as the list polish above. Each field now has its
label floating above it rather than off to the side the way a form section
header would, and text fields sit borderless directly on the sheet
background rather than in an inset box. After a successful metadata fetch,
a small favicon-plus-domain row fades in between the URL and title fields
as a lightweight visual confirmation of which site actually got fetched.
One structural wrinkle worth noting: the favicon view used elsewhere in the
app depends on app-only settings that don't exist inside the Share
Extension's process, so the shared favicon styling and its monogram
fallback moved into the common layer, with a small extension-safe variant
that reads the server URL straight from the shared App Group storage
instead. Tag editing on both forms was reworked into the same label-above-
field layout, and the Share Extension's read-only URL, auto-fetch-on-appear,
and inline action bar all kept working unchanged throughout this pass.

## Tag Picker Sheet: visual polish (native apps)

A matching polish pass on the tag picker itself, purely visual: the
underlying tap-to-toggle and search-as-create behavior is unchanged. Each
row now leads with a selection circle (empty when unselected, filled with
the accent color when selected) rather than a trailing checkmark, the same
multi-select pattern Mail and Reminders use. When at least one tag is
selected, a horizontally scrolling strip of removable chips appears between
the search field and the tag list, showing the current selection in the
order it was picked, sliding in and out smoothly as the selection goes from
empty to non-empty and back. The search-as-create row got its own distinct
visual treatment too: a filled plus-circle rather than a plain selection
circle, so it reads clearly as an action rather than just another
selectable row.

## Add/Edit Bookmark: tag chip strip (native apps)

A direct follow-up to the custom layout work above: the tag summary row on
both the add and edit forms now uses the same removable chip strip the tag
picker introduced, instead of static, non-interactive tag pills. Tapping a
chip's remove button drops that tag immediately, without needing to reopen
the full picker sheet just to remove one tag: a small but genuinely useful
convenience once the chip strip existed elsewhere in the app anyway. The
shared chip component moved into its own file in the common layer so it's
clearly reusable rather than looking like an implementation detail of the
picker alone.

## Settings: visual polish (native apps)

The same Things/Craft-inspired polish extended to the Settings screens. The
recurring problem here was that in-place action buttons (Sync Now, Sign
Out, Change Password, enrolling or disabling 2FA, New Smart View) were
inheriting plain full-width form-row styling instead of looking like actual
buttons, and destructive actions had no visual weight distinguishing them
from routine ones. In-place actions became genuine bordered buttons, sized
to their content and left-aligned rather than stretched across the row, with
destructive ones (Sign Out, Disable Two-Factor) tinted red and the primary
creation action (New Smart View) given a filled accent style. Navigation
rows correctly stayed as plain navigation links, since that's the right
native pattern for "go to another screen" rather than "do something here."
The account settings screen and the Smart View management screen both moved
off the grouped form style entirely, onto the same label-above-field layout
introduced for the bookmark forms, with clearer visual separation between
sections.

## Share Extension: visual polish (native apps)

A matching refinement pass on the Share Extension's four states (loading,
signed out, the add form, and confirmation). The add form itself is the
shared bookmark form and already picked up the redesign automatically; this
pass was specifically about the extension's own surrounding chrome. Loading
became a quiet ribbon mark with a muted spinner instead of a generic
progress view with a redundant text label. The signed-out state switched to
the same shared empty-state component used elsewhere, with directive rather
than apologetic copy ("Open the Stash app to sign in, then share this page
again"). Confirmation became a calmer moment overall: a green checkmark,
"Saved to Stash," the actual domain that was saved as concrete confirmation,
the bookmark's tags shown read-only, and an unobtrusive text-only Undo
button instead of a heavier bordered destructive one. The auto-dismiss timer
also got noticeably shorter, from three seconds down to one and a half, once
the confirmation moment itself felt substantial enough not to need lingering
as long.

## Settings: General tab follow-ups (macOS)

The first Settings polish pass missed the macOS General tab, which was
still a grouped form and stood out visually next to the newly-restyled
Account and Smart Views tabs: noticeably more empty space, and its
buttons weren't picking up the new bordered styling at all since the form's
own row chrome was swallowing it. I converted it to match the other two
tabs' layout, and while I was in there also fixed its Server URL field to
use the same label-above-field pattern as the rest of the form, rather than
a plain static-looking value row.

That same URL field then got one more correction shortly after: I'd made it
editable on macOS in that earlier pass, but Settings is only reachable while
already signed in, and switching servers genuinely requires signing out and
setting up against the new instance from scratch, so an editable field
there was actively misleading, not a nice convenience. Both platforms now
show it strictly read-only, with a small footnote explaining that signing
out is how you connect to a different server.

## Add/Edit Bookmark: description field fill + scroll (native apps)

The description field switched from a plain growing text field to a proper
text editor, since a plain text field isn't actually a scroll view and
silently ignored the mouse wheel on macOS once its content overflowed the
visible space: a real usability bug for anyone pasting in a longer
description. Along with that fix, the description field now expands to
fill whatever vertical space is left in the sheet, removing an awkward gap
that used to sit between the tags section and the action buttons when the
description was short: only the description itself scrolls internally when
its content is long, while the rest of the form stays fixed in place.

## Settings: grouped background for custom-layout sheets (native apps)

Once the account settings and Smart View form screens moved off the native
grouped form/list style for their custom label-above-field layout, they
lost the grouped background color that a form or list supplies for free,
and fell through to a plain white background on iOS: visibly inconsistent
with the still-form-based Settings screen sitting right next to them. A
small shared style helper restores the correct grouped background color on
each platform (they use different system colors under the hood), applied to
both affected screens.

## Tag count badge (native apps, then the web frontend)

The sidebar's plain tag count number became a proper badge that
distinguishes visible from archived bookmarks, on both the native apps and
then the web frontend to match. Previously a tag's count was just one
number: either the active count natively, or confusingly the *total*
including archived on the web, which didn't match what the list itself
actually showed by default. Now every tag tracks both an active count and a
total count; when they're equal, the badge is a plain accent capsule
showing that one number, and when a tag has archived bookmarks too, it
splits into a two-tone pill: an accent half showing the visible count and
a muted half showing specifically the *hidden* count, not the total, so a
tag whose bookmarks are all archived still shows up in the sidebar instead
of silently disappearing, reading clearly as "0 visible, 5 hidden" with no
mental arithmetic required. The tag picker deliberately keeps showing a
plain, badge-free count, since picking and assigning tags isn't a context
where archival state matters.

## Sidebar selection occasionally stops refreshing the detail list

An intermittent, genuinely tricky bug on the iPad and macOS split-view
layouts: tapping a different tag or view in the sidebar would sometimes
re-highlight correctly but leave the actual bookmark list on screen
unchanged, and once it happened it stayed stuck for every subsequent
selection until the app was force-relaunched. Timing- and
navigation-history-dependent, which made it hard to pin down.

The reload logic itself was firing correctly the whole time: the actual
problem was the detail column's navigation stack having no stable identity
at all. Two different things were mutating that same stack's root
underneath it: switching between a tag filter and a Smart View selection
swapped which branch of a conditional built the root view, and tapping into
a bookmark's detail pushed a new screen onto that same stack. Change the
selection while a detail was pushed, or flip between the tag and Smart View
branches, and the stack's root would get swapped out from under its pushed
content with nothing keying the stack's identity to notice: its internal
navigation state would desync from the new root and effectively wedge,
after which further selections updated the sidebar highlight but never
touched the actual displayed content again.

The fix was giving the detail navigation stack an explicit identity tied to
the current selection, so every selection change deterministically
rebuilds a fresh stack from scratch: discarding any pushed detail view and
any wedged internal state along with it. That's the idiomatic pattern for
a selection-driven detail column, and it has the nice side effect that
picking a new tag now resets the detail column back to the top of that
tag's list rather than stranding a previous selection's pushed detail view
behind it.

## Tag sidebar refreshes after a sync (not just after a local write)

A narrower instance of the same cross-repository staleness class of bug
covered earlier: after a launch, a manual sync, or a reconnect, the
bookmark list itself would correctly show newly-synced bookmarks, but the
sidebar's tag list would not: a bookmark that synced in carrying a
brand-new tag would appear in the list while that tag was still missing
from the sidebar entirely, only showing up after a full app relaunch. The
tag repository derives its data from the local store and is a shared
singleton, but the sidebars only ever called its load method once on first
appearance, which became a no-op on every subsequent call: nothing was
re-deriving the tag list when a sync mutated the underlying store out from
under it. The fix has each tag sidebar re-derive on the same
syncing-to-idle transition the bookmark list already watches for, keeping
the previous tags visible until the fresh set is ready so there's no empty
flash. I also noticed by this point that the same watch-for-sync-completion
logic had been copy-pasted at each call site, so I pulled it into one
small shared view modifier: a cleanup, not a behavior change; each view
still opts in individually rather than centralizing the trigger itself into
the sync engine.

## Bookmark row tags: accent capsules (native apps)

I reversed an earlier polish decision here: the bookmark row's tags had
been switched to plain, quiet text as part of the content-first visual
pass, but that left the row entirely colorless: a gray domain line, a
primary title, and quiet tags, with only the favicon carrying any color at
all. I brought back the accent-tinted capsule treatment for the row's tags,
so the row and the detail view now render tags identically everywhere
rather than the row using a plainer variant.

## Unreachable backend: fail-fast timeout & a recoverable 2FA setup state

When a device has a working network path but the Stash backend specifically
is unreachable (off the home LAN, the server down, a wrong URL), the
connectivity monitor still reports online, since it only sees the network
path, not whether the actual server behind it answers. Requests would
therefore proceed and just sit blocked on the default 60-second URLSession
timeout. Writes already dodge this entirely thanks to the optimistic-write
work, but two surfaces that genuinely have to wait on the network (a
manual "Sync Now" and 2FA enrollment) were left showing a spinner for a
full minute with no way out.

The fix has two parts. First, every request now uses a much shorter
15-second timeout instead of the default 60, applied once at the shared
client layer so both the app and the CLI benefit automatically: generous
enough for a small JSON API on a LAN, short enough that a genuinely
unreachable server fails with a clear, fast error instead of a long silent
hang. Second, I found and fixed a genuine stuck-spinner bug while looking
into this: the 2FA enrollment screen's error state was only ever rendered
inside the branch where setup had actually started, so a failure on the
very first request left the screen showing a progress spinner forever, with
the error message captured but never displayed anywhere. It now shows a
proper error state with a Try Again button that clears the error and
retries.

## iOS background refresh logged the user out (Keychain protection class)

A genuinely nasty one: iOS users who enabled background app refresh started
getting logged out involuntarily, with no clear trigger: disabling
background refresh made the logouts stop, and macOS was never affected at
all. The root cause turned out to be the Keychain's default accessibility
setting: tokens were stored with the "accessible when unlocked" protection
class, but iOS runs its background sync task while the device is genuinely
locked: at which point the Keychain correctly, and by design, returns
nothing at all for that item. The token manager treats a missing access
token as "expiring soon" and tries to refresh; the refresh token read as
missing too, and the existing refresh logic's guard clause treated that as
a definitive failure and cleared the whole session. The user would then
wake their phone to find themselves logged out, with seemingly no
explanation. macOS was never affected simply because it has no equivalent
locked-background sync trigger at all.

The real fix was changing the token's Keychain accessibility to a class
that stays readable in a locked-but-previously-unlocked-since-boot
background context, which is exactly the standard choice for tokens used by
background tasks: existing tokens migrate to the new setting automatically
on their next normal rotation. I also hardened the refresh logic itself as
defense in depth: a missing refresh token read no longer clears the session
outright, since that read can legitimately be transient (a locked device,
or a not-yet-migrated token before this exact fix lands); only a
genuinely rejected, dead token from the server still triggers a real
logout, consistent with the same "only a definitive failure clears the
session" principle established back in the original concurrent-refresh
race fix.

## Account & Smart View screens moved onto native grouped Forms

The Settings → Account screen and the Smart View editor had drifted into
reading like flat HTML forms translated into SwiftUI, rather than native
iOS/macOS UI: a fair complaint, and one that stood out specifically
because the rest of the app, including the very screen Account was nested
inside, already used proper native grouped forms with row-based sections.
The fix wasn't to invent anything new, just to actually adopt the pattern
already established everywhere else: both screens became real grouped
forms with proper sectioned rows, footer text for hints and error messages,
and platform-appropriate delete affordances: swipe-to-delete on iOS,
since lists have no swipe gesture on macOS a visible remove button there
instead, both alongside a context-menu delete. The macOS General Settings
tab got the same treatment in the same pass, so all three macOS Settings
tabs finally read as one consistent surface instead of two native ones and
one that looked hand-rolled.

## Native clients fetch metadata on-device (out-of-radius add)

The add-bookmark "Fetch metadata" preview was backend-only on every client:
both the app and the Share Extension always sent the URL to the backend to
fetch and parse. Away from the home-lab network, the backend is unreachable
while the rest of the internet is perfectly reachable, so the preview
simply couldn't work at all in that situation, and a "try the backend,
then fall back locally" scheme would still have to wait out a full request
timeout before it could even discover the backend was unreachable, which
would have made every single fetch feel sluggish regardless of network
state. Since the backend's own metadata parser is already a small,
dependency-free regex-based parser with no server-specific logic in it, I
ported it verbatim to the client instead: the native clients now always
fetch and parse metadata locally, never touching the backend for this at
all, and the fetch never throws; any failure just quietly returns no
metadata rather than blocking the add. Favicon caching, the one genuinely
server-side part of this whole flow, is unaffected, since it's triggered
separately when the bookmark actually reaches the backend on save,
regardless of where the title and description preview came from.

## Share Extension picks tags offline (out-of-radius add)

The companion gap to the fix above. The app's own tag picker already works
offline, since its tag repository reads from the local on-device store,
but the Share Extension, by design, never opens that store at all, since
it's a separate, deliberately online-only process. Away from the home-lab
network, its tag fetch would simply fail, and the picker would show no tags
whatsoever, precisely the kind of frustration that pushes someone to
just open the main app instead while out and about.

I considered relocating the local store into the shared App Group container
so the extension could read it directly, and rejected that: it would
reverse the extension's deliberate online-only design, require migrating
every existing installation's private on-device store, and load an entire
bookmark library into a memory-constrained extension process just to read
tag names. Instead, the app now writes its already-computed tag list into
the same shared storage mechanism that already carries the configured
server URL, and the extension seeds itself from that snapshot on launch,
falling back to it whenever a live network fetch fails rather than showing
an empty picker. This is a narrow, deliberate relaxation of "the extension
never touches app-only data": tags only, and still nothing resembling
direct store access.

## In-app browser preference (native apps, iOS/iPadOS)

Tapping a bookmark link always handed off to the system's default browser,
with no way to view a page inside the app itself. I added a Browser
preference (in-app or default browser, defaulting to in-app) built on
Apple's own recommended component for exactly this situation, which brings
Reader mode, AutoFill, content blockers, and shared Safari cookies for
free, rather than building a bare web view and having to reimplement all of
that browser chrome myself. Every place a bookmark link can be opened, the
detail page's URL, the "Open in Browser" button, the row's context menu,
routes through one centralized URL-opening override rather than three
separate edits, so the shared list and detail views themselves needed no
changes at all, and macOS keeps its default-browser-only behavior for free
with zero platform-specific branching. Only actual http/https links are
intercepted; anything else (mail links, phone numbers, share actions)
passes straight through to the system unmodified, both for correctness and
because the in-app browser component only accepts http/https anyway.

A follow-up shortly after added a Reader-mode toggle alongside the browser
choice, since Reader mode is only meaningful when browsing happens inside
the app in the first place; the toggle is disabled outright when the
preference is set to the system default browser, since there's no way to
request Reader mode from an external browser handoff.

---

## Accent palette: replaced Terracotta with Indigo

I swapped the tenth accent theme, Terracotta, for a new Indigo option in
the same slot, keeping the palette at ten themes total and every other
theme untouched. The light value is the exact indigo used in the app's own
icon mark, deliberately tying this particular accent choice back to the
product's own visual identity, something none of the other nine themes
do. Unlike Terracotta, which used one identical hex for both light and dark
mode, that specific indigo is too dark to read well as an accent color on a
dark background, so the dark-mode value lightens it considerably, following
the same light-in-dark convention every other theme already uses. Any
instance previously set to Terracotta just falls back to the default theme
automatically, since that identifier no longer resolves to anything.
