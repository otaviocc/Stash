# Stash: Decision Log

This is my running log of the technical and design decisions I made while
building Stash, the companion to [`PRODUCT.md`](./PRODUCT.md). `PRODUCT.md`
says what I set out to build; this records how I actually built it and why,
especially the choices that aren't obvious from the code, the places I
deviated from the plan, and the trade-offs I accepted along the way.

### How I keep this updated

I add to it whenever I finish a milestone or a meaningful chunk of work, under
the relevant heading (a new one if it's a new milestone). Entries stay short:
what I decided, why, and the trade-off or alternative when one mattered, with
PRD sections referenced as `§n`. I'd rather append than rewrite; a decision I
later reversed gets marked *Superseded* with a pointer to what replaced it,
instead of being deleted outright. This is a decision log, not API docs;
endpoint/behavior reference lives in `Docs/api.md`.

### A rough legend

Not every entry needs a label, but where it helps I mark a decision as a
deviation from `PRODUCT.md`, or as superseded by a later decision; I say so
in the sentence rather than leaning on symbols.

---

## Cross-cutting conventions

I replaced Vapor's default error middleware with a custom `StashErrorMiddleware`
so every API error, including routing 404s and validation failures,
serializes to the same `{ error, code, message }` envelope (§17.4).
Strongly-typed `APIError` cases own the status/code/message mapping, and the
duplicate-URL case carries an extra `existingID`.

For testing I settled on `VaporTesting` + swift-testing running against an
in-memory SQLite database (§17.7) rather than Postgres, fast and isolated,
and production still runs on Postgres; the only schema concession is that
array/JSON columns map slightly differently per driver (more on that in M2).
I never got around to unit-testing the Leaf templates themselves (§17.7);
Leaf errors only show up at render time, and the existing suite can't catch
them, so each web feature gets a throwaway end-to-end smoke test (log in, do
the thing, assert) that I run once and delete.

One dependency snuck outside what §17.2 lists: `fluent-sqlite-driver`, needed
because §17.7 requires an in-memory SQLite test database. Postgres is still
the production driver.

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

## M4: Docker & deployment

The Docker image is multi-stage and jammy-matched: it builds on
`swift:*-jammy` and runs on `ubuntu:22.04`, so the build glibc/ABI actually
matches the runtime. The static Swift stdlib plus jemalloc ship in the
runtime image; nothing else does, just the binary and the libraries it
needs. It's arch-agnostic, so `buildx` produces both `linux/amd64` and
`linux/arm64` from the same Dockerfile. (The build base started on
`swift:5.10-jammy` and was later bumped to `swift:6.1-jammy`.)

First-boot admin seeding lives in `configure.swift` (`AdminSeeder`, running
after migrations): it seeds the admin from `ADMIN_USERNAME`/`ADMIN_PASSWORD`
only when the database has no users yet, throws and exits if those
credentials are missing or invalid (I didn't want a login-less instance to
ever start), and is a silent no-op on every boot after that. It never runs
against the test database.

Migrations auto-run on boot in every environment, so the canonical
`docker compose up -d` needs zero manual steps: Fluent tracks which
migrations have already applied, so re-running on every boot is safe and
idempotent.

`.env.example` is Docker-oriented: it documents the four variables from §16
(`DB_PASSWORD`, `JWT_SECRET`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`), and Compose
interpolates the full `DATABASE_URL` from `DB_PASSWORD`. A local, non-Docker
run exports `DATABASE_URL` directly instead.

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

## M6: StashKit (shared Swift package)

StashKit splits into exactly three layers and no more, mirroring a pattern
I'd used before in `MicroblogAPI`, built on top of `MicroClient`
(`from: "0.0.27"`, Swift tools 6.0, iOS 17 / macOS 14 at the time):
`Codable`/`Sendable` DTOs matching the API's wire shapes, request factories
that build typed `NetworkRequest` values, and a thin `StashClient` wrapping
`MicroClient.NetworkClient`.

Each API domain gets its own factory enum: `AuthRequestFactory`,
`BookmarkRequestFactory`, `TagRequestFactory`, `MetadataRequestFactory`,
`AdminRequestFactory`, all `public static` methods, every path prefixed
`/api/v1/`. They're pure value builders with no I/O, so testing one just
means inspecting the `NetworkRequest` it returns.

StashKit decodes wire shapes into DTOs and stops there: mapping those DTOs
into domain models is the app's repository layer's job (from M8 on). The
package carries no business logic and no domain types. `BookmarkPageDTO` is a
`typealias` over a generic `PageDTO<T>` matching Vapor's `Page<T>` envelope.

`StashClient` itself is genuinely thin: it owns the `NetworkConfiguration`
(base URL plus a `BearerAuthorizationInterceptor`) and exposes one `run(_:)`
that delegates straight to `NetworkClient`. No token storage, no silent
refresh, no business logic: refresh-on-401 is the repository layer's job
(§8.1). Its only real value-add over the bare `NetworkClient` is mapping
errors. That mapping (`NetworkClientError → StashAPIError`) lives entirely in
`StashClient.run`: on a non-2xx response it decodes the standard
`{ error, code, message, existingID? }` envelope and switches on `code`:
`duplicate_url` plus its `existingID` becomes `.duplicateURL(existingID:)`,
any 5xx or `internal_error` becomes `.serverError`, and anything undecodable
or unrecognized falls back to `.serverError` or `.unknown(error)`. The
backend's `cannot_delete_self` code has no dedicated case, since it's really
a UI-level guard, and maps to `.unknown`.

The package stays storage-agnostic via a
`tokenProvider: @escaping @Sendable () async -> String?` closure passed into
the initializer; the app supplies the current access token from wherever it
actually lives (Keychain from M8 on, in-memory in tests). StashKit defines no
`TokenStore` protocol and never touches the Keychain itself. A second,
internal initializer accepts a `URLSessionProtocol` so tests can inject a
mock session. Dates round-trip correctly because `StashClient` configures its
encoder/decoder with the same `.iso8601` strategy Vapor's
`ContentConfiguration` uses by default; I checked this against Vapor's
source rather than assuming it.

One real limitation: hierarchical tag deletion is constrained by how
`MicroClient` builds URLs. It appends path components via
`URL.appendPathComponent`, which treats `/` as a separator and re-encodes a
literal `%` (so a pre-encoded `%2F` becomes `%252F`). That means a single
path segment can't carry an encoded slash, so
`TagRequestFactory.makeDeleteRequest(tag:)` just passes the raw tag and lets
`appendPathComponent` percent-encode it. That's correct for flat tags and for
deleting an entire parent subtree (`swift` removes `swift` and everything
under it), but it can't target one specific hierarchical child like
`swift/vapor` in isolation, given this dependency. I've accepted that for now
and would revisit it if child-specific deletion turns out to matter from a
client.

The spec originally called for StashKit to have zero external dependencies
beyond Foundation and URLSession (§15). I built it on `MicroClient` instead,
which is itself Foundation/URLSession-only under the hood, so the
data-ownership spirit holds even if the letter of that constraint doesn't.
Similarly, §15's proposed in-memory tag-autocomplete cache doesn't live in
StashKit: that's stateful, session-scoped behavior that belongs in the app's
repository layer alongside refresh and storage, not in a stateless
request/DTO package; `TagRequestFactory.makeListRequest()` just supplies the
raw data.

Two endpoints (`auth/totp/disable` and `admin/users/:id/reset-totp`) had
StashKit factories (`makeTOTPDisableRequest`/`makeResetTOTPRequest`) before
the backend actually exposed them on the JSON API; they'd first shipped only
on the web controllers. The backend has since caught up and exposes both at
exactly the paths StashKit was already targeting.

Tests inject a `MockURLSession` conforming to `MicroClient.URLSessionProtocol`
that records the last request and replays a canned status and body,
following the same Given/When/Then, "It should …" structure as the backend
suite. Coverage spans query-item construction (including the `__untagged__`
sentinel), every factory's path/method/body encoding, and `StashClient.run`'s
decoding and error-mapping, including a parameterized test walking every
error code to its `StashAPIError` case, 13 tests in total.

Lint and format config is copied straight from the backend, the same
`.swiftformat` and `.swiftlint.yml`, MIT header and all, so
`swiftformat --lint` stays idempotent and `swiftlint lint` reports zero
violations here too.

---

## M7: CLI (`stash`)

The CLI (`CLI/`, executable target `stash`, Swift tools 6.0, macOS 14+) is
built on `swift-argument-parser` (`from: "1.5.0"`) and the local `StashKit`
package (§14/§17.2), one type per command. Every command is its own
`AsyncParsableCommand`; related ones group under a parent (`config`,
`bookmarks`, `tags`, `admin`), and shared business logic stays in StashKit's
request factories: the CLI itself is purely presentation and orchestration.
The most common bookmark commands (`list`/`add`/`get`/`delete`/`archive`) are
registered both under the `bookmarks` parent and directly at the root, so
`stash list` and `stash bookmarks list` resolve to the same type; `stash tags`
and `stash bookmarks` use a default subcommand so the bare group lists.

`ConfigStore` reads and writes `~/.config/stash/config.json` in one file:
base URL, access token, refresh token, all optional, so a missing file just
loads as an empty config and first-run commands fail with a clear "not
configured / not logged in" message instead of crashing. (`CLIConfig` needed
an explicit `init(… = nil)` because the shared `.swiftformat` config strips
property `= nil` defaults, which would otherwise break the no-arg
`CLIConfig()`.)

Before any authenticated command, `CLIRuntime` decodes the access token's
`exp` claim by hand (no library, same as elsewhere) and proactively
refreshes when it's within 60 seconds of expiring and a refresh token exists,
persisting the rotated pair. A failed refresh clears both tokens and tells the
user to run `stash login` again; an unparseable token is treated as expiring,
but if there's no refresh token at all the command just proceeds and lets the
server reject it, so a manually `set-token`'d access token still works for
scripting.

Login needed its own request builder to cover the 2FA branch: `POST
/api/v1/auth/login` returns either a token pair or a `{ requires2FA,
tempToken }` challenge, both as HTTP 200, and StashKit's typed
`makeLoginRequest` only knows the token-pair shape. So the CLI declares a
local `LoginOutcome` that decodes both, and builds that one `NetworkRequest`
directly, which is why the CLI depends on `MicroClient` explicitly, on top
of StashKit and ArgumentParser. That's the one deviation from the §14
dependency list.

Import and export are re-implemented client-side over the public API, since
the import endpoint is web-only (§13). `stash import` parses the file locally:
`ImportParser` re-implements the Anybox tag mapping and the Stash-JSON
shape, mirroring the same URL/tag normalization `Bookmark` uses, and submits
each record through the create endpoint, falling back to update when the
server reports `duplicate_url`. `stash export` paginates through both active
and archived bookmarks (the list API splits on `archived`, so both need
fetching separately) and assembles the native export envelope sorted by
`createdAt`. One accepted limitation: the public create endpoint has no
`createdAt` field and no way to set archived-on-create, so CLI-imported
bookmarks get a fresh `createdAt`, and an archived record has to be created
then updated to set the flag: the web importer, with direct DB access,
preserves the original `createdAt`; the CLI can't. (Re-importing a Stash
export of already-existing bookmarks takes the duplicate-update path instead,
where `createdAt` is preserved (I verified this is idempotent against a
212-bookmark export).

Output conventions: results and success lines go to stdout (plain
fixed-width tables, or pretty-printed `--json`), while prompts, delete
confirmations, and error messages go to stderr, with a non-zero exit on
failure. Hidden password entry reads directly from `/dev/tty`. I also had to
make transport errors readable: a bare `MicroClient.NetworkClientError error
0` told a user nothing when they pointed the CLI at `https://` against a
plain-HTTP server, so those now surface as actual sentences, e.g. "Could not
reach the server. A TLS error caused the secure connection to fail. (Check
the URL and scheme: a plain HTTP server needs http://, not https://.)".

Admin commands take usernames rather than the UUIDs the admin API actually
wants, so `suspend`/`unsuspend`/`reset-password`/`reset-totp`/`delete-user`
first list users and match case-insensitively before issuing the real
request.

Building the CLI's live write path also surfaced a real StashKit bug:
`StashClient` only configured a `BearerAuthorizationInterceptor`, so every
POST/PUT went out with a JSON body but no `Content-Type` header, and Vapor
rejected every write with a `400 bad_request` ("No value found at path
'url'"). StashKit's mock-based tests never exercised a real header, so this
was invisible until the CLI started making live calls. I added
`ContentTypeInterceptor` and `AcceptHeaderInterceptor` to the client's
interceptor chain, a one-line fix that also benefits the iOS/macOS clients
later, and verified it end-to-end: create, duplicate detection,
update-on-import, archive, tag rename/delete, and the full admin user
lifecycle.

`admin reset-totp` will 404 until the backend adds the route to the JSON API;
as noted under M6, that endpoint exists only on the web controller so far.
The CLI command itself is correct and calls the documented path; it'll start
working the moment the backend catches up.

No CLI unit tests, by design (§18.7): manual integration only. The build is
clean, formatting is idempotent, linting reports zero violations, and every
command has been exercised against a live backend instance.

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

## Linting & formatting (SwiftLint + SwiftFormat)

I found that SwiftFormat's organization rules (`organizeDeclarations` and
`markTypes`) are opt-in and disabled by default, and the config had supplied
all their options without ever actually turning the rules on, so no MARK
organization was happening at all. Enabling both applies an MIT header, a
`// MARK: - <Type>` before each type, and in-type sections ordered
Nested Types → Static Properties → Properties → Computed Properties →
Lifecycle → Functions, public before private within each section. I chose
type-mode organization over visibility-mode deliberately: the codebase is
overwhelmingly `internal`-access, so visibility mode would have mostly
produced `Internal`/`Private` headings rather than anything meaningful.
`Package.swift` stays untouched by the header rule, since SwiftFormat already
knows to keep `// swift-tools-version:` on line 1.

Three SwiftLint rules got disabled because they false-positive on Fluent's
query DSL: `first_where`, `contains_over_first_not_nil`, and `empty_string`
all want to rewrite database-builder calls as if they were plain `Sequence`
operations, which would break compilation. A handful of idiomatic short
names (`db`, `q`, `i`, `a`, `b`, `c`, `s`, `v`, `ok`, `ts`, `me`) are
excluded from `identifier_name` rather than renamed everywhere. I also
disabled the length-based rules (`file_length`, `type_body_length`,
`function_body_length`) for consistency with the complexity rules already
off in the config: the web controllers and test suites legitimately run
long, and this is easy to revisit with soft thresholds if I ever want a
gentle nudge instead of silence. End state: zero lint violations, idempotent
formatting, a clean build, 65 passing tests.

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

## Code style: comments and documentation

I don't allow comments of any kind inside method or function bodies: code
and tests are the documentation, and if a body needs a `//` explaining what
it does, that's usually a sign that the code itself isn't clear enough. All
documentation lives at the declaration level instead. (The one exception is
the backend tests' `// Given` / `// When` / `// Then` structure markers,
below.) I initially said doc comments were for types only, but that turned
out to be un-enforceable: SwiftFormat's `--doc-comments before-declarations`
auto-upgrades any `//` placed before a declaration into a `///` doc comment
regardless of what kind of declaration it is, so the rule now just reflects
what the formatter actually produces: doc comments are fine on types,
properties, and methods alike. Everything is American English throughout:
`behavior`, not `behaviour`; `color`, not `colour`, including test
descriptions, which follow Given/When/Then structure with every expectation
phrased as "It should …".

## Code style: blank lines

A blank line after the last `guard` in a group is enforced automatically by
SwiftFormat. Blank lines before `if`/`for`/`switch` and before a `return` in
a multi-statement body aren't: neither SwiftFormat nor SwiftLint has a rule
for it, and building a custom one felt fragile, so that one stays a
hand-applied convention rather than a machine-enforced rule.

## Code style: commit messages

I follow the seven rules of a good commit message
([cbea.ms/git-commit](https://cbea.ms/git-commit/)): separate subject from
body with a blank line, keep the subject under 50 characters, capitalize it,
no trailing period, imperative mood ("Add", "Fix", not "Added"/"Adds"), wrap
the body at 72 characters, and use the body to explain what and why, not
how. Nothing enforces this with a hook: it's just discipline. A single
cohesive change gets prose paragraphs; a commit grouping several distinct
changes gets `-` bullets. I went back and reworded the whole repository's
early history at one point so every subject line actually fit in 50
characters.

## iOS/macOS project: committed, off XcodeGen

I originally generated the Xcode project from `project.yml` with XcodeGen
and gitignored the `.xcodeproj` itself, but reversed that decision: the
project is committed now and XcodeGen is gone. Two things drove the switch:
regenerating kept wiping out Xcode's "update to recommended settings," and I
wanted the modern synchronized-folder format where a folder on disk is
referenced once instead of every file being individually listed in the
project. `xcuserdata/` stays gitignored; the shared schemes are committed.
Since membership in synchronized folder groups is folder-level, it fits this
codebase well: platform splits are already `#if`-guarded rather than
per-file, so `Common/` maps to all four targets, `Stash/` to both apps,
`StashShareExtension/` to both extensions. I did this conversion inside
Xcode itself rather than scripting a `.pbxproj` rewrite: round-tripping
through `plutil` emits an XML-format project that breaks `xcodebuild`'s
package resolution and scheme autocreation, so tooling shouldn't try to
regenerate this project. I also renamed the outer cross-target `Shared/`
folder to `Common/` and flattened the inner, app-only `Stash/Shared/` up
into `Stash/` directly, since once the outer folder was `Common/` the inner
`Shared/` name was just redundant.

## Merged the iOS and macOS targets into multiplatform targets

M10 had created genuinely separate iOS and macOS targets. With SwiftUI
there's no real reason for that split, so I collapsed all four targets down
to two multiplatform ones (`Stash` and `StashShareExtension`) supporting
iPhone, iPad, and Mac from one scheme selected by run destination. This
needed zero Swift changes, since the code was already `#if`-guarded and the
single `@main` already branched per platform. Per-platform `Info.plist` and
entitlement differences (a handful of keys, plus macOS-only sandbox and
network-client entitlements) moved into a small non-synced `Config/` folder,
selected by SDK-conditional build settings, which also happened to fix a
stray-`Info.plist` defect the synchronized-folders conversion had
introduced, since with no plists inside the synced folders there's nothing
that can leak into the wrong bundle. I edited the project file with the
`xcodeproj` Ruby gem rather than `plutil`, for the same XML-round-trip
reason as before, and verified the result by building both destinations
cleanly from the one scheme.

## StashApp: fixed miscategorized files within `Stash/`

I kept the macro `Common/` / `Stash/` / `StashShareExtension/` split as-is,
since it encodes real Xcode target membership rather than just taste: files
in `Stash/` look shareable at a glance, but `Stash/` *is* the iOS↔macOS
shared layer already; its stateful repositories, the SwiftData store, and
the sync engine are app-only by design, and pulling them into `Common/`
would bloat the process-isolated, online-only Share Extension with code it
can't use. I did move three files to the subfolder that actually matched
what they are: `LocalStore` and `LocalBookmark` into a new `Persistence/`
subfolder (a service and a persistence entity, not "Models" in the domain
sense), `BookmarkFilter` into `Support/` (a stateless helper enum, not a
repository), and `SyncModifiers` into `Views/` (a SwiftUI `ViewModifier`,
same kind as another modifier already living there). All pure disk moves:
synchronized folder groups pick them up automatically with no project file
edit.

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

## M4.1: CI/CD pipeline & Docker image publishing

Two workflows, split by trigger and cost. `ci.yml` runs on every push to
`main` and every pull request, building and testing every component but
publishing nothing, so it stays a cheap regression gate. `release.yml` runs
only on a `v*.*.*` tag push: it re-runs the backend tests and, only if
those pass, builds and publishes the Docker image. Keeping image publishing
tag-only means routine pushes never pay for the multi-arch build.

Getting the backend test job right in CI took a couple of iterations. I
first built and tested it with `-c release`, to validate the shipping
configuration in one pass, but that crashed the Swift 6.2.1 compiler in
CI: its SIL optimizer, which only runs under release optimization, hit a
fatal error compiling the Vapor dependency tree. A regression gate doesn't
actually need release optimization (the Docker image build validates that
separately, on Swift 6.1), so the backend now just runs `swift test` in
plain debug, which sidesteps the crashing optimizer entirely. Then I found
the tests needed to run serially: swift-testing parallelizes by default, and
each test boots its own `Application` and hashes passwords at bcrypt cost
12 on purpose (slow), which starved the SQLite connection pool on a CI
runner: six of seventy-six tests failed with connection timeouts, no logic
failures, just contention. Running with `--no-parallel` removes that
contention entirely; the trade-off is a slower CI run, which is fine for a
gate. This never showed up locally on a fast multi-core Mac, which is why
it only surfaced in CI.

Docker builds use GitHub's layer cache in `mode=max`, so the expensive Swift
package-resolution and compilation layers are reused between runs, which
makes subsequent tagged releases substantially faster.

Making the published image public turned into a small research detour. The
original plan was to `curl PATCH` the image to public visibility from CI,
but that doesn't actually work: there's no REST endpoint for container
package visibility at all (the Packages API only exposes
get/delete/restore; visibility is a web-UI-only setting), and even if there
were, `GITHUB_TOKEN` is a bot installation token that can't call the
user-scoped API anyway. Worse, a bare `curl` without `--fail` would have
swallowed the 404 silently and left the job green, a no-op nobody would
notice. I removed the step and replaced it with a one-time manual
instruction instead: flip the package to public by hand once, after the
first push, and it stays public for every push after that. The source
repository itself stays private; only the image is public. Everything that
*is* automated (the GHCR login, the multi-arch push, the release
creation) authenticates with the workflow's own `GITHUB_TOKEN`, no personal
access token needed.

The release itself attaches the canonical `docker-compose.yml` to a GitHub
Release, so someone can grab just that file and run `docker compose up -d`
against the published image with no clone and no build.

`ci.yml` ended up split into a Linux `backend` job and a macOS `apple` job,
because the components genuinely don't share a platform or a toolchain.
StashKit and the CLI depend on `MicroClient`, which uses Apple Foundation's
networking types without the shim Linux needs, so they simply don't compile
there: the `apple` job has to run on macOS, covering StashKit, the CLI, and
the app plus Share Extension for both iOS and macOS, all on one runner
(macOS runner minutes bill at roughly 10× on a private repo, so I didn't
want to fan this out further). The app itself has no test target by design,
so CI build-verifies it on both platforms rather than unit-testing it:
enough to catch compile-level regressions across the cross-platform `#if`
shells, which is the actual risk for a target with no tests.

---

## HTTPS / Caddy

HTTPS is an optional Caddy sidecar, not something built into the image
itself: Stash serves plain HTTP internally, and TLS termination is a
deployment concern, the same pattern other self-hosted tools like Navidrome
use. That keeps the app simple and doesn't force HTTPS complexity on anyone
who doesn't need it. Caddy is documented as an opt-in addition to the
compose file, covering both a local-network case (self-signed, with
root-CA trust instructions per platform) and an internet-exposed case
(automatic Let's Encrypt); no changes needed to the Stash image or the
Vapor backend itself.

---

## Documentation

All documentation ended up consolidated into one top-level `Docs/` folder:
I merged every component's docs in and deleted the per-component READMEs
that had accumulated, leaving the root `README.md` as a concise landing page
that links into `Docs/`. The standing rule going forward: a new component or
feature gets one guide in `Docs/`, never a `Component/README.md`: the
browser extension actually shipped with its own README first and I folded
it into `Docs/browser-extension.md` shortly after, to match everything else.
The `caddy/` directory of committed Caddyfile variants also got folded into
`Docs/backend-docker-caddy.md` and removed: now there's a single documented
source of truth as copy-paste blocks, instead of files in the repo that
could quietly drift from the walkthrough describing them.

---

## Markdown style: hard line breaks

All Markdown in this repo uses hard line breaks, prose wrapped at 80
characters, rather than long flowing paragraphs: it's easier to read in a
plain text editor and produces cleaner, more reviewable diffs. Code blocks,
tables, and headings are left alone, since tables in particular can't be
narrowed without losing their structure.

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
is hardcoded directly in the footer template rather than passed through
context, specifically so it can't be accidentally omitted, overridden, or
removed by an admin. The version string is read from a `VERSION` file at
startup and falls back to `"dev"` if that file is missing or empty. The
theme picker itself needs no JavaScript at all: just visually-hidden radio
inputs with CSS drawing the active ring around whichever swatch is checked.

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

## Browser Extension

The browser extension (`Extension/`) saves the current page to a Stash
instance from Firefox or Chrome (including Zen), talking directly to the
REST API, no backend, StashKit, or native-app changes needed at all.

It's plain HTML and vanilla JS with no build step, the same philosophy as
the server-rendered web UI: no npm, no bundler, no framework. The
extension is small enough (a popup, an options page, a service worker) that
a framework would add real tooling overhead for no meaningful gain, and
every file just loads directly in the browser. It's Manifest v3, and one
manifest genuinely serves both browser engines: the background script is
declared with both the `service_worker` key Chrome wants and the `scripts`
key Firefox/Zen require instead (they reject a service-worker-only
manifest outright), and each engine just uses the key it understands and
ignores the other.

`background.js` owns all token storage and every API call: it's the only
place that touches extension storage for tokens at all, and the popup and
options pages talk to it purely through message passing. That keeps login,
the silent-refresh window, the refresh-on-401 retry, and logout all in one
place, mirroring the same centralization pattern the app and the CLI both
use. The JWT `exp` claim is decoded by hand here too, the same
dependency-free approach as everywhere else in the project, refreshing
within 60 seconds of expiry and once more on an outright 401. The 2FA
branch is handled inline on the settings page, switching on the same
either-token-pair-or-challenge response shape the CLI and app both handle:
the extension has to support 2FA-enabled accounts, so this couldn't be
deferred.

The URL field in the popup is read-only by design: the extension saves the
page you're currently on, and making the URL editable would mean navigating
away from that page just to fix a typo, defeating the whole point. There's
deliberately no undo and no "save another" here either, unlike the Share
Extensions: a popup's lifecycle is too short for a timer-based undo (closing
it cancels the timer), and since the extension only ever saves the tab
you're on, there's nothing more to add once that's done. A duplicate URL
just surfaces inline as "Already saved" with a link to the existing
bookmark.

Icons are generated programmatically from one master SVG via a small Python
script using Pillow, so the various manifest sizes stay reproducible from
source instead of being committed as opaque binaries with no lineage. With
no compile step, "build" here just means packaging: a small Makefile wraps
linting, icon generation, and zipping for store submission, using only
`zip`/`python3`/`node`, keeping the no-build-step promise intact even for
tooling. Linting itself degrades gracefully: Mozilla's proper extension
linter is an npm tool the project deliberately avoids depending on, so `make
lint` uses it if it happens to be installed and otherwise falls back to
dependency-free checks: valid JSON, and each JS file passing a basic syntax
check. That's the one automated guard that actually matters here, since
there's no compiler to catch a malformed manifest or a JS typo otherwise.

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

## SwiftUI view decomposition convention (native apps)

I settled on a consistent way to break up SwiftUI views across the whole
app: a sub-piece of a view is a private `make…() -> some View` function,
named `make` plus whatever it produces, rather than a computed-`var`
subview: a style I'd already used throughout a sibling project and liked
enough to standardize here. `var body` stays a small composition of those
`make…()` calls instead of one sprawling view tree; a plain, non-view
computed property like `isValid` or a navigation title stays a normal `var`,
since only `some View`-returning members get the function treatment. I
applied this across the whole app in one pass: converting existing
computed-var subviews, renaming a handful of view-returning functions that
didn't follow the `make` prefix, and slicing several of the larger bodies
(the bookmark detail screen, login, the Smart View form, the sidebars) into
proper pieces. Purely structural, with identical view trees and modifier
order: no behavior changed. SwiftFormat's organization rule files these
under one consistent MARK automatically, so I never have to hand-place them.

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

## Offline Sync: landing page copy

The public landing page predated offline sync entirely and still described
the native apps with no mention of local storage or syncing at all. I
updated the hero copy to say the apps "work offline," and rewrote the
platform feature card to spell out the actual differentiator: a full local
copy of the library, browsing and saving while offline, automatic sync on
reconnect. I folded this into the existing platform card rather than adding
a seventh feature card, specifically to keep the feature grid's balanced
three-by-two layout intact.

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

## 2FA disable / reset land on the JSON API

Two endpoints the original spec called for (self-service 2FA disable and
an admin-triggered 2FA reset) had only ever been implemented on the web
controllers, even though StashKit's request factories already targeted
their documented API paths in anticipation. This closed that gap: both now
exist on the JSON API too, at exactly the paths StashKit already expected,
so no client code needed to change at all, this was purely catching the
backend up to the contract everyone else already assumed. Both invalidate
every refresh token for the account on success, matching the spec, which
is actually a small deliberate improvement over the older web handler that
had historically skipped that revocation step. Along the way, a code review
pass caught two rough edges before they shipped: the response shape had
drifted from the sibling endpoint's convention, and the admin reset
endpoint was unconditionally running its teardown logic even against a
user who'd never enabled 2FA in the first place, which would have silently
signed out every one of that user's sessions for no reason: both fixed
before release, with new test coverage for the success path, the
already-disabled no-op case, and the permission-denied case.

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

## Smart View form: condition row buttons follow-up (native apps)

A small icon-only follow-up: the condition row's add/remove buttons in the
Smart View form switched from generic bordered buttons to proper SF Symbol
icon buttons: a neutral minus-circle for remove, an accent-colored
plus-circle for add, which reads more consistently with the rest of the
app's iconography. No behavior change.

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
showing the description and date the native row omits, since the web is
inherently a denser reading surface than a phone screen.

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

## Per-machine signing & bundle identifier (xcconfig)

I build this app under two different Apple developer accounts on two
different machines, each with its own bundle prefix. Previously the team id
and prefix were hardcoded throughout the committed Xcode project, several
entitlement files, several Info.plists, and a handful of Swift constants:
switching machines meant editing tracked files by hand and risking
accidentally committing the wrong account's identifiers.

Now there's exactly one source of truth: a committed base xcconfig file
defining the bundle prefix and the development team, wired in at the
project level so both targets inherit it. A second, gitignored xcconfig can
optionally override either value on a given machine: present, it wins;
absent, the committed defaults apply silently, so the primary machine needs
no extra file at all. Every bundle-keyed identifier (the app's bundle id,
the extension's, the App Group name, the exported file type, the background
task identifier) derives from that one prefix at build time and again at
runtime by reading it back out of the built app's own Info.plist, so the
build settings and the Swift constants can never drift apart from each
other. Change the one xcconfig line, and the whole graph of derived
identifiers follows automatically.

## Bookmark row tags: accent capsules (native apps)

I reversed an earlier polish decision here: the bookmark row's tags had
been switched to plain, quiet text as part of the content-first visual
pass, but that left the row entirely colorless: a gray domain line, a
primary title, and quiet tags, with only the favicon carrying any color at
all. I brought back the accent-tinted capsule treatment for the row's tags,
so the row and the detail view now render tags identically everywhere
rather than the row using a plainer variant.

## Documentation: Podman runtime & local-dev compose override

Two documentation-only additions. First, Podman is now documented as a
supported alternative to Docker for running Stash, since it's API-compatible
enough that the published image and the committed compose file work
completely unchanged: the only difference is at the operator's own
machine, pointing tooling at Podman's socket instead of Docker's, so nothing
in the repo itself needed to change to support it. Second, the local-dev
workflow for building from source (rather than the published image), which
previously only lived in the Makefile and in my own dev-environment
notes, finally got written up properly in the user-facing docs, so a
contributor doesn't have to reverse-engineer it from the Makefile alone.

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

## Open-sourcing prep: footer GitHub link, scrubbed identifiers, OSS scaffolding

A few small things done specifically in preparation for eventually making
this repository public. The footer gained a GitHub link alongside the
existing Mastodon and Ko-fi ones. My real Apple Developer Team ID and my
personal legacy bundle prefix, both of which had been hardcoded throughout
committed config, docs, and source, were replaced everywhere with
placeholder values, matching the same placeholder pattern already used for
the machine-local xcconfig override, deliberately leaving the historical
prose in this very document describing what was actually built under the
old identifiers untouched, since it's an accurate record of what happened
at the time, not something that needs to match today's placeholders. And
the repository picked up the standard scaffolding an open-source project is
expected to have: a license, a contributing guide, a code of conduct, a
security policy, and issue/PR templates, even though the repository itself
stays private for now. This is preparation, not a visibility change yet.

## License: split MIT into AGPLv3 (Backend) and MIT (everything else)

The MIT license added just one commit earlier covered the whole monorepo,
but MIT does nothing to stop someone from taking the server, running it as
a hosted service with modifications, and never sharing those changes back,
the same "SaaS loophole" that Immich, Nextcloud, Mastodon, and Grafana all
close by licensing their server under AGPLv3 instead. I'm the sole
copyright holder, so relicensing needed no one else's sign-off, and I split
the license along the same server/client boundary that already exists in
the repo: `Backend` moved to AGPL-3.0-only, while `StashKit`, `CLI`,
`StashApp`, `Extension`, and `StashSkill` stayed MIT. `StashApp` staying
MIT specifically rules out an App Store conflict: Apple's terms are
incompatible with (A)GPL, and I want the door open to the App Store later.
`StashKit` staying MIT rather than following `Backend` into AGPL was the
one non-obvious call: `Backend` links it, and combining permissive code
into an AGPL work is allowed, so the combined Backend distribution is still
governed by AGPL while `StashKit`'s own source, and every client that
links it, stays copyleft-free.

The per-file header changed shape at the same time, from the full MIT text
pasted into every source file to a two-line SPDX identifier
(`SPDX-License-Identifier: AGPL-3.0-only` or `MIT`, per component). That
header lives in one place per component: the `--header` line in each
`.swiftformat`, so the four config edits regenerated all ~230 file headers
in one SwiftFormat pass rather than needing a hand edit per file. `Backend`
also gained its own `LICENSE` file with the full AGPLv3 text alongside the
root MIT `LICENSE`, and `StashSkill` got a copy of the MIT `LICENSE` too,
since it's meant to be copied standalone into someone's `.claude/skills`
directory and shouldn't rely on the rest of the repo being present to stay
license-compliant.

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
