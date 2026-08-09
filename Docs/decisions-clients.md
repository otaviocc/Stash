# Stash Decisions: StashKit, CLI & Browser Extension

_Part of the Stash Decision Log. See [`DECISIONS.md`](../DECISIONS.md) for the index and the full list of topical files. Entries are in original chronological order within this file._

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

---

## "Read Later" on the CLI and browser extension

StashKit already carried full plumbing for a new boolean field (the same
shape as `isArchived`'s `Bool?` on both request bodies), so `isReadLater`
only needed a `BookmarkListQuery.readLaterTag` sentinel constant added
alongside `untaggedTag`/`todayTag`/`thisWeekTag`.

**CLI:** got full symmetric support, deliberately going further than
`archive` (which is add-only via a dedicated `stash archive` subcommand,
with no `unarchive`): `stash add --read-later` marks a bookmark at creation,
`stash read-later <id>` / `stash mark-read <id>` are a matched pair of
subcommands (with top-level aliases, same convention as `archive`), and
`stash list --read-later` filters to the "To Read" view by mapping onto the
`__read_later__` tag sentinel; rejected as a usage error if combined with
an explicit `--tag`, since both occupy the same underlying query slot. The
asymmetry with `archive` is deliberate: this feature's ask was explicitly
two-directional ("mark to read later" / "mark as read") from the start,
where archiving has so far only ever needed the one direction from the CLI.
The CLI's own hand-rolled Stash-JSON import/export mirror
(`ImportParser`/`ExportDocument`, duplicated from the backend importer since
the import endpoint is web-only) picked up the field the same way it
already carries `isArchived`.

**Browser extension:** a "Read later" checkbox in the popup's add-bookmark
form (next to Tags, unchecked by default), read into the `POST
/api/v1/bookmarks` body as `isReadLater`. The extension remains add-only (no
edit UI), so, same as `isArchived`, there's no way to toggle it on an
already-saved bookmark from the popup itself.
