# Stash — Decision Log

A running record of the **technical and design decisions** made while building
Stash, complementing the requirements in [`PRODUCT.md`](./PRODUCT.md). Where
`PRODUCT.md` says *what* to build, this document records *how* it was built and
*why* — especially the choices that aren't obvious from the code, the deviations
from the PRD, and the trade-offs accepted.

### How to maintain this document

- Update it whenever a milestone or a meaningful chunk of work is completed.
- Add new entries under the relevant milestone heading (create a new heading for
  new milestones).
- Keep entries short: **what was decided**, **why**, and the **trade-off or
  alternative** when one mattered. Reference PRD sections as `§n`.
- Prefer appending over rewriting history — a decision that was later reversed
  should be marked *Superseded* rather than deleted, with a pointer to what
  replaced it.
- This is a decision log, not API docs. Endpoint/behaviour reference lives in
  `Docs/api.md`.

### Status legend

✅ In effect · ⚠️ Deviation from `PRODUCT.md` · 🔁 Superseded

---

## Cross-cutting conventions

- **✅ Error envelope via custom middleware.** A `StashErrorMiddleware` replaces
  Vapor's default error middleware so *every* API error — including routing 404s
  and validation failures — serialises to the standard `{ error, code, message
  }` envelope (§17.4). Strongly-typed `APIError` cases own the
  status/code/message mapping; the duplicate-URL case carries an extra
  `existingID`.
- **✅ Testing stack.** `VaporTesting` + swift-testing, running against an
  in-memory **SQLite** database (§17.7), not Postgres — fast and isolated.
  Production uses Postgres; the only schema concession is that array/JSON
  columns map differently per driver (see M2).
- **✅ Leaf templates are not unit-tested** (§17.7). Instead, each web chunk is
  verified with a throwaway end-to-end smoke test (login → action → assert) that
  is **run and then removed**, since Leaf errors only surface at render time and
  the existing suite can't catch them.
- **⚠️ `fluent-sqlite-driver` added** (not in the §17.2 dependency table)
  because §17.7 mandates an in-memory SQLite test database. Postgres remains the
  production driver.

---

## M1 — Auth foundation

- **⚠️ TOTP implemented natively, not via `vapor/auth`.** §17.2 lists
  `vapor/auth.git` `from 2.0.0` for "built-in RFC-compliant TOTP". That package
  is the **Vapor 3-era** auth package; it does not exist for / compile against
  Vapor 4 (where `Authenticatable` lives in Vapor core and there is no bundled
  TOTP). RFC 6238 TOTP + Base32 are therefore implemented directly on top of
  `swift-crypto` (already a transitive dependency) in `Sources/App/Auth/`. Keeps
  the backend dependency-light, in line with the project's data-ownership
  philosophy. Every other §17.2 dependency is used as listed.
- **✅ Token strategy.** Access token = HS256 JWT, 15 min, carries a `scope`
  claim (`access`). The 2FA step uses a separate 5-min JWT with `scope = "2fa"`
  so a temp token can never be replayed as an access token. Refresh token =
  opaque 256-bit hex, stored only as a SHA-256 hash, 90-day expiry, **rotated**
  on every use (§8.1).
- **✅ bcrypt cost 12** (Vapor's default) for passwords and recovery codes
  (§8.5). Recovery codes are 8 × `XXXX-XXXX`, normalised (dash-free, uppercased)
  before hashing/verifying.
- **✅ Constant-time-ish login.** Unknown usernames still run a throwaway bcrypt
  verify so response timing doesn't leak account existence.
- **✅ `withTestApp`, not `withApp`.** The test boot helper is named distinctly
  on purpose: VaporTesting exports a generic `withApp`, and a single-expression
  test closure (e.g. just a `.test(...)` call) would infer a non-`Void` return
  and silently resolve to VaporTesting's overload, skipping our explicit
  `asyncBoot()` and leaving the responder unbooted — every route then 404s. Cost
  ~an hour to diagnose; the rename prevents recurrence.

---

## M2 — Bookmarks

- **✅ Tags stored twice for portable querying.** The canonical `tags` is a
  `[String]` field (`.array` → a `JSON` column, which works on both SQLite and
  Postgres). Hierarchical **prefix matching** (`tag=swift` matches `swift` and
  `swift/*`, §7.5) can't be done portably against an array/JSON column, so a
  derived `tags_search` text column holds a pipe-wrapped form
  (`|swift|swift/vapor|`) and the filter is two portable `LIKE` (`~~`) clauses.
  Single source of truth (`tags`); `tags_search` is kept in sync via
  `applyTags`.
- **⚠️ Tags normalised on write** — trimmed, lowercased, surrounding slashes
  stripped, `|` removed, de-duplicated. Lowercasing isn't explicit in the PRD,
  but every example is lowercase and it prevents a fragmented tag tree (`Swift`
  vs `swift`).
- **✅ Duplicate URL → 409 with `existingID`.** Enforced by a pre-check *and* a
  unique `(user_id, url)` index as a race backstop; the error envelope includes
  the existing bookmark's id (§9.3/§17.4).
- **✅ Metadata fetching is dependency-free and non-blocking.** `MetadataFetcher`
  uses Vapor's built-in HTTP client (5 s timeout, no retry, §10) and a small
  regex HTML parser — no scraping library. Fetching runs inline server-side (no
  internal HTTP round-trip). On any failure the save proceeds with whatever the
  client supplied; client-supplied title/description always win over fetched
  values. Title falls back to the URL when otherwise blank.
- **🔁 Full-text `q` used `LIKE` (`~~`)** across URL, title, description, and
  tags (the latter via the existing `tags_search` column). Behaviour was
  **case-insensitive on SQLite, case-sensitive on Postgres** — originally left
  as a documented nuance. *Superseded during M8* once a real client exercised
  it: §9.3 actually mandates case-insensitive search ("ILIKE on PostgreSQL"), so
  this is now case-insensitive on both drivers — see the M8 search fix below.
  (Tags in `q` go beyond the PRD's "URL, title, description" — added on request;
  same change applied to both the API and web list handlers so they stay
  consistent.)
- **✅ `bookmarkCount` is a denormalised counter** on `User`, maintained on
  create/delete (§7.1); the `makeBookmark` test helper maintains it too so it
  reflects reality in tests.
- **✅ Pagination** uses Vapor's `Page<T>` (§17.5); `per` is clamped to 1–100.

---

## M3 — Admin API

- **✅ Admin role enforced by middleware.** `AdminMiddleware` is layered after
  the access-token authenticator + guard; authenticated non-admins get `403
  forbidden` in the standard envelope.
- **⚠️ `username_taken` (409).** §17.4's code table has no username-conflict
  code, so one was added (mirrors the `duplicate_url` pattern).
- **✅ Accounts are always created as `user`.** Any `role` field in the create
  body is ignored; admin accounts exist only via first-boot seeding (§4).
  (Tightened from an earlier version that accepted `role` — see M3 correction.)
- **✅ Self-deletion blocked** with `400 cannot_delete_self`.
- **✅ Self-suspension blocked** with `400 cannot_suspend_self`, mirroring
  self-deletion — an admin must not lock themselves out. Enforced on both the
  JSON API (`PUT /admin/users/:id` with `isActive: false` on one's own id) and
  the web dashboard (`POST /admin/users/:id/suspend`); the web "Suspend account"
  button is hidden for the signed-in admin's own detail page (same `isSelf` flag
  that hides Delete).
- **✅ Suspension *and* password reset both revoke refresh tokens** (§8.6) — any
  change to an account's security state forces re-authentication.
- **✅ Hard delete cascades explicitly** (bookmarks → refresh tokens → recovery
  codes → user) rather than relying on FK `ON DELETE CASCADE`, so it behaves
  identically on SQLite (tests) and Postgres regardless of FK enforcement.
- **✅ Per-user counts use the denormalised `bookmarkCount`** (same source as
  `/me`), keeping stats cheap and consistent.

---

## M4 — Docker & deployment

- **✅ Multi-stage image, jammy-matched.** Build stage `swift:*-jammy` → runtime
  `ubuntu:22.04`, so the build glibc/ABI matches the runtime. Static Swift
  stdlib + jemalloc; runtime carries only the binary and required libs.
  Arch-agnostic, so `buildx` produces `linux/amd64` + `linux/arm64`. (Build base
  started at `swift:5.10-jammy`; later bumped to `swift:6.1-jammy`.)
- **✅ First-boot admin seeding in `configure.swift`** (`AdminSeeder`, after
  migrations): seeds the admin from `ADMIN_USERNAME`/`ADMIN_PASSWORD` only when
  the DB has no users; **throws and exits** on missing/invalid credentials
  (don't start a login-less instance); no-op once any user exists; never runs
  against the test DB.
- **✅ Migrations auto-run on boot** (all environments) so the canonical `docker
  compose up -d` works with zero manual steps; Fluent records applied
  migrations, so it's idempotent.
- **✅ `.env.example` is Docker-oriented** — the four §16 variables
  (`DB_PASSWORD`, `JWT_SECRET`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`); compose
  interpolates `DATABASE_URL` from `DB_PASSWORD`. Local non-Docker runs export
  `DATABASE_URL` directly.

---

## M5 — Web admin dashboard

- **✅ Session-cookie auth, separate from the JWT API** (§11). Cookie
  `stash_admin_session`, backed by an **in-memory** session store (fine for a
  single self-hosted instance — sessions just don't survive a restart). Entirely
  independent of `/api/v1/*`.
- **✅ Custom session payload over `ModelSessionAuthenticatable`.** The admin's
  user id is stored as a string in the session and reloaded by
  `AdminSessionMiddleware`, avoiding uncertainty around `UUID:
  LosslessStringConvertible`. The middleware redirects to `/admin/login` on any
  failure (missing/expired/suspended/demoted) instead of returning a JSON error,
  and `req.auth.login`s the user so handlers use `req.auth.require`.
- **✅ POST-only actions + PRG.** HTML forms can't issue PUT/DELETE, so
  suspend/reset/delete are `POST` sub-routes; success uses Post/Redirect/Get
  with `?ok=` confirmation banners. Web handlers render error states or redirect
  rather than throwing (which would emit the JSON envelope).
- **✅ Render-with-status helper.** Responses with a non-200 status are built
  from `view.data` directly; the async `View.encodeResponse` overload didn't
  resolve cleanly, and `req.view.render` needs an explicit `let view: View = …`
  annotation to pick the async overload.

---

## M6 — StashKit (shared Swift package)

- **✅ Three-layer split: DTOs, request factories, thin client.** StashKit
  mirrors the `MicroblogAPI` pattern on top of `MicroClient` (`from: "0.0.27"`).
  The package has exactly three concerns and no more: `Codable`/`Sendable`
  **DTOs** matching the API response shapes, **request factories** that return
  typed `NetworkRequest<RequestModel, ResponseModel>` values, and a thin
  **`StashClient`** wrapping `MicroClient.NetworkClient`. Swift tools 6.0;
  platforms iOS 17 / macOS 14.
- **✅ One factory enum per API domain, all `public static` methods.**
  `AuthRequestFactory`, `BookmarkRequestFactory`, `TagRequestFactory`,
  `MetadataRequestFactory`, and `AdminRequestFactory` each own the requests for
  one domain. Every path is prefixed `/api/v1/`. Factories are pure value
  builders — they construct a `NetworkRequest` and nothing else (no I/O), so
  they're trivially testable by inspecting the returned request's
  `path`/`method`/`queryItems`/`body`.
- **✅ DTOs only; domain mapping deferred to the app's repository layer.**
  StashKit decodes the wire shapes into DTOs (`BookmarkDTO`, `TagDTO`,
  `UserDTO`, `TokenPairDTO`, …) and stops there. Mapping DTOs to domain models
  is the repository layer's job in the app (M8+); the package contains no
  business logic and no domain types. `BookmarkPageDTO` is a `typealias` over a
  generic `PageDTO<T>` matching Vapor's `Page<T>` envelope (`items` + `metadata
  { page, per, total }`).
- **✅ `StashClient` is genuinely thin: configure, run, map errors.** It owns the
  `NetworkConfiguration` (base URL + a single `BearerAuthorizationInterceptor`)
  and exposes one `run(_:)` that delegates to `NetworkClient`. It does **no**
  token storage, **no** silent refresh, and **no** business logic —
  refresh-on-401 is the repository layer's responsibility (PRD §8.1). Its only
  value-add over `NetworkClient` is error mapping.
- **✅ `tokenProvider` closure keeps the package storage-agnostic.** The public
  initializer takes `tokenProvider: @escaping @Sendable () async -> String?`;
  the app supplies the current access token from wherever it lives (Keychain in
  M8, in-memory in tests). StashKit defines **no** `TokenStore` protocol and
  never touches the Keychain — storage is entirely the app's concern. A second
  internal initializer accepts a `URLSessionProtocol` so tests inject a mock
  session.
- **✅ Error mapping `NetworkClientError → StashAPIError` lives in
  `StashClient.run`.** On a non-2xx response
  (`NetworkClientError.unacceptableStatusCode`), the client decodes the standard
  `{ error, code, message, existingID? }` envelope into `APIErrorDTO` and
  switches on `code` to a typed `StashAPIError` case (e.g. `duplicate_url` +
  `existingID` → `.duplicateURL(existingID:)`, `internal_error`/any 5xx →
  `.serverError`). Undecodable bodies and unrecognized codes fall back to
  `.serverError` (5xx) or `.unknown(error)`. The `cannot_delete_self` backend
  code has no dedicated `StashAPIError` case (it's a UI-level guard) and maps to
  `.unknown`.
- **✅ `.iso8601` date strategy matches the backend.** Vapor's default
  `ContentConfiguration` uses `JSONEncoder/Decoder.custom(dates: .iso8601)`, so
  `StashClient` configures its decoder/encoder with `.iso8601` (no fractional
  seconds) to round-trip `createdAt`/`updatedAt` correctly. Verified against
  Vapor's source rather than assumed.
- **⚠️ Hierarchical tag deletion is limited by `MicroClient`'s path model.**
  `MicroClient` builds URLs via `URL.appendPathComponent`, which (a) treats `/`
  as a separator and (b) re-encodes a literal `%` (so a pre-encoded `%2F`
  becomes `%252F`). A single path segment therefore cannot carry an encoded
  slash. `TagRequestFactory.makeDeleteRequest(tag:)` passes the raw tag and lets
  `appendPathComponent` percent-encode it — correct for flat tags and for
  deleting a parent subtree (`swift` removes `swift` and `swift/*`), but it
  cannot target a specific hierarchical child like `swift/vapor` over this
  dependency. Accepted for now; revisit if child-specific deletion is needed
  from a client.
- **⚠️ `auth/totp/disable` and `admin/users/:id/reset-totp` factories precede
  their JSON API.** These endpoints currently exist only on the web controllers
  (M11 / post-M11); the JSON API hasn't added them yet. StashKit defines
  `makeTOTPDisableRequest`/`makeResetTOTPRequest` at the PRD §9.2/§9.6 paths now
  (the task's factory list mandates them) so the client is ready when the
  backend exposes them.
- **✅ Tests: mock `URLSession`, Given/When/Then, "It should …".**
  `StashKitTests` injects a `MockURLSession` (conforming to
  `MicroClient.URLSessionProtocol`) that records the last request and replays a
  canned status + body. Coverage: `BookmarkListQuery` → query items incl. the
  `__untagged__` sentinel; auth/bookmark factory paths, methods, and body
  encoding; and `StashClient.run` for success decoding, the `duplicate_url` →
  `.duplicateURL(existingID:)` mapping, and every enumerated error code → its
  `StashAPIError` case (parameterized test). 13 tests pass.
- **⚠️ Depends on `MicroClient`, not "Foundation + URLSession only" (§15).** §15
  specifies StashKit has no external dependencies. M6 instead builds on
  `MicroClient` (the typed `NetworkRequest` / `NetworkClient` / interceptor
  stack, mirroring `MicroblogAPI`), which is the agreed architecture for this
  milestone. `MicroClient` is itself Foundation/`URLSession`-only, so the
  data-ownership spirit holds.
- **⚠️ The §15 in-memory tag cache (`autocompleteTags(prefix:)`) is not in
  StashKit.** That cache is a stateful, session-scoped concern that belongs to
  the app's repository layer (which also owns refresh and storage), not the
  stateless request/DTO package. `TagRequestFactory.makeListRequest()` provides
  the data; caching/invalidation is layered on top in the app.
- **✅ Lint/format config copied from `Backend`.** The same `.swiftformat` and
  `.swiftlint.yml` (MIT header, type-mode organization, the
  Fluent-false-positive rule exclusions, idiomatic short-name allowances) apply
  to StashKit. `swiftformat --lint` is idempotent and `swiftlint lint` reports 0
  violations.

---

## M7 — CLI (`stash`)

- **✅ `ArgumentParser` + StashKit, one type per command.** The CLI (`CLI/`,
  executable target `stash`, Swift tools 6.0, macOS 14+) is built on
  `swift-argument-parser` (`from: "1.5.0"`) and the local `StashKit` package
  (§14/§17.2). Every command is its own `AsyncParsableCommand`; related commands
  are grouped under a parent (`config`, `bookmarks`, `tags`, `admin`) with
  shared business logic kept in `StashKit`'s request factories — the CLI is
  purely a presentation/orchestration layer.
- **✅ Top-level aliases via multi-parenting.**
  `BookmarksList`/`Add`/`Get`/`Delete`/`Archive` are listed both under the
  `bookmarks` parent *and* directly under the root command, so `stash list` and
  `stash bookmarks list` resolve to the same type (ArgumentParser keys commands
  by their static `commandName`, so a type can appear in two `subcommands`
  arrays). `stash tags` and `stash bookmarks` use `defaultSubcommand: …List` so
  the bare group lists.
- **✅ Config + token store in one file.** `ConfigStore` reads/writes
  `~/.config/stash/config.json` (`CLIConfig { baseURL, accessToken, refreshToken
  }`, all optional). A missing file loads as an empty config so first-run
  commands fail with a clear "not configured / not logged in" message rather
  than crashing. `CLIConfig` declares an explicit `init(… = nil)` because the
  shared `.swiftformat` `--nil-init remove` strips property `= nil` defaults,
  which would otherwise break the no-arg `CLIConfig()`.
- **✅ Proactive JWT refresh, dependency-free.** Before any authenticated
  command, `CLIRuntime` decodes the access token's `exp` claim by hand
  (base64url-decode of the JWT payload — no library, §8.1) and, when it is
  within 60 s of expiry *and* a refresh token exists, calls
  `AuthRequestFactory.makeRefreshRequest`, persisting the rotated pair. A failed
  refresh clears both tokens and surfaces "Session expired — please run stash
  login". A token that can't be parsed is treated as expiring; with no refresh
  token present the command proceeds and lets the server reject it (so manually
  `set-token`'d access tokens still work for scripting).
- **⚠️ Login builds its own request to cover the 2FA branch.** `POST
  /api/v1/auth/login` returns *either* a token pair *or* a `{ requires2FA,
  tempToken }` challenge, both as HTTP 200. StashKit's `makeLoginRequest` is
  typed to `TokenPairDTO` and can't represent the challenge, so the CLI declares
  a local `LoginOutcome` decoding both shapes and builds the `NetworkRequest`
  directly. This is why the CLI depends on **`MicroClient`** explicitly
  (re-declaring StashKit's transitive dependency) in addition to StashKit and
  ArgumentParser — the only deviation from the §14 dependency list.
- **✅ Import/export re-implemented client-side over the public API.** The import
  endpoint is web-only (§13), so `stash import` parses the file locally
  (`ImportParser` re-implements the Anybox `[[namespace, value]]`-tag mapping
  and the Stash-JSON shape, with URL/tag normalization mirrored from `Bookmark`
  in `BookmarkInput`) and submits each record through
  `BookmarkRequestFactory.makeCreateRequest`, falling back to
  `makeUpdateRequest` when the server reports `duplicate_url` (carrying the
  `existingID`). `stash export` paginates through *both* active and archived
  bookmarks (the list API splits on `archived`, so both must be fetched),
  assembles the native `{ version, exportedAt, bookmarks[] }` envelope sorted by
  `createdAt`, and writes it.
- **⚠️ Import can't preserve `createdAt` or set archived-on-create.** The public
  create endpoint has no `createdAt` field and `CreateBookmarkRequest` no
  `isArchived`, so CLI-imported bookmarks get a fresh `createdAt` and an
  archived record is created then updated to set the flag. The web importer,
  which has direct DB access, preserves `createdAt`; this is an accepted
  limitation of importing over the REST API. (Re-importing a Stash export of
  existing bookmarks takes the duplicate-update path, where the server preserves
  `createdAt` — verified idempotent against a 212-bookmark export.)
- **✅ Output: stdout for results, stderr for everything interactive.** Tables
  (plain `String(repeating:)` padding — ID 8 / title 40 / URL 50, no table
  library), `--json` (pretty-printed, `.iso8601`, `.withoutEscapingSlashes`),
  and success lines go to stdout; prompts, the `Delete …? [y/N]` confirmations,
  and `Error: <message>` go to stderr, with a non-zero exit on failure (a shared
  `runCLI` wrapper maps `StashAPIError`/`CLIError` to a single-line message and
  exits 1). Hidden password entry uses `getpass` (reads `/dev/tty`).
  `NetworkClientError` is mapped to actionable text too — a bare
  `MicroClient.NetworkClientError error 0` told a user nothing when they pointed
  the CLI at `https://` against a plain-HTTP server (a TLS handshake failure),
  so transport/URL/decoding failures now read as e.g. "Could not reach the
  server. A TLS error caused the secure connection to fail. (Check the URL and
  scheme — a plain HTTP server needs http://, not https://.)".
- **✅ Admin commands resolve usernames to IDs.** The admin API is keyed by UUID
  but the CLI takes usernames (§14), so
  `suspend`/`unsuspend`/`reset-password`/`reset-totp`/`delete-user` first list
  users (`makeUsersRequest`) and match case-insensitively. Suspend/unsuspend and
  reset-password are `makeUpdateUserRequest` with `isActive`/`password`.
- **🔁 Fixed a latent StashKit defect: writes sent no `Content-Type`.**
  `StashClient` configured only a `BearerAuthorizationInterceptor`, so POST/PUT
  requests carried a JSON body with no `Content-Type` header and Vapor rejected
  every write with `400 bad_request` ("No value found at path 'url'").
  StashKit's mock-based tests never exercised a real header, so the bug was
  invisible until the CLI made live write calls. Added `ContentTypeInterceptor`
  and `AcceptHeaderInterceptor` to `StashClient`'s interceptor chain (a one-line
  config fix that also benefits the future iOS/macOS clients). Verified
  end-to-end against the running backend: create, duplicate-detection,
  update-on-import, archive, tag rename/delete, and the full admin user
  lifecycle.
- **⚠️ `admin reset-totp` 404s until the JSON API adds the route.** As noted
  under M6, the `/api/v1/admin/users/:id/reset-totp` endpoint exists only on the
  web controller so far; the CLI calls the documented path and surfaces the
  server's `404 not_found`. The command is correct and will work once the
  backend exposes the route.
- **✅ No CLI tests (§18.7) — manual integration only.** Build is clean,
  `swiftformat --lint` is idempotent, and `swiftlint lint` reports 0 violations.
  The `.swiftformat`/`.swiftlint.yml` are copied from `Backend/`. All commands
  were exercised against a live backend instance.

---

## M8 — iOS app (core)

Scope for this milestone is a working app — authentication, bookmark list, add
bookmark. The Share Extension (M9), full settings, tag rename/delete, and
edit/delete screens are deliberately deferred.

- **✅ Project generated with XcodeGen, not a checked-in `.xcodeproj`.**
  `StashApp/project.yml` is the source of truth; `xcodegen generate` recreates
  the project, which is `.gitignore`d (mirrors how the package targets avoid
  committing build artifacts). Single multiplatform SwiftUI target `Stash`, iOS
  17 minimum, bundle id `cc.otavio.stash`, App Group `group.cc.otavio.stash`,
  `TARGETED_DEVICE_FAMILY` `1,2` (iPhone + iPad).
  `NSAppTransportSecurity.NSAllowsArbitraryLoads` is set via the generated
  `Info.plist` for plain-HTTP local-network deployments (§16). macOS is added in
  M10, so the target is iOS-only for now (`UIPasteboard` is used directly in the
  add sheet; revisit for macOS).
- **✅ `KeychainStore` vendored from Triton, extended with an access group.**
  Copied verbatim and adapted: a new optional `accessGroup: String?` init
  parameter (default `nil`) adds `kSecAttrAccessGroup` to every query so the
  item can be shared with the Share Extension over the App Group in M9. The two
  token stores (`cc.otavio.stash.accessToken` / `…refreshToken`) are created
  with the default (no access group) so M8 works standalone without a
  `keychain-access-groups` entitlement; M9 will pass `group.cc.otavio.stash`.
  The Security calls (`SecItemDelete`/`Add`/`CopyMatching`) are injected
  closures, keeping the store testable; the class is `@unchecked Sendable`
  (immutable after init, manual safety). Reads via `SecItemCopyMatching`, writes
  via delete-then-add, `nil` deletes.
- **⚠️ Both tokens stored in the Keychain, not access-token-in-memory.**
  §16/§8.1 say the access token lives in memory only. This milestone's task
  mandates two `KeychainStore` instances (access + refresh), so both are
  persisted. This is what lets the M9 Share Extension reuse the access token
  directly, and it means a cold start restores the session without an immediate
  refresh round-trip. Noted as a deliberate deviation from the PRD's memory-only
  access token.
- **✅ `TokenManager` decodes the JWT `exp` by hand — no library.**
  `isAccessTokenExpiringSoon()` base64url-decodes the access token's payload
  segment and reads the `exp` claim (`< 60 s` → expiring), the same
  dependency-free approach as the CLI's `JWTDecoder` (M7). A token that is
  absent or unparseable is treated as expiring, so the caller refreshes rather
  than sending a request that would be rejected.
- **✅ Repository pattern maps StashKit DTOs to local domain models.**
  `AuthRepository`, `BookmarkRepository`, `TagRepository` are `@MainActor
  @Observable` classes; views observe them directly. StashKit stops at DTOs (M6
  decision), so the repositories own the `BookmarkDTO → Bookmark`, `TagDTO →
  Tag`, `PageMetadataDTO → PageMetadata` mapping and all session-stateful
  concerns. The §15 in-memory tag cache (deferred out of StashKit in M6) lives
  here: `TagRepository` caches the tag list for synchronous, local
  `autocompleteTags(prefix:)` and exposes `invalidateCache()` after a bookmark
  write that may change tags.
- **✅ Silent refresh centralised in `AuthRepository`, behind a narrow
  protocol.** Per §8.1, an authenticated operation first calls
  `refreshIfNeeded()`: if the token is expiring and a refresh token exists it
  rotates the pair via `AuthRequestFactory.makeRefreshRequest` and re-saves; on
  failure it clears the session (returning the UI to login) and rethrows. The
  bookmark/tag repositories depend on a one-method `SessionRefreshing` protocol
  rather than the concrete `AuthRepository`, so they can ensure a fresh token
  without owning auth state and without a reference cycle.
- **✅ `StashClientProvider` rebuilds the client only when the server URL
  changes.** The server URL is read from the same `serverURL` UserDefaults key
  that `AppSettings` (`@AppStorage`) persists, so the provider always reflects
  the latest configuration without holding the observable. The client's
  `tokenProvider` closure reads the access token from `TokenManager` at request
  time, so a refresh that rewrites the Keychain is picked up without rebuilding
  the client. `@unchecked Sendable` with an `NSLock` around the cache.
- **⚠️ App depends on `MicroClient` directly for the 2FA login branch.** `POST
  /api/v1/auth/login` returns *either* a token pair *or* a `{ requires2FA,
  tempToken }` challenge, both as HTTP 200, and StashKit's typed
  `makeLoginRequest` is `TokenPairDTO`-only. As the CLI does (M7),
  `AuthRepository` declares a local `LoginOutcome` decoding both shapes and
  builds the `NetworkRequest` directly — hence a direct `MicroClient` dependency
  in addition to StashKit.
- **✅ `AppEnvironment` is the DI container.** A single `@MainActor @Observable`
  `AppEnvironment` builds the token stores, `TokenManager`,
  `StashClientProvider`, and the three repositories once at launch; it and
  `AppSettings` are injected via `.environment(_:)`. `RootView` routes on
  `AppSettings.isConfigured` → `AuthRepository.isAuthenticated`: setup → login →
  main app.
- **✅ `NavigationSplitView` on iPad, tab bar on iPhone.** `MainView` switches on
  `horizontalSizeClass`: regular width shows a `NavigationSplitView` with a tag
  sidebar driving the filtered `BookmarkListView` in the detail column; compact
  width shows `TabContainerView` (Bookmarks / Tags / Settings tabs, each in its
  own `NavigationStack`). `BookmarkListView` takes an optional `tag` filter so
  the same screen serves both layouts and the Tags tab's drill-in.
- **✅ `FaviconView` vendored from Triton with a local `roundedFavicon()`
  modifier.** Copied verbatim, `public` modifiers dropped for the app target;
  the `RoundFaviconModifier` (16×16, 4 pt corner radius) is implemented locally
  as instructed.
- **✅ Bookmark list: `.searchable`, pull-to-refresh, load-more, archived
  toggle.** Search reloads on submit (and on clear) rather than per keystroke;
  `loadNextPage()` fires from the last row's `onAppear` when `hasMore`; the
  toolbar carries a `+` (presents `AddBookmarkSheet`) and an options menu with
  the archived `Toggle`. `AddBookmarkSheet` has a paste button, a metadata fetch
  that populates title/description, comma-separated tag input with
  `TagSuggestionView` autocomplete chips, and surfaces duplicate-URL/validation
  errors inline via the shared error mapping.
- **✅ Error mapping for the UI.** A single `Error.stashUserMessage` maps
  `StashAPIError` (and the app's own `AppError`) to short, user-facing strings
  shown inline or in an alert.
- **✅ Code style and verification.** American English, `///` on types only, no
  inline comments; `.swiftformat`/`.swiftlint.yml` copied from `Backend/`.
  `swiftformat --lint` is idempotent and `swiftlint lint` reports 0 violations;
  the app builds clean (no warnings) for the iOS 17 simulator and boots through
  Setup → Login (routing verified live against the running Docker backend). No
  app unit tests per §18.7 — the StashKit networking path is already covered by
  M6's mocked tests and proven end-to-end by the M7 CLI against the same
  backend.

### M8 follow-ups (first device testing)

- **🔁 `AppSettings.serverURL` is a tracked property, not `@ObservationIgnored
  @AppStorage`.** The original spec'd `@ObservationIgnored
  @AppStorage("serverURL")` is excluded from `@Observable` tracking, so setting
  it from `SetupView` persisted the value but never notified `RootView` — the
  app appeared stuck on Setup ("Continue does nothing"). It only routed
  correctly when the value was already present at launch. Replaced with a plain
  tracked `var serverURL` whose `didSet` writes through to the same `serverURL`
  UserDefaults key (still read by `StashClientProvider`), so the change is
  observed and routing is reactive while persistence and the key are unchanged.
- **✅ Per-view `BookmarkRepository`, not one shared instance.** `AppEnvironment`
  originally held a single `bookmarkRepository`, so the Bookmarks tab, a
  Tags-tab tag drill-in, and the iPad detail all mutated the same `bookmarks`
  array — browsing a tag in the Tags tab left the Bookmarks tab showing that
  tag's results. `AppEnvironment` now exposes `makeBookmarkRepository()`
  (sharing the client and session) instead, and `BookmarkListView` is a thin
  wrapper owning its own repository in `@State` (created lazily on first
  appearance), rendering a private `BookmarkListContent` bound to it. Each list
  is therefore independent. `AuthRepository` and `TagRepository` stay shared
  singletons (auth state and the tag cache are intentionally global);
  `AddBookmarkSheet` receives the presenting list's repository so a saved
  bookmark lands in that list.
- **✅ Bookmark navigation is closure-based, not `navigationDestination(for:)`.**
  `BookmarkListView` declared `.navigationDestination(for: Bookmark.self)`
  *inside itself*, but it is reused at multiple stack depths (root of the
  Bookmarks tab, pushed under the Tags tab, iPad detail column). A pushed copy
  re-declared the same destination, so SwiftUI logged "a navigationDestination
  for Stash.Bookmark was declared earlier on the stack" and kept only the
  root-most one — tapping a bookmark in the Tags flow re-pushed the list instead
  of the detail, with the real detail buried (off-by-one back button). It also
  mixed value-based links (`NavigationLink(value:)`) with closure-based links
  (TagBrowserView's tag link) in one stack. Fixed by making the bookmark rows
  closure-based (`NavigationLink { BookmarkDetailView(…) }`) and removing the
  `navigationDestination` entirely: closure links resolve at any depth with no
  registration, so all bookmark navigation is now uniform. (`LoginView` keeps a
  single `navigationDestination(for: String.self)` for the 2FA push — correct,
  since it is declared once at the stack root.)
- **✅ Search field disables autocapitalization/autocorrection.** `.searchable`
  defaults to sentence-case, so typing `casio` became `Casio` and matched
  nothing (see the search fix below). `BookmarkListView` applies
  `.textInputAutocapitalization(.never)` + `.autocorrectionDisabled()` to the
  search field so the query is sent as typed.
- **✅ Case-insensitive `q` search (backend, supersedes the M2 nuance).** A real
  client surfaced that Postgres `LIKE` is case-sensitive while §9.3 wants
  case-insensitive ("ILIKE on PostgreSQL"). `LIKE`/`~~` would have needed a
  Postgres-only `ILIKE`, which isn't portable to the SQLite test DB, so a shared
  `QueryBuilder<Bookmark>.filterFullText(_:)` (`Sources/App/Extensions/`)
  compares `lower(column) LIKE lower(term)` over
  url/title/description/tags_search via a bound `SQLBind` parameter (FluentSQL
  `.filter(.sql(...))`). Portable across both drivers, genuinely
  case-insensitive, and the bound term preserves the previous `~~` wildcard
  semantics. Both the JSON API (`BookmarkController`) and the web list
  (`AppWebController`) call the one helper so they can't drift. The existing
  search test gained uppercase-query/mixed-case-content assertions.

### M8 follow-ups (SwiftUI review)

Changes from reviewing the app with the SwiftUI-expert skill, against its
state-management, performance, view-composition, navigation, and list
references.

- **✅ Bookmark row tags are a truncating row, not a horizontal `ScrollView`.**
  Each list row had a nested `ScrollView(.horizontal)` of tag pills, adding a
  scroll container and gesture recognizer to every cell (heavy in a hot list,
  and it competes with the list's own scrolling). Replaced with a non-scrolling
  `HStack` showing the first three tags plus a `+N` overflow count. The detail
  screen keeps its scrolling tag row, since it should show all tags and isn't in
  a list.
- **✅ `AppSettings` is `@MainActor`.** The other `@Observable` types
  (`AppEnvironment`, the repositories) are already main-actor isolated;
  `AppSettings` now matches, for thread-safe use from SwiftUI.
- **✅ Context-aware empty state.** `BookmarkListView` showed "Tap + to save your
  first bookmark" even when a search or tag filter simply matched nothing,
  implying the user had zero bookmarks. It now branches:
  `ContentUnavailableView.search(text:)` for an active query, a tag-specific
  message when a tag filter is active, an archived-specific message for the
  archived view, and the original first-run copy only when truly empty.
- **✅ `PasteButton` instead of `UIPasteboard.general`.** The add-bookmark URL
  field used a custom button calling `UIPasteboard.general.string`, which trips
  the system paste-permission banner on every tap. Replaced with
  `PasteButton(payloadType: String.self)` (icon-only, circular), which the
  system enables only when the pasteboard holds text and which pastes without a
  permission prompt. Removes the `import UIKit` from the view.
- **✅ Typed login route.** `LoginView` drove its stack with `[String]` and
  `navigationDestination(for: String.self)`, using the raw temp token as the
  route. Replaced with a `LoginRoute` enum (`.twoFactor(tempToken:)`) for
  type-safe, self-documenting navigation.
- **⚠️ Considered but not changed.** Kept the computed `suggestions` in the add
  sheet (a `@State` cache keyed on the text would miss the async tag-load
  completing mid-typing, and the data is small). Left `AsyncImage` favicons
  as-is (URLCache covers downloads; an in-memory decode cache is a larger,
  optional change). Left the size-class swap between split view and tab bar (the
  iPhone tab IA differs from the iPad sidebar, so a single adaptive
  `NavigationSplitView` doesn't fit).

---

## M9 — iOS Share Extension

Scope: save a URL to Stash from Safari (or any app) via the system share sheet,
presenting the same add-bookmark UX as the app and confirming the save with an
undo option. No login flow inside the extension — the user authenticates in the
main app first.

- **✅ A `StashShareExtension` `app-extension` target
  (`cc.otavio.stash.ShareExtension`).** Added to the XcodeGen `project.yml`
  (still the single source of truth; `Stash.xcodeproj` stays gitignored). Its
  `NSExtension` Info.plist is `com.apple.share-services` with an activation rule
  of `NSExtensionActivationSupportsWebURLWithMaxCount: 1` (URLs only), principal
  class `$(PRODUCT_MODULE_NAME).ShareViewController`, iOS 17 minimum, the same
  `MicroClient` + local `StashKit` dependencies as the app, and
  `NSAllowsArbitraryLoads` for the same plain-HTTP local-network deployments
  (§16). The app target gains a `target: StashShareExtension` dependency so the
  `.appex` is embedded under `PlugIns/`.
- **✅ Shared sources extracted to `StashApp/Shared/`, a second source root on
  both targets.** What the extension genuinely needs — `KeychainStore`,
  `TokenManager`, `StashClientProvider`, the domain models
  (`Bookmark`/`Tag`/`PageMetadata`/`CreateBookmarkInput`), the error mapping
  (`AppError`/`ErrorMessage`), `TagSuggestionView`, and the new
  `AddBookmarkView` — moved out of `Stash/Shared/` into a top-level
  `StashApp/Shared/` listed in both targets' `sources`. App-only code
  (repositories, `AppEnvironment`, `RootView`/`LoginView`/etc.) stays under
  `Stash/`. No code is duplicated across the two binaries; each just compiles
  the shared files in.
- **✅ Tokens shared via a Keychain access group; the server URL via the App
  Group `UserDefaults` suite.** A single `AppGroup` enum owns the group
  identifier, the two token account keys, and the `serverURL` key. The app's
  `AppEnvironment` now builds its two `KeychainStore`s with `accessGroup:
  "group.cc.otavio.stash"` (the M8 placeholder for this, noted there, is now
  real), and the extension builds the *same two* stores with the same keys and
  group, so it reads the tokens the app wrote. The server URL was the other
  half: `AppSettings` wrote it to `UserDefaults.standard`, which a separate
  process can't see, so both `AppSettings` (write) and `StashClientProvider`
  (read) now use `AppGroup.sharedDefaults` (the group suite). ⚠️ Because the
  app's tokens now live in the access group, an existing M8 install (tokens
  stored with no group) will not find them after this change — the user signs in
  once more; this is the planned M8→M9 transition.
- **✅ The extension is process-isolated, with its own lightweight
  repositories.** It can't share the app's live `@Observable` repositories
  (different process), so it builds its own: `ExtensionBookmarkRepository`
  (create / fetch-metadata / delete only — no list or pagination) and
  `ExtensionTagRepository` (load once + local `autocompleteTags(prefix:)` — no
  cache invalidation, since the extension is short-lived). Both go through one
  `ExtensionSession`, which mirrors `AuthRepository.refreshIfNeeded()`: before
  each request it rotates the access token via
  `AuthRequestFactory.makeRefreshRequest` if it is expiring soon and writes the
  pair back to the shared Keychain. `ExtensionBookmarkRepository` is a plain
  class (the views need no observable state from it); `ExtensionTagRepository`
  is `@Observable` so the suggestion chips refresh when the tag list arrives.
- **✅ `AddBookmarkView` extracted as the shared form behind two narrow
  protocols.** The M8 `AddBookmarkSheet` was tied to
  `AppEnvironment`/`BookmarkRepository`. Its body moved into a shared
  `AddBookmarkView` that depends only on `BookmarkCreating`
  (`create`/`fetchMetadata`) and `TagAutocompleting`
  (`tags`/`load`/`autocompleteTags`); the app's `BookmarkRepository`/
  `TagRepository` and the extension's repositories all conform. The view reports
  results through `onSaved`/`onCancel` callbacks rather than dismissing itself,
  so each host decides what happens next. `AddBookmarkSheet` is now a thin
  wrapper (URL editable, paste + "Fetch Metadata" buttons, dismiss on save,
  invalidate the tag cache); the extension passes `isURLEditable: false` (URL
  comes from the share sheet, shown read-only) and `autoFetchOnAppear: true`
  (metadata fetched on load). Duplicate-URL still surfaces inline via the shared
  `stashUserMessage` ("This URL is already saved.") — same as the app.
- **✅ Three-state bootstrap UI driven by a `Phase` enum.** `ShareExtensionView`
  shows: a brief **loading** state (a `ProgressView` + "Stash") while it reads
  tokens and resolves the shared URL; a **signed-out** state
  (`ContentUnavailableView`, "Open Stash to sign in before saving bookmarks." +
  Cancel) when there's no configured server, no refresh token, or no URL could
  be extracted; and the **add** state (the shared `AddBookmarkView`). The URL is
  pulled from `extensionContext.inputItems` by `SharedItemLoader`, which prefers
  a `public.url` attachment and falls back to the first link found in a
  `public.plain-text` attachment (via `NSDataDetector`). It is
  `@MainActor`-isolated so the non-`Sendable` `NSExtensionItem`/`NSItemProvider`
  never cross an actor boundary — only the resolved `URL`/`String` is returned
  across the `loadItem` continuation.
- **✅ Confirmation + undo with a self-cancelling timer.** A save advances to a
  **confirmation** state ("Saved to Stash ✓" + the bookmark title) with an Undo
  button. The confirmation view's `.task` sleeps three seconds then calls
  `completeRequest(returningItems:)`; tapping Undo instead changes the phase
  back to the add form, which removes the confirmation view and cancels its task
  (so the auto-dismiss never fires), then issues `DELETE /api/v1/bookmarks/:id`
  for the just-saved bookmark. Cancel anywhere calls
  `cancelRequest(withError:)`. Returning to the add form after undo lets the
  user re-save with different tags or cancel.
- **✅ Entry point.** `ShareViewController` (the principal class) hosts
  `ShareExtensionView` in a `UIHostingController` pinned to its edges, handing
  it the `extensionContext`.
- **✅ Style and verification.** `Shared/` and the extension follow the same
  conventions (American English, `///` on types only, no inline comments, the
  shared `.swiftformat`/`.swiftlint.yml`). `swiftformat --lint` is idempotent,
  `swiftlint lint` reports 0 violations, and the app + embedded `.appex` build
  clean (no warnings) for the iOS 17 simulator. No unit tests per §19.6.

---

## M10 — macOS app (+ deployment-target bump to 26)

Scope: a native macOS app sharing the iOS source tree, plus a macOS Share
Extension; and a bump of both platform minimums to iOS 26 / macOS 26 (Liquid
Glass adopted automatically by building against the 26 SDKs).

- **✅ Deployment targets raised to iOS 26 / macOS 26.** `project.yml`,
  `StashKit/Package.swift` (`.iOS(.v26)`/`.macOS(.v26)`, tools 6.2), and
  `CLI/Package.swift` (`.macOS(.v26)`, tools 6.2) were bumped. The iPhone tab
  bar gained `.tabBarMinimizeBehavior(.onScrollDown)` so the floating Liquid
  Glass bar collapses on scroll. No explicit `.liquidGlass` calls — the look
  comes from the SDK. Verified: StashKit, CLI, the iOS app, and the macOS app +
  extension all build on the Swift 6.2 / macOS 26 toolchain.
- **✅ One `@main App` for both platforms; macOS adds scenes.** Rather than a
  second entry point, `StashApp` stays the single `@main` and branches its
  `body` with `#if os(macOS)`: macOS adds a `Settings` scene (⌘,),
  `windowResizability(.contentMinSize)` with a 800×500 minimum, and
  `SidebarCommands()`. `RootView` routes the authenticated state to `MainView`
  on iOS and `MacContentView` on macOS.
- **⚠️ macOS uses a two-column split that reuses `BookmarkListView`, not a
  bespoke inspector.** The brief sketched a three-column layout with an optional
  inspector. To honor "maximum code sharing with minimal `#if`",
  `MacContentView` is a `NavigationSplitView` whose sidebar (All Bookmarks,
  Untagged, then the tag list — flat, matching the iPad sidebar) drives the
  *same* shared `BookmarkListView` in the detail column inside a
  `NavigationStack`; selecting a bookmark pushes the shared `BookmarkDetailView`
  there, exactly as on iPad. The inspector panel (explicitly optional in the
  brief) was not built — it would have required a selection-driven variant of
  the shared list and more platform divergence for little gain. The
  system-provided sidebar toggle and the list's own toolbar (add, archived,
  refresh) cover the macOS toolbar requirements.
- **✅ Platform differences concentrated in `PlatformModifiers` + thin `#if`
  shells.** iOS-only text-field/title modifiers (`keyboardType`,
  `textContentType`, `textInputAutocapitalization`,
  `navigationBarTitleDisplayMode`) live behind cross-platform helpers
  (`urlFieldStyle`/`usernameFieldStyle`/`passwordFieldStyle`/`oneTimeCodeFieldStyle`/
  `lowercasedFieldStyle`/`uppercasedFieldStyle`/`inlineNavigationTitleStyle`/`searchInputStyle`)
  so the shared leaf views read as plain SwiftUI. SwiftUI has no cross-platform
  copy API, so a single `copyToPasteboard(_:)` free function is the one place
  `UIPasteboard`/`NSPasteboard` are touched. Whole-view `#if` guards are
  reserved for genuine platform shells: `MainView`/`TabContainerView` (iOS,
  size-class + tab bar) and
  `MacContentView`/`MacSettingsView`/`AccountSettingsView` (macOS).
  `BookmarkListView`'s one iOS-only toolbar placement (`.topBarLeading`) is
  selected via a computed `ToolbarItemPlacement` (`.automatic` on macOS).
- **✅ Shared edit / delete / archive, surfaced per platform.**
  `BookmarkRepository` gained `update`/`setArchived`/`delete`;
  `BookmarkDetailView` became read-write (edit sheet, archive,
  delete-with-confirmation) and is shared by the iOS push and the macOS detail
  column; `EditBookmarkView` (URL fixed, like the web edit form) is shared. A
  right-click/long-press context menu on each `BookmarkListView` row (Open in
  Browser, Copy URL, Archive/Unarchive, Delete) is also shared. Keyboard
  shortcuts wired: ⌘N (new), ⌘E (edit), ⌘R (refresh), ⌘⌫ (delete the open
  bookmark, with confirmation). ⌘F is left to the system search field rather
  than custom-bound.
- **✅ macOS `Settings` scene with three tabs.** General (server URL field + sign
  out), Account (change password with the 12-char rule; 2FA enrol via a QR +
  manual secret + verify → one-time recovery codes, or disable with a current
  code), and Appearance (Light / Dark / Auto). This drove StashKit additions —
  `ChangePasswordRequest` + `UserRequestFactory` (`/me`, `/me/password`) — and
  `AuthRepository` methods (`currentUser`, `changePassword`, `beginTOTPSetup`,
  `completeTOTPSetup`, `disableTOTP`) over the existing TOTP factories, plus
  `CurrentUser`/`TOTPSetup` models and a cross-platform `QRCodeView` (CoreImage
  `CIFilter.qrCodeGenerator`, available on both platforms).
- **✅ Appearance lives in `UserDefaults`, not a cookie.** The web frontend
  stores Light/Dark/Auto in a `stash_theme` cookie; the native clients have no
  browser, so `AppSettings.appearance` (`AppAppearance`) is a tracked property
  in standard `UserDefaults` (app-only — the extension never themes), applied
  app-wide via `.preferredColorScheme` at the scene root. `serverURL` stays in
  the App Group `UserDefaults` suite since the extension reads it.
- **✅ macOS Share Extension reuses the iOS extension's SwiftUI.**
  `StashMacShareExtension` (`cc.otavio.stash.macShareExtension`, app group,
  sandbox + network client) shares `ShareExtensionView`, `ExtensionSession`,
  `ExtensionBookmarkRepository`, `ExtensionTagRepository`, and
  `SharedItemLoader` verbatim — they are all SwiftUI/Foundation with no UIKit.
  Only the principal controller differs: the iOS `ShareViewController`
  (`UIViewController`/`UIHostingController`) is guarded `#if os(iOS)` and a new
  `MacShareViewController` (`NSViewController`/`NSHostingController`) is guarded
  `#if os(macOS)`, both living in the one `StashShareExtension/` source folder
  that both extension targets compile. Same three-state UI and
  confirmation-with-undo as M9.
- **✅ Style and verification.** American English, `///` on types only, no inline
  comments, the shared `.swiftformat`/`.swiftlint.yml`. `swiftformat --lint` is
  idempotent and `swiftlint lint` reports 0 violations; the iOS app, the macOS
  app, and both embedded `.appex` bundles build clean (no warnings). No unit
  tests per §19.6.

---

## M11 — User-facing web frontend

- **✅ Second session cookie, shared store.** The frontend uses its own
  `stash_session` cookie (path `/app`) via a dedicated
  `SessionsMiddleware`/`SessionsConfiguration`, distinct from the admin
  dashboard's cookie but sharing the same in-memory driver.
  `UserSessionMiddleware` admits any **active** account regardless of role;
  suspended accounts are rejected.
- **✅ Shared `layout.leaf`.** Both web sections reuse one base template + inline
  CSS. The `<title>` prefix is conditional (`Stash Admin` vs `Stash`); a side
  effect is the admin *login* tab title changed cosmetically — accepted as
  trivial.
- **✅ Two-button add flow, no JS.** "Fetch metadata" previews title/description
  via an inline server-side fetch; "Save" persists (auto-fetching any blank
  fields). Duplicate URL shows an inline error linking to the existing bookmark.
  The edit form intentionally **doesn't allow URL changes**, sidestepping
  duplicate-handling there.
- **⚠️ 2FA setup shows the otpauth URI + setup key, not a scannable QR image.**
  Server-side QR rendering would need a QR-encoding dependency (no CoreImage on
  Linux), which conflicts with the minimal-deps goal. Manual key entry is fully
  functional; a QR image can be added later if desired.
- **✅ Leaf gotchas codified.** `#if(count(x))` does **not** coerce an `Int` to
  `Bool` (count 0 read as truthy) — always write `#if(count(x) > 0)`. Inline
  conditionals require the colon: `#if(cond): … #endif`.

---

## Frontend improvements (post-M11)

- **✅ Self-service 2FA disable requires a current TOTP code**, not just a
  password — this proves the user still controls their authenticator before 2FA
  is turned off (`POST /app/settings/totp/disable`). On success it clears the
  secret/flag and deletes recovery codes.
- **✅ Admin 2FA reset also revokes refresh tokens.** `POST
  /admin/users/:id/reset-totp` clears the secret/flag and recovery codes *and*
  deletes the user's refresh tokens, since their session security level changed
  — forcing re-login. Self-reset is allowed (no confirmation code; admin action
  suffices).
- **✅ Tag autocomplete with zero new requests.** The user's existing tags are
  embedded as a JSON array in a `data-known-tags` attribute on the create/edit
  forms; a ~50-line dependency-free vanilla JS block in `layout.leaf` filters
  the comma-segment under the cursor and offers prefix matches (full
  hierarchical strings like `swift/vapor` included). The attribute is
  **single-quoted** so Leaf's HTML-escaping of the JSON quotes survives — the
  browser entity-decodes the attribute value before `JSON.parse`, avoiding the
  need for an unescaped-output Leaf tag.
- **✅ Tag autocomplete matches per hierarchy segment, not just the whole-string
  prefix.** The original filter (`t.indexOf(frag) === 0`) only matched when the
  typed fragment was a prefix of the *entire* tag, so `music` never surfaced
  `kind/music-gear`. The filter now splits each candidate on `/` and matches
  when **any segment** starts with the fragment (`t.split('/').some(seg =>
  seg.indexOf(frag) === 0)`), so a fragment finds nested tags whose later
  segment begins with it. This is deliberately segment-*prefix*, not free
  substring: `usic` still matches nothing, keeping suggestions aligned with the
  `/`-delimited hierarchy the rest of Stash is built on (the `tags_search`
  prefix filter). One-line change in `layout.leaf`; the edit form shares the
  same script and gets it for free.
- **✅ Add-bookmark form accepts a `?url=` prefill query parameter.**
  `GET /app/bookmarks/new?url=…` reads the `url` query param
  (`req.query[String.self, at: "url"]`, defaulting to `""`) and seeds the
  `AppNewBookmarkContext.url` field, which the template already binds via
  `value="#(url)"` (Leaf auto-escapes, so no attribute-injection risk). The page
  only *pre-populates* — it never auto-submits or auto-saves, so a crafted link
  cannot silently add bookmarks; the user still has to click "Save bookmark".
  This is the groundwork for a browser bookmarklet that opens Stash with the
  current page's URL ready to save.

---

## Import / Export

- **✅ Pluggable registry architecture.** `BookmarkImporter`/`BookmarkExporter`
  protocols expose static metadata (`identifier`, `displayName`,
  `fileExtension`, exporter `mimeType`) plus one instance method each. A
  singleton `ImportExportRegistry` holds the registered instances; the settings
  UI's selectors and the import/export routes are driven entirely off the
  registry, so a new format is added by conforming a type and adding one
  `register(...)` line in the registry's `init` — **no controller, route, or
  template changes**. The registry is `@unchecked Sendable`: registration
  happens once in `init` and it's immutable thereafter, so concurrent request
  reads are safe.
- **✅ Importer owns data consistency.** The importer takes only `(data, userID,
  db)` and is responsible for everything: per-record validation, duplicate
  handling, and bumping the denormalised `User.bookmarkCount` by the number of
  rows it created. Keeps the controller a thin orchestrator and the behaviour
  identical regardless of caller.
- **✅ Parse-failure vs bad-record split.** A file that can't be parsed at all
  throws `ImportError.invalidFormat` (controller re-renders settings with an
  inline error, no redirect). Individual bad records (missing/invalid URL, etc.)
  are **counted and described** in `ImportResult.skipped`/`.errors`, never
  thrown — surfaced in a collapsible `<details>` block.
- **✅ Preserving `createdAt` on import.** Fluent's `_create` calls
  `touchTimestamps(.create, .update)` unconditionally, so a pre-set `createdAt`
  is overwritten on insert. Anybox's `date_added` is therefore restored with a
  **follow-up `save`** (an update only touches `updatedAt`, leaving the re-set
  `createdAt` intact). Duplicate-URL updates never touch `createdAt` for the
  same reason.
- **⚠️ Anybox's real export shape differs from the PRD example**, discovered
  against an actual file. Corrected mapping: - **`tags` is `[[String]]`** —
  arrays of `[namespace, value]` pairs (e.g.
  `[["topic","music-gear"],["status","wishlist"]]`), not a flat `[String]`. Each
  pair is joined with `/` into a hierarchical Stash tag (`topic/music-gear`),
  then normalised — a natural fit for Stash's slash-hierarchy. A plain
  `[String]` is still accepted as a fallback. (The original decoder assumed
  `[String]` and threw `typeMismatch` → "doesn't look like an Anybox export".) -
  **`dateAdded`** (camelCase, **ISO-8601 string**) → `createdAt`, not
  `date_added` (Unix int) as documented. A numeric `date_added`/`dateAdded` is
  accepted as a fallback; missing → current time. Decoding is done with a custom
  `init(from:)` so any single bad field degrades gracefully rather than failing
  the whole file. - `folder` is ignored (flat import), as are
  `comment`/`article`/`keyword`/`isStarred`. Missing `title` → empty string.
  Duplicate URL → overwrite title/description/tags in place. Verified against a
  real 211-bookmark export (all imported, re-import idempotent).
- **✅ Export is the native format and complete.** `stash-json` emits `{ version,
  exportedAt, bookmarks[] }` with ISO-8601 timestamps, **all** bookmarks
  (archived included), sorted by `createdAt` ascending. `withoutEscapingSlashes`
  keeps URLs readable. Versioned (`"1"`) so future schema changes are detectable
  by importers.
- **✅ Post/Redirect/Get with a session flash.** A successful import redirects to
  `/app/settings?imported=1`; the full `ImportResult` (including the
  skipped-record descriptions, which are too large/numerous for the query
  string) is flashed via a one-shot JSON value in the session and cleared on
  read.
- **✅ Upload body limit raised.** The import route uses `.on(.POST, … body:
  .collect(maxSize: "16mb"))` because Vapor's default collected-body cap (16KB)
  would reject any real export file.
- **✅ Multipart upload** via Vapor's `File` in a `Content` form struct; the
  export download sets `Content-Disposition: attachment;
  filename="stash-export-YYYY-MM-DD.json"`.
- **✅ Stash JSON importer (`stash-json`) — backup restore / round-trip.**
  Decodes the native export (`{ bookmarks: [...] }`), mapping `url` (required),
  `title`, `description`, `tags` (normalised), `isArchived`, `faviconURL`, and
  `createdAt` (ISO-8601; current time if missing/unparseable — accepts
  fractional seconds as a fallback). `id`/`updatedAt`/`version`/ `exportedAt`
  are ignored. Duplicate URL updates in place (createdAt preserved), same
  contract as Anybox. Registering it was a one-line change in the registry — the
  settings selector picked it up with no template edits, validating the
  pluggable design.

---

## Tag sidebar (bookmark list)

- **✅ Flattened pre-ordered tree, not recursion.** Leaf has no clean recursion,
  so the tag tree is built server-side into a flat `[SidebarTag]` carrying
  `depth`, and the template indents each row by `calc(depth * 0.9rem)`. The list
  is produced by sorting all tag slugs by their `/`-split path components
  (prefix-first) — which *is* a pre-order DFS: a parent always precedes its
  subtree and siblings are alphabetical at every level.
- **✅ Synthetic parents.** If only `swift/vapor` exists, `swift` is still
  emitted as a parent node (so children nest under something) with `count = 0`;
  the template hides the count when 0. Synthetic parents remain clickable —
  `?tag=swift` prefix-matches `swift/*`, so the link is useful even without a
  bare `swift` tag.
- **✅ Counts are exact**, matching `/app/tags` (count of bookmarks with that
  literal tag), not the prefix aggregate — consistent with the rest of the app.
- **✅ Reuses the existing tag query.** The sidebar loads the user's bookmarks
  and tallies tag counts (same source as `/app/tags` and the autocomplete) — one
  extra `.all()` per list view, accepted for simplicity over a separate
  aggregate query.
- **✅ Encoded hrefs built server-side.** `?tag=swift%2Fvapor` is percent-encoded
  in Swift (`tagHref`) since Leaf/URLComponents leave `/` unencoded; the brief
  wants `%2F`.
- **✅ Layout & dark mode.** Two-column flex (`.app-main` flex:1 + `.tag-sidebar`
  fixed 220px, sticky/scrollable); hidden under 768px (the on-list filter pills
  cover mobile). All colours use existing variables — active tag is `--accent`,
  counts are `--text-muted`. `/app/tags` is unchanged.
- **⚠️ Leaf gotcha — a non-nil empty `String` is truthy in `#if`.** A
  *non-optional* `String` field that is `""` makes `#if(field)` evaluate
  **true** (unlike a `String?` field, which is `nil` when absent and therefore
  falsy — which is why `#if(error)`/`#if(notice)` work). The `tag` context field
  is `query.tag?.nonEmpty ?? ""`, so guards on it must be explicit: `#if(tag !=
  "")` for the "Filtered by tag" line and the hidden form input, and `#if(tag ==
  "")` for the "All" active state. (This is also why `#if(cond):#else: X #endif`
  with an empty then-branch misbehaved earlier — the same empty-string-is-truthy
  quirk; prefer positive single-branch tests.)
- **✅ Sidebar positioning: just two flex columns (final).** Both `sticky` and
  `fixed` were tried and rejected — `sticky` scrolled away once past the
  parent's height, and `fixed` (viewport- anchored with magic `top`/`right`
  offsets) was brittle and detached from the content. The desired behaviour is
  the simplest: a normal two-column document where both columns scroll together
  as one unit. So `.tag-sidebar` has **no**
  `position`/`overflow`/`max-height`/scrollbar rules and `.app-main` has **no**
  reserve margin — just `.app-layout { display:flex; gap:1.5rem;
  align-items:flex-start }`, `.app-main { flex:1; min-width:0 }`, `.tag-sidebar
  { flex:0 0 220px; width:220px }`. The sidebar starts at the top of the layout
  and ends where its content ends. Mobile (<768px) hides it. (Supersedes both
  the sticky and fixed attempts.)
- **✅ "Tags" top-aligned with the search field.** The sidebar gets `margin-top:
  3.25rem` so its heading lines up with the search box rather than the
  `Bookmarks` h1. The offset is derived from pinned values (`.app-main h1 {
  margin: 0 0 1rem }` → 2.25rem line + 1rem margin), so it's exact, not a
  guessed magic number; the h1 pin is scoped to `.app-main` so other pages are
  untouched. (Aligning with the *first bookmark cell* was rejected — the
  conditional "Filtered by tag" line moves that cell between filtered/unfiltered
  views, so a fixed offset couldn't track it.)
- **✅ "Untagged" filter via an internal sentinel.** `?tag=__untagged__` is
  special-cased in the list handler *before* the normal prefix path — it filters
  `tagsSearch == ""` (the value for a tagless bookmark). The untagged count is
  tallied from the same bookmark fetch that builds the sidebar (no extra query).
  The sentinel never reaches the UI as a label: the sidebar shows "Untagged"
  (sentinel only in the `href`), and the filter banner's `tagDisplay` is
  overridden to "Untagged".
- **🐛 The `__untagged__` sentinel was honored by the web UI but not the JSON
  API.** The macOS app's "Untagged" sidebar entry correctly sent `GET
  /api/v1/bookmarks?tag=__untagged__`, but `BookmarkController.list` had no
  sentinel branch — it fell straight into the prefix path, where
  `normalizeTagQuery` lowercased/trimmed it into a literal tag no bookmark
  carries, so the result was always empty (only `AppWebController` special-cased
  it, which is why `/app` worked). Fixed by adding the same `rawTag ==
  Bookmark.untaggedSentinel → filter(\.$tagsSearch == "")` branch to the API
  controller. The sentinel string was promoted from a private
  `AppWebController.untaggedSentinel` constant to `Bookmark.untaggedSentinel` so
  both controllers share one source of truth (the web controller's constant now
  aliases it). Locked in with a `BookmarkTests` case asserting
  `?tag=__untagged__` returns only tagless bookmarks. ⚠️ The filter *expression*
  is still written in both controllers — only the sentinel constant is shared;
  this duplication is what let the API drift from the web UI in the first place.
- **✅ "Today" / "This Week" recency filters via the same sentinel pattern.** Two
  more sidebar helpers sit after "Untagged": `?tag=__today__` (bookmarks created
  since `Calendar.startOfDay`) and `?tag=__this_week__` (created since the most
  recent Monday). They reuse the `tag` query param rather than a new `added=`
  parameter — this is deliberate: the sentinel approach inherits the existing
  plumbing for free (the `listURL` pagination helper and the toolbar's hidden
  `tag` input already round-trip `tag`, and the filter banner's `tagDisplay`
  just gains "Today"/"This Week" overrides alongside "Untagged"). The trade-off
  is that recency and tag filters are mutually exclusive, same as "Untagged" —
  an acceptable limitation for these convenience shortcuts. The two new
  sentinels live on `Bookmark` next to `untaggedSentinel`; the date math is one
  shared `AppWebController.dateBoundaries(now:)` helper used for *both* the
  query filter and the sidebar counts, so the two can never disagree. Week start
  is **Monday** (`calendar.firstWeekday = 2`, then
  `dateInterval(of: .weekOfYear)`), using the server's `Calendar.current`
  timezone. The today/this-week counts are tallied in the same single pass over
  the user's bookmarks that already builds the sidebar
  (no extra query), and the count badge is hidden when 0 like the others. ⚠️
  Web-UI only — the JSON API does not (yet) honor these sentinels, consistent
  with their nature as web-frontend conveniences. ⚠️ Like "Untagged", the filter
  banner renders "Filtered by tag Today", a slight wording mismatch carried over
  from the shared template path.
- **✅ Sidebar split into two labeled sections: Views + Tags.** The smart filters
  (All, Untagged, Today, This Week) and the hierarchical tag tree had grown into
  one undifferentiated list under a single "Tags" heading, which mislabeled the
  filters as tags. They now live in two `<ul class="tag-tree">` lists, each under
  its own `h2` — "Views" over the filters, "Tags" over the tree (`.tag-tree + h2`
  gets `margin-top` so the second heading is spaced from the first list). Both
  lists reuse the `tag-tree` styling. The "Views" heading is now the sidebar's
  first element, so it takes over the `margin-top: 3.25rem` search-field alignment
  role previously held by "Tags" — no value change needed, just a heading rename.

---

## Dark mode (web frontend + admin dashboard)

- **✅ Cookie-only, no DB.** The theme preference (`light`/`dark`/`auto`, default
  `auto`) lives in a 1-year `stash_theme` cookie at path `/` so it applies to
  both `/app` and `/admin`. No model field or migration — it's a pure
  presentation concern. The cookie is **`HTTPOnly=false`** on purpose so the
  inline flash-prevention script can read it; `SameSite=Lax`.
- **✅ Flash-of-wrong-theme prevention.** A tiny inline script at the top of
  `<head>` (before any CSS) reads the cookie and sets `data-theme` on `<html>`
  synchronously, before first paint. For `auto`/missing it sets nothing and lets
  the media query decide.
- **✅ CSS custom properties, three-way resolution.** All colours became
  variables on `:root` (light). Dark values are defined twice — under
  `[data-theme="dark"]` (explicit) and under `@media (prefers-color-scheme:
  dark) :root:not([data-theme="light"]):not([data-theme="dark"])` (auto). The
  duplication is intentional (matches the spec) so an explicit choice always
  wins over the OS preference. `color-scheme` is set per-mode so native
  controls/scrollbars match.
- **✅ Shared layout = free admin theming.** Because `/app` and `/admin` share
  `layout.leaf`, the variables + flash script apply to both with no
  admin-specific work. Theme is only *settable* from `/app/settings` (a plain
  HTML radio form → `POST /app/settings/theme` sets the cookie and redirects);
  the site-wide cookie path means it still themes `/admin`.
- **✅ Palette.** iOS-style dark (not pure black): bg `#1c1c1e`, surface
  `#2c2c2e`, border `#3a3a3c`, text `#f2f2f7`/`#aeaeb2`, accent `#0a84ff`,
  danger `#ff453a`, success `#30d158`. Pill and banner colours fold into the
  shared `--ok-*`/`--err-*` variables so they adapt automatically.

---

## Danger zone — delete all bookmarks

- **✅ Phrase confirmation, enforced on both ends.** `POST
  /app/settings/delete-all-bookmarks` re-checks the typed phrase (`delete all`,
  case-insensitive, trimmed) **server-side** — the client-side `oninput`
  enable/disable of the submit button is only a convenience, never the gate.
- **✅ Reveal-then-confirm, minimal vanilla JS.** A "Delete all bookmarks" button
  reveals a hidden form; a ~10-line inline script enables the submit button only
  when the input matches. No framework, consistent with the rest of `/app`.
- **✅ Scope is bookmarks only.** Deletes the user's bookmarks and resets
  `bookmarkCount` to 0; account, password, 2FA, and tag metadata (derived from
  bookmarks) are untouched. PRG redirect to `/app?notice=all_bookmarks_deleted`
  with a one-shot banner driven by a `notice(for:)` mapping (parallel to the
  existing `?ok=`/`message(for:)` convention).

---

## Linting & formatting (SwiftLint + SwiftFormat)

- **✅ Enabled the opt-in organization rules.** `organizeDeclarations` and
  `markTypes` are *disabled by default* in SwiftFormat; the `.swiftformat`
  supplied all their options but never turned the rules on, so no MARK
  organization was happening. Added `--enable organizeDeclarations` and
  `--enable markTypes`. Applied across all source + test files: MIT header, a
  `// MARK: - <Type>` before each type/extension, and in-type sections in **type
  mode** — `Nested Types → Static Properties → Properties → Computed Properties
  → Lifecycle → Functions` — with public-before-private *ordering within* each
  section.
- **✅ Type mode over visibility mode (user decision).** SwiftFormat emits either
  type marks *or* visibility marks, not both. Chose type mode (matching the
  config's `--organization-mode type` and the requested Nested
  Types/Properties/Lifecycle order); visibility mode was rejected because the
  codebase is overwhelmingly `internal`-access, so it would mostly produce
  `Internal`/`Private` headings rather than `Public`/`Private`.
- **✅ `Package.swift` is safe.** SwiftFormat keeps `// swift-tools-version:` as
  line 1 and skips the license header there.
- **✅ Disabled three SwiftLint rules that false-positive on Fluent.**
  `first_where`, `contains_over_first_not_nil`, and `empty_string` flag the
  query DSL (`.filter(\.$x == y).first()`, `first(where:) != nil`, `\.$field ==
  ""`) — these are database builders, not `Sequence` ops, and rewriting them
  would break compilation.
- **✅ `identifier_name` exclusions** for idiomatic short names (`db`, `q`, `i`,
  `a`, `b`, `c`, `s`, `v`, `ok`, `ts`, `me`). The Anybox snake_case JSON key is
  handled with a proper Swift identifier instead of a lint exception: `case
  dateAddedUnix = "date_added"` in the `CodingKeys` enum.
- **⚠️ Disabled `file_length` / `type_body_length` / `function_body_length`**
  for consistency with the complexity family already disabled in the config
  (`line_length`, `nesting`, `cyclomatic_complexity`,
  `function_parameter_count`, `large_tuple`) — the web controllers and test
  suites legitimately run long. Easy to switch to soft thresholds instead if a
  size nudge is wanted.
- **✅ One inline `for_where` disable** in `AuthController` — the loop's
  predicate is `try await`, which a `where` clause can't hold.
- Result: `swiftlint lint` clean (0 violations), `swiftformat --lint`
  idempotent, build clean, 65 tests pass.

---

## Tag renaming

- **✅ Shared logic in `TagRenamer`.** `POST /api/v1/tags/rename` (JSON) and
  `POST /app/tags/rename` (web form) both call the same `TagRenamer.rename`, so
  behaviour can't drift. Both `from`/`to` are normalised with
  `normalizeTagQuery` (same as every other tag write); empty-after-normalisation
  → `422 validation_failed`; `from == to` or an unused `from` is an idempotent
  200 with `affectedBookmarks: 0`.
- **✅ Renames children, merges without duplicates.** Candidates are found via
  the `tags_search` prefix match (`|from|` or `|from/`), then a pure transform
  renames the exact tag and rewrites `from/x → to/x`, de-duplicating so a merge
  into an existing `to` never stores a tag twice (order preserved). `applyTags`
  keeps `tags_search` in sync. Scoped to the user's own bookmarks.
- **✅ Web UX:** each tag row has an inline rename form revealed by a small
  vanilla-JS toggle (same pattern as the danger zone); submit does
  Post/Redirect/Get to `/app/tags?ok=renamed&from=…&to=…&n=…` (values
  percent-encoded via the shared `queryValue` helper, also now used by
  `tagHref`), and the browser builds the "Renamed X to Y (N bookmarks updated)"
  banner from those params.
- **⚠️ Beyond the PRD** — tag renaming isn't in `PRODUCT.md`; added on request.
  Lint: `to` is the documented API field name, so it joins the idiomatic
  short-name exclusions in `.swiftlint.yml`.

## Tag deletion

- **✅ Shared logic in `TagDeleter`** (mirrors `TagRenamer`). `DELETE
  /api/v1/tags/:tag` (JSON) and `POST /app/tags/delete` (web form — HTML forms
  can't issue `DELETE`, so a `POST` sub-route is used) both call
  `TagDeleter.delete`. The `:tag` path parameter is URL-decoded by Vapor, so a
  hierarchical slug is sent percent-encoded (`foo-bar%2Fswift`). The tag is
  normalised with `normalizeTagQuery`; empty-after-normalisation → `422
  validation_failed`; a tag that isn't used is an idempotent 200 with
  `affectedBookmarks: 0`.
- **✅ Deletes children too.** Same `tags_search` prefix candidate query (`|tag|`
  or `|tag/`) as rename, then a pure transform drops the exact tag and any
  `tag/x` (order of the rest preserved). A look-alike like `foo-barbaz` is left
  untouched (no slash boundary). A bookmark whose only tag is deleted survives
  with an empty `tags` array — bookmarks are never deleted, only their tags.
  `applyTags` keeps `tags_search` in sync; scoped to the user's own bookmarks.
- **✅ Web UX:** each tag row gains a "Delete" button alongside "Rename"; it
  reveals an inline confirmation ("Delete X and all its children? This cannot be
  undone.") via the same vanilla-JS toggle (only one of rename/delete open per
  row). Submit does Post/Redirect/Get to `/app/tags?ok=deleted&tag=…&n=…`, and
  the browser builds the "Deleted X (N bookmarks updated)" banner from those
  params.
- **⚠️ Beyond the PRD** — like renaming, tag deletion isn't in `PRODUCT.md`;
  added on request.

## Code style — comments and documentation

- **✅ No inline comments inside method bodies.** The code and tests are the
  documentation. Inline `//` comments explaining *what* the code does are
  removed; the code should be readable without them.
- **✅ `///` doc comments on types only.** Every `enum`, `struct`, `class`,
  `actor`, and `protocol` has a doc comment. Methods, computed properties, and
  stored properties inside types do not.
- **✅ American English throughout.** All doc comments, `#expect` descriptions,
  and test labels use American English spelling (`behavior`, `initialize`,
  `normalize`, `color`, etc.), never British English.
- **✅ Tests follow Given/When/Then.** Every test has `// Given`, `// When`, `//
  Then` structural comments. Every `#expect()` has a string description starting
  with `"It should ..."` describing the expected behavior.

## Code style — blank lines

- **✅ Blank line after `guard` (automated).** Enforced by SwiftFormat's
  `blankLinesAfterGuardStatements` rule (`--line-between-guards false`): a blank
  line follows the last `guard` in a group, and blank lines between consecutive
  guards are collapsed.
- **⚠️ Blank line before `if`, `for`/`switch`, and before `return` in
  multi-statement bodies (manual convention).** SwiftFormat has no rule that
  inserts blank lines before these statements, and neither does SwiftLint's
  autocorrect — enforcing it automatically would require a fragile custom tool.
  These are therefore a hand-applied convention, not machine-enforced: separate
  a control-flow block (`if`/`for`/`switch`) from the code above it with a blank
  line, and precede a `return` with a blank line when the function body has more
  than one statement.

## Code style — commit messages

- **✅ Follow the seven rules of a great commit message**
  ([cbea.ms/git-commit](https://cbea.ms/git-commit/)). A hand-applied
  convention; no hook enforces it: 1. Separate subject from body with a blank
  line. 2. Limit the subject line to 50 characters. 3. Capitalize the subject
  line. 4. Do not end the subject line with a period. 5. Use the imperative mood
  in the subject line ("Add", "Fix", "Bump" — not "Added"/"Adds"). 6. Wrap the
  body at 72 characters. 7. Use the body to explain *what* and *why*, not *how*.
- **✅ Body style.** Prose paragraphs for a single cohesive change (a feature or
  milestone); `-` bullets when a commit groups several distinct changes —
  matching the existing history. The whole repository's history was reworded so
  every subject fits in 50 characters.

## iOS/macOS project — committed, off XcodeGen

- **🔁 The Xcode project is now committed; XcodeGen is retired.** M8 declared
  "`StashApp/project.yml` is the source of truth; `.xcodeproj` is gitignored."
  That is **superseded**: `StashApp/Stash.xcodeproj` is now committed and
  `project.yml` is deleted. Two reasons drove the switch: (1) regenerating wiped
  Xcode's "update to recommended settings" each time, and (2) we want the modern
  format where folders on disk are referenced once rather than every file being
  listed in the project. `xcuserdata/` stays gitignored (via the generic
  `*.xcodeproj/xcuserdata/` rule); the `Stash` and `StashMac` **shared schemes**
  are committed under `xcshareddata/`.
- **✅ Synchronized folder groups for file references.** The project uses
  `PBXFileSystemSynchronizedRootGroup`s so adding/moving/renaming a file on disk
  needs no project edit. Membership is folder-level, which fits the codebase
  because platform splits are `#if`-guarded (not per-file membership): `Common/`
  → all four targets, `Stash/` → both apps, `StashShareExtension/` → both
  extensions. `Info.plist`/entitlements inside a synced folder are excluded from
  target membership (they are wired via `INFOPLIST_FILE` /
  `CODE_SIGN_ENTITLEMENTS`; otherwise the build double-produces `Info.plist`).
- **⚠️ The synchronized-folder conversion is done in Xcode, not headlessly.**
  Rewriting a `.pbxproj` without Xcode means round-tripping through `plutil`,
  which emits an XML-format project that breaks `xcodebuild` package resolution
  and scheme autocreation. So the conversion to synchronized folders (and the
  Capabilities/Signing check) is performed in Xcode; tooling/automation should
  not regenerate the project.
- **✅ Renamed the cross-target `Shared/` to `Common/`.** There were two `Shared`
  folders at different scopes — `StashApp/Shared/` (compiled into the app *and*
  the extensions) and `StashApp/Stash/Shared/` (app code shared between iOS and
  macOS). The outer one is now `StashApp/Common/`. The inner `Stash/Shared/` was
  then flattened up into
`StashApp/Stash/` directly (`Models/`, `Repositories/`, `Views/`,
`AppEnvironment`, `AppSettings`) — once the outer folder was `Common/`, the
`Shared/` subfolder name was redundant.

## Merged the iOS and macOS targets into multiplatform targets

- **🔁 Four targets collapsed to two.** M10 created separate iOS and macOS
  targets (`Stash`/`StashMac` and
  `StashShareExtension`/`StashMacShareExtension`). With SwiftUI there's no
  reason for that, so `Stash` and `StashShareExtension` are now
  **multiplatform** targets (Supported Destinations: iPhone, iPad, Mac), and the
  two `*Mac*` targets are deleted. One `Stash` scheme builds both platforms
  (selected by run destination); the macOS product is still a native
  AppKit/SwiftUI app (`SUPPORTS_MACCATALYST = NO`, `SDKROOT = auto`). **Zero
  Swift changes** — the code was already `#if`-guarded and the single `@main`
  already branched per platform. The macOS share-extension bundle id changed
  from `cc.otavio.stash.macShareExtension` to `cc.otavio.stash.ShareExtension`
  (one id across platforms now).
- **✅ Per-platform `Info.plist`/entitlements are SDK-conditional, in a
  non-synced `Config/` folder.** The two platforms differ only in a few
  `Info.plist` keys (iOS launch screen / orientations vs. macOS
  `LSApplicationCategoryType`) and entitlements (macOS adds App Sandbox +
  network client). Each is selected with `INFOPLIST_FILE[sdk=macosx*]` /
  `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`. Moving all eight files **out of the
  synchronized source folders** into `StashApp/Config/` also fixed the
  stray-`Resources/Info.plist` defect from the synchronized-folders review —
  with no plists inside the synced folders, no membership exceptions are needed
  and nothing leaks into the macOS bundles (verified: clean iOS + macOS builds
  each carry exactly one app `Info.plist` and one embedded `.appex`).
- **✅ Edited the project with the `xcodeproj` Ruby gem, not `plutil`.** The gem
  writes the proper ASCII `.pbxproj` (the `plutil` JSON round-trip emits XML
  that breaks `xcodebuild`), so target settings, target deletion, and the
  conditional build settings were applied programmatically and verified by
  building both destinations from the one scheme.

---

## Editable server URL on the login screen

- **✅ The server URL is now editable from `LoginView`, not just first-launch
  `SetupView`.** A self-hosted instance reached by IP can change address,
  leaving a configured-but-unreachable app with no in-app way to fix it on iOS
  (logout returns to login, which previously only *displayed* the URL as footer
  text). `LoginView` now carries a "Server" `TextField` (same `urlFieldStyle` /
  `http(s)://` validation as `SetupView`), and `canSubmit` also requires a valid
  URL.
- **✅ Edited locally, committed to `AppSettings` only on sign-in.** The field is
  seeded from `settings.serverURL` on appear into a local `@State`, and written
  back to `settings.serverURL` inside `signIn()`. Binding the `TextField`
  straight to `settings.serverURL` would flip `isConfigured` to `false` the
  instant the field was cleared mid-edit, bouncing `RootView` back to
  `SetupView`. No change was needed below the view: `StashClientProvider`
  already rebuilds its cached client whenever the persisted URL changes, so the
  next login hits the new server.

---

## M4.1 — CI/CD pipeline & Docker image publishing

- **✅ Two workflows, split by trigger and cost.** `.github/workflows/ci.yml`
  runs on every push to `main` and every pull request — it builds and tests all
  components (`Backend` test, `StashKit` build + test, `CLI` release build, and
  the iOS + macOS app builds) but **builds no image and pushes nothing**, so it
  stays a regression gate. `.github/workflows/release.yml` runs **only on a
  `v*.*.*` tag push**; it re-runs the backend test suite, then (and only if
  tests pass) builds and publishes the Docker image. Keeping image publishing on
  tags-only means routine pushes never spend the multi-arch build.
- **✅ `ci.yml` tests the backend in debug, not release.** An earlier revision
  built and tested the backend with `-c release` (to validate the shipping
  configuration in one compile). That **crashed the Swift 6.2.1 compiler** in
  CI: its SIL optimizer (which only runs under `-O`/release) hit a fatal error
  compiling the Vapor dependency tree. A regression gate doesn't need release
  optimization — the release build is validated by the Docker image (`swift
  build -c release` on Swift 6.1) at tag time — so the backend is tested in
  plain debug (`swift test`, which compiles and runs in one step). Debug skips
  the crashing optimizer entirely.
- **✅ Backend tests run serially (`--no-parallel`).** swift-testing parallelizes
  by default, and each test boots its own `Application` and hashes passwords
  with bcrypt cost 12 (deliberately slow). On a CI runner that parallelism
  starves the SQLite connection pool — 6 of 76 tests failed with
  `connectionRequestTimeout` (all timeouts, no logic failures) while the rest
  passed. Running the suite with `--no-parallel` removes the contention; the
  trade-off is a slower run, acceptable for a gate. (Locally on a fast
  multi-core Mac the parallel run doesn't starve, which is why this only
  surfaced in CI.)
- **✅ GitHub Actions layer cache for Docker builds (`type=gha`).**
  `docker/build-push-action` is configured with `cache-from: type=gha` /
  `cache-to: type=gha,mode=max`, so the expensive Swift layers — package
  resolution and compilation — are cached between runs. `mode=max` caches every
  intermediate layer (not just the final image), which is what makes the Swift
  build layers reusable and subsequent tagged releases substantially faster.
- **⚠️ Image visibility is a one-time manual step, NOT automated; the repo stays
  private.** The brief called for a `curl PATCH` to
  `/user/packages/container/stash/visibility` to flip the image public from CI.
  That does not work: there is **no REST endpoint for container-package
  visibility** (the Packages API only exposes `GET`/`DELETE`/`restore` —
  visibility is a web-UI-only setting), and even if one existed, `GITHUB_TOKEN`
  is a bot installation token that cannot call the user-scoped `/user/...` API.
  Worse, a bare `curl` without `--fail` swallows the 404/403 and the job stays
  green — a silent no-op. The step was therefore **removed** and replaced with a
  comment: after the first push, set the package public **once** by hand
  (Packages → `stash` → Package settings → Danger Zone → Change visibility →
  Public). It then stays public across every subsequent push. The source
  repository remains private — only the image is public.
- **✅ `GITHUB_TOKEN` is sufficient for everything that IS automated — no PAT or
  extra secrets.** GHCR login, the multi-arch push, and the release creation all
  authenticate with the workflow's built-in `secrets.GITHUB_TOKEN`. The
  `publish` job declares `permissions: { contents: write, packages: write }` so
  that token can push the package and create the release; no personal access
  token or additional repository secret is needed. (The one thing it cannot do —
  flip package visibility — is the manual step above.)
- **✅ Release attaches the canonical `docker-compose.yml`.**
  `softprops/action-gh-release` publishes a GitHub Release for the tag with
  `Backend/docker-compose.yml` attached and quick-start instructions in the
  body, so a user downloads the compose file from the release and runs `docker
  compose up -d` against the published image — no clone, no build.
- **✅ Canonical `docker-compose.yml` references the published image; the local
  override stays gitignored.** `Backend/docker-compose.yml` already points at
  `ghcr.io/otaviocc/stash:latest` (no `build:`), and the local-development
  `Backend/docker-compose.override.yml` (which uses `build: .`) is ignored via
  `Backend/.gitignore`, so it never lands in the repo and the release artifact
  is always the image-based file.
- **⚠️ `ci.yml` is split into a Linux `backend` job and a macOS `apple` job.**
  The components don't share a platform *or* a toolchain. The `backend` runs on
  `ubuntu-latest` / Swift 6.1 — matching the Docker image's `swift:6.1-jammy`
  base (and 6.1 avoids the 6.2.1 optimizer crash above). The `apple` job covers
  everything Apple-platform — StashKit (build + test), CLI (release build), and
  the app + Share Extension (iOS and macOS builds) — and **must run on macOS**:
  StashKit and CLI depend on `MicroClient`, which uses Apple Foundation's
  networking types (`URLSession`/`URLRequest`/ `URLResponse`) without the
  `FoundationNetworking` shim Linux requires, so they do not compile on Linux at
  all (the original M4.1 brief assumed they would); everything also targets iOS
  26 / macOS 26 and declares swift-tools 6.2, i.e. it needs Xcode 26. The job
  runs on `macos-latest` and pins Xcode via `maxim-lobanov/setup-xcode@v1`
  (`latest-stable`). ⚠️ macOS runner minutes bill at ~10× on a private repo, so
  all the Apple targets share **one** runner rather than fanning out.
  `release.yml`'s `test` job stays on Linux / Swift 6.1, since it only touches
  `Backend`.
- **✅ The app is build-verified on both platforms, not unit-tested.** The
  `Stash` app and `StashShareExtension` have no test target (PRD §19.6 — the app
  is manual/integration-tested, the backend carries the suite). CI therefore
  *builds* the `Stash` scheme for iOS (a generic simulator destination, so no
  specific simulator must exist on the runner) and macOS with
  `CODE_SIGNING_ALLOWED=NO`; building also compiles the embedded Share
  Extension. That catches compile-level regressions across the cross-platform
  `#if` shells — the practical risk for a target with no tests.

---

## HTTPS / Caddy

- **✅ HTTPS via optional Caddy sidecar, not built into the image.** Stash serves
  plain HTTP internally; TLS termination is a deployment concern. This mirrors
  the pattern used by Navidrome and other self-hosted tools — the app stays
  simple, and users who don't need HTTPS aren't forced to deal with
  certificates. Caddy is documented as an opt-in addition to
  `docker-compose.yml` (the `caddy/docker-compose.caddy.yml` override resets the
  `app` port mapping and adds a `caddy:2-alpine` reverse proxy on 80/443)
  covering both local network (`tls internal`, self-signed, with root-CA trust
  instructions per platform) and internet-exposed (automatic Let's Encrypt) use
  cases. No changes to the Stash image or Vapor backend are required.

---

## Documentation

- **✅ All documentation consolidated into a single top-level `Docs/` folder.**
  Every component's docs were merged into `Docs/` and the per-component READMEs
  (`Backend/README.md`, `CLI/README.md`, `StashApp/README.md`,
  `StashKit/README.md`) were deleted; the root `README.md` became a concise
  landing page that links into `Docs/`. The folder holds one guide per concern —
  `backend-build`, `backend-local`, `backend-docker`, `backend-docker-caddy`,
  `configuration`, `api`, `cli-build`, `mobile-build`, `stashkit`. `PRODUCT.md`
  and `DECISIONS.md` remain at the repo root.
- **✅ The `caddy/` directory was folded into `Docs/backend-docker-caddy.md` and
  removed.** The `Caddyfile` variants and the `docker-compose.caddy.yml`
  override (🔁 superseding the committed files referenced in the *HTTPS / Caddy*
  entry above) now live as copy-paste code blocks inside that one doc; users
  recreate them in a `caddy/` folder next to their `docker-compose.yml`.
  Trade-off: nothing Caddy-related ships in the repo anymore, so there is a
  single documented source of truth instead of files that could drift from their
  walkthrough.

---

## Markdown style — hard line breaks

- **✅ All Markdown files use hard line breaks, wrapping prose at 80 characters.**
  Prefer hard-wrapped lines over long flowing paragraphs: easier to read in a
  plain text editor and produces clean, reviewable diffs. Code blocks, tables,
  and headings are left as-is (tables cannot be narrowed without losing
  structure). Every time a Markdown file is created or edited, apply this
  convention to the modified sections.

---

## Site Settings & Admin Customisation

- **✅ `SiteSettings` is a single-row table, never deleted.** There is always
  exactly one row, seeded by the `CreateSiteSettings` migration (accent theme
  `ocean`, all other fields `nil`). `SiteSettingsService.current(on:)` is the
  single accessor; it recreates the row on first access if somehow missing, so
  callers never deal with an empty table.
- **✅ Theme injection via a server-side CSS block.** The selected accent theme's
  light and dark hex values are injected into `<head>` in `layout.leaf` as a
  second `<style>` block (after the main stylesheet) that overrides the default
  `--accent` custom property. All existing `var(--accent)` uses pick it up
  automatically — no per-template or per-stylesheet changes. There is **no
  per-request DB query**: the values come from an app-level cache
  (`SiteSettingsCache` on `Application.storage`, behind an `NSLock`) loaded once
  at boot and refreshed in place when the admin saves the appearance form.
- **⚠️ Chrome is a nested `chrome` field on every web context, not a flattened
  merge.** Both web controllers pass `chrome: req.siteChrome()` (footer + accent
  + about text) into every page context, and `layout.leaf` / `_footer.leaf` read
  `chrome.*`. A generic wrapper that flattens an arbitrary page context's keys
  alongside a `chrome` key was rejected: Leaf's `LeafEncoder` `fatalError`s on a
  second `container(keyedBy:)` at the same encoding level ("Can't encode to
  multiple containers at the same encoding level"), so the
  `try page.encode(to:)`-then-add-a-key trick that works with `JSONEncoder`
  crashes under Leaf. Threading one nested field is verbose but reliable.
  `req.siteChrome()` is synchronous and never throws — a missing cache falls back
  to defaults so a page render is never blocked by a missing footer config.
- **✅ Stash identity is hardcoded, not configurable.** The name "Stash", the
  Ko-fi link (`https://ko-fi.com/otaviocc`), and the Mastodon link
  (`https://social.lol/@otaviocc`) live directly in `_footer.leaf`. Admins cannot
  remove or replace them; they are not passed via `FooterContext`, so they cannot
  be accidentally omitted or overridden.
- **✅ `VERSION` file approach.** The version string is read from `Backend/VERSION`
  at startup (`AppVersion.read(directory:)`, relative to the working directory)
  and stored on `Application` under `AppVersionKey`. It is copied into the Docker
  image (`COPY`/`cp` of `VERSION` in the build stage). Falls back to `"dev"` when
  the file is missing or empty.
- **✅ Theme picker is pure HTML radio inputs.** No JavaScript is needed for
  selection: nine visually-hidden radio inputs, each wrapped by a `<label>` whose
  coloured circle (`.theme-swatch`) is styled via CSS, with
  `input:checked + .theme-swatch` drawing the active ring.
- **✅ `aboutText` capped at 280 characters.** A natural limit for a short
  instance description (one Mastodon post). Enforced server-side (422 + inline
  error on overflow); a small `oninput` counter mirrors the existing danger-zone
  JS pattern for convenience only.
- **✅ `footerCustomURL` requires `https://`.** Plain HTTP links are rejected
  (422) to avoid mixed-content warnings on HTTPS instances. The custom footer
  link renders only when **both** label and URL are non-empty; empties are
  normalised to `nil` on save.

---

## Token refresh — concurrent-refresh race (macOS spurious logout)

- **✅ Silent refresh is single-flight; concurrent callers are coalesced.**
  Refresh tokens are single-use — the backend rotates on every
  `POST /api/v1/auth/refresh` and deletes the one just presented (M1, §8.1). The
  app fires `refreshIfNeeded()` before *every* authenticated request, and it had
  no serialization: two requests that started together with an expired access
  token both read the same refresh token from the Keychain and both POSTed it.
  The server honoured the first and deleted it; the second arrived with a now-
  deleted token → `401 token_invalid` → `clearSession()` → the user was dropped
  to the login screen. `AuthRepository` (and the Share Extension's
  `ExtensionSession`) now hold an `inflightRefresh: Task<Void, Error>?`: the
  first caller spawns the refresh task and stores it; concurrent callers `await`
  that same task instead of starting their own. Because both types are
  `@MainActor`-isolated, the check-and-set is race-free without locks (the first
  suspension point is `await task.value`, after the task is stored).
- **⚠️ Why this only bit macOS / iPad, not iPhone.** It is the navigation shell,
  not the auth code (which is shared). `MacContentView` (and the iPad
  `NavigationSplitView`) render both columns at launch, so the sidebar's
  `tagRepository.load()` and the detail column's bookmark load fire two
  authenticated requests *simultaneously* — the race. iPhone's
  `TabContainerView` lazy-loads tabs, so only one request fires at cold start; a
  backend restart is a red herring (refresh tokens live in Postgres with a
  volume and survive it). The bug was intermittent because it only triggers when
  the cached access token is already expired at launch (app idle > ~15 min); a
  fresh token short-circuits at the expiry guard before any refresh.
- **✅ Only a definitive auth failure clears the session.** The old `catch`
  cleared the session on *any* refresh error, so a transient network blip or a
  5xx during refresh logged the user out even though the refresh token was still
  valid server-side. `performRefresh()` now clears only on an authentication
  failure (`token_expired` / `token_invalid` / `invalid_credentials` /
  `account_suspended`) and rethrows everything else with the session intact for
  retry. This is safe because the refresh endpoint returns `token_invalid` /
  `token_expired` for *every* dead-token case — invalid, expired, rotated-away,
  and revoked (suspend / password reset / 2FA reset, §8.6) — so the logout
  behaviour for genuinely dead tokens is unchanged; only transient failures are
  spared.

---

## Cross-links between the `/app` and `/admin` web navs

- **✅ The `/app` nav shows a "Dashboard" link to `/admin`, gated to admins.**
  The user-facing frontend's nav bar gained a "Dashboard" entry after
  "Settings", linking straight to the admin dashboard so an admin browsing their
  own bookmarks can cross over without retyping the URL. It is rendered only when
  the signed-in user is an admin (`#if(appIsAdmin)`), since the `/admin` section
  is role-gated and admits a regular user only to its own login screen — showing
  the link to everyone would be a dead end.
- **✅ `appIsAdmin` is a per-context flag, mirroring `appUsername`.** The web
  layout has no global render context — every page concern (`appUsername`,
  `chrome`, …) is passed explicitly into each view context. So `appIsAdmin: Bool`
  was added to all eight `/app` page contexts in `AppWebDTOs.swift` and populated
  from `user.role == .admin` at each `req.view.render` call in `AppWebController`,
  alongside the existing `appUsername`. A real `Bool` means the template uses
  `#if(appIsAdmin)` directly, avoiding the `#if(count(x) > 0)` Int-coercion gotcha
  codified in M11 (that only applies to counts, not booleans).
- **✅ The `/admin` nav shows a reciprocal "App" link to `/app`, always.** Unlike
  the `/app → /admin` direction, this one needs no gating: only admins ever reach
  the admin dashboard, and every admin also has a regular `/app` account (the two
  web UIs share the same user table), so the link is never a dead end. It is a
  plain `<a href="/app">App</a>` with no context flag.

---

## Appearance theme swatches respect dark mode

- **✅ Each swatch previews the colour for the active light/dark mode.** Every
  `AccentTheme` carries both a light and a dark hex (§7.6), but the appearance
  picker rendered each swatch with an inline `background` hardcoded to the light
  value (`ThemeOption.color = $0.light`), so in Dark Mode the circles showed the
  wrong (light-mode) colours while the rest of the page was dark. The swatch now
  switches with the page: `ThemeOption` carries both `light` and `dark`, the
  inline style sets `--swatch-light` / `--swatch-dark` custom properties only,
  and `.theme-swatch` resolves the background from them in CSS — defaulting to
  `--swatch-light`, overridden to `--swatch-dark` under `[data-theme="dark"]` and
  under `prefers-color-scheme: dark` in auto mode. This mirrors the three-way
  resolution already used for the injected `--accent` override, so the previews
  match the colour the app actually renders.

---

## Smart Views

- **✅ All conditions are ANDed.** A Smart View matches a bookmark only when *every*
  condition holds. There is no `OR`, no grouping, and no boolean-expression parser
  — AND covers the large majority of "saved query" use cases, and the absence of a
  query DSL keeps both the data model and the builder UI trivial. A user who needs
  an alternative just creates a second Smart View.
- **✅ Conditions stored as a JSON array of `{ type, value }` objects.** The
  `conditions` column is a single `.json` column holding an array of
  discriminated-union objects (`{ "type": "urlContains", "value": "youtube" }`).
  Adding a new condition type is a code-only change — no schema migration — and the
  flat `{ type, value }` shape (all values are strings; dates are ISO-8601,
  `isArchived` is `"true"`/`"false"`) is the same on the wire and in the DB, so the
  API response is a direct projection of the stored value. `SmartViewCondition` is a
  Swift `enum` whose `Codable` round-trips that shape; its `validated(type:value:)`
  factory is the single choke point that rejects unknown types, empty values, and
  unparseable dates/booleans with `422 validation_failed`.
- **⚠️ Conditions are wrapped in a single-object `SmartViewConditionList`, not a
  bare `[SmartViewCondition]` field.** Storing the array directly worked on the
  SQLite test DB but failed in production on PostgreSQL: Fluent's Postgres encoder
  serializes a top-level Swift array as `jsonb[]`, which the `jsonb` column rejects
  (`column "conditions" is of type jsonb but expression is of type jsonb[]`). SQLite
  has no array type, so it stored the same value as JSON text and the tests passed
  — a textbook SQLite-tests / Postgres-prod divergence the in-memory test DB can't
  catch. Wrapping the array in a one-field `Codable` struct makes Fluent emit a
  single `jsonb` document on both drivers; `SmartView.conditions` is a computed
  accessor over the stored wrapper, so call sites are unchanged. This keeps the
  already-created `jsonb` column valid — no ALTER migration needed. (Verified by
  running the backend against a real PostgreSQL 16, not just the SQLite test suite.)
- **✅ Text conditions reuse the portable case-insensitive `LIKE` helper.**
  `urlContains` / `titleContains` / `descriptionContains` use a new
  `QueryBuilder<Bookmark>.filterColumn(_:contains:)` that compares
  `lower(column) LIKE lower('%value%')` via a bound parameter — the same approach as
  the existing `filterFullText`, portable across SQLite (tests) and PostgreSQL
  (production). The `tag` condition reuses the bookmark list's exact prefix-match
  semantics (`tags_search` contains `|tag|` *or* `|tag/`), so a Smart View tag
  filter behaves identically to the sidebar tag filter (matches the tag and its
  descendants). Multiple conditions of the same type are allowed and ANDed — two
  `tag` conditions require both tags.
- **✅ `isArchived` overrides the default archived filter.** The bookmarks endpoint
  returns non-archived bookmarks unless the Smart View carries an `isArchived`
  condition, which then controls archived state entirely. On the web results page
  the archived toggle is hidden when an `isArchived` condition is present (the
  condition owns it) and works normally otherwise.
- **✅ No count in the sidebar.** Smart Views render in the bookmark-list sidebar
  (above the tag tree, below the time filters) as plain links with no count — a
  count would mean running each saved query on every page render. The user's Smart
  Views are loaded in one `.all()` call per render alongside the tag list; the
  dividers/section only appear when the user has at least one Smart View.
- **✅ Loaded per render, no cache.** Like the tag list, Smart Views are read fresh
  on each page render (one extra query). The data is small and per-user, so caching
  would add invalidation complexity for no meaningful gain.
- **✅ Management is a top-level nav item.** The create/edit/delete management page
  (`/app/smart-views`) is linked directly from the main nav (between Tags and
  Settings) rather than buried under Settings — Smart Views are a first-class
  browse/organize surface alongside Bookmarks and Tags, so the nav entry makes them
  discoverable. (Initially placed under Settings; promoted to the nav for
  discoverability.) The results page reuses the existing bookmark-list template (same sidebar, same
  pagination) with an `isSmartView` flag that swaps the search toolbar for a "Smart
  View" label. The condition builder is the same minimal-vanilla-JS pattern as the
  tag autocomplete and danger zone: rows cloned from a `<template>`, each row's
  type-select toggling between a text/date input and a Yes/No select (the inactive
  control is `disabled`, so exactly one value submits per row).
- **✅ The `tag` condition value reuses the bookmark forms' tag autocomplete.** The
  layout's autocomplete was refactored into a reusable `window.stashTagAutocomplete(
  input, known, opts)`; the bookmark fields call it in `multi` mode (comma-segment
  completion) and the Smart View condition value calls it in single mode (replaces
  the whole value), gated by an `enabled` callback so suggestions only appear while
  the row's type is `tag`. The form embeds the user's tags in a `data-known-tags`
  attribute (same zero-extra-request approach as the add/edit forms), so picking a
  tag never requires guessing.
- **✅ StashKit gains a `SmartViewRequestFactory` + DTOs only.** Following the M6
  thin-package rule, StashKit adds `SmartViewDTO` / `SmartViewConditionDTO`, a
  `SmartViewRequest` body, and the factory (list/create/get/update/delete/bookmarks)
  — no client state. `smart_view_not_found` maps to the existing `.notFound`
  `StashAPIError` case. No CLI or native-app surface was added this pass.
