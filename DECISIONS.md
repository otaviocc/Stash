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
- **✅ `auth/totp/disable` and `admin/users/:id/reset-totp` factories preceded
  their JSON API — now resolved.** These endpoints first shipped only on the web
  controllers (M11 / post-M11); StashKit defined
  `makeTOTPDisableRequest`/`makeResetTOTPRequest` at the PRD §9.2/§9.6 paths ahead
  of the backend (the task's factory list mandated them) so the client was ready.
  The backend has since exposed both on the JSON API at exactly those paths — see
  "2FA disable / reset land on the JSON API" below.
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
  the `RoundFaviconModifier` (16×16 icon, 4 pt corner radius) is implemented locally
  as instructed. It draws the icon on an **always-light (white) background** with
  a 1 pt inset (growing the chip to 18×18, the icon kept at 16×16) — some favicons are designed for white backdrops and look poor on
  the dark-mode surface, so the background is fixed light regardless of color
  scheme rather than following it.
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
  Untagged, then the tag list — flat at M10, since made a hierarchical tree at iPad
  parity, later flattened to an always-expanded indented tree; see "Native apps —
  hierarchical tag sidebar" and "Flat-indented (web-parity) tag tree") drives the
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
  Browser, Copy URL, Copy Markdown URL, Share…, Archive/Unarchive, Delete) is also
  shared; the same copy and share actions (Copy URL + Copy Markdown URL — the
  latter emits `[title](url)` — and Share…) also live in `BookmarkDetailView`'s
  actions section. Keyboard
  shortcuts wired: ⌘N (new), ⌘E (edit), ⌘R (refresh), ⌘⌫ (delete the open
  bookmark, with confirmation). ⌘F is left to the system search field rather
  than custom-bound.
- **✅ Esc dismisses the bookmark detail back to the list.** `BookmarkDetailView`
  carries a hidden, zero-opacity `Button("Back")` bound to
  `.keyboardShortcut(.cancelAction)` (Esc) that calls the same
  `@Environment(\.dismiss)` the delete path already uses — reusing the exact ⌘F
  "Find" idiom (`Button(…).keyboardShortcut(…).opacity(0).accessibilityHidden(true)`
  in a `.background`). `.cancelAction` rather than a raw `.escape` so layering is
  correct for free: when the edit sheet or the delete `confirmationDialog` is
  presented, that foremost presentation captures the cancel action and Esc
  dismisses *it* first; Esc only pops the detail when nothing is on top. The
  binding is applied uniformly — not `#if os(macOS)`-guarded — because it is inert
  where no Esc key physically exists: always live on macOS, and on iPadOS/iOS only
  when a hardware keyboard is attached (no on-screen Esc). The detail is the same
  shared view pushed onto a `NavigationStack` on every platform, so one `dismiss()`
  pops it everywhere.

  **Why a hidden button and not a "cleaner" API.** SwiftUI has no view-level "when
  this view is visible, run a closure on Esc" binding — `.keyboardShortcut` is
  deliberately *control*-bound, so to map a key to an action (rather than a visible
  control) you attach it to a `Button` and then suppress that button
  (`opacity(0)` keeps it in the hierarchy and interactive, unlike `.hidden()` /
  conditional removal; `accessibilityHidden(true)` keeps the phantom out of
  VoiceOver). It is a common, stable idiom (documented behavior only, no private
  API) rather than a bespoke hack — and it is the same shape already used for ⌘F.
  The two more "first-class" alternatives were both worse fits: `.onKeyPress(.escape)`
  is *focus-scoped*, so inside a `Form` of focusable rows it fires only when focus
  happens to sit in the subtree — unreliable, whereas `.keyboardShortcut` is active
  for the whole key window; and `Commands`/`CommandMenu` is the idiomatic macOS home
  for global shortcuts but is macOS-only and lives at app/scene altitude, wrong for
  a per-view, cross-platform "pop the current detail" action.
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
  `?tag=__untagged__` returns only tagless bookmarks. ⚠️ At the time, the filter
  *expression* was still written out in both controllers — only the sentinel
  constant was shared; this duplication is what let the API drift from the web UI
  in the first place. ✅ **Resolved** when the recency sentinels were added: the
  whole sentinel-plus-prefix filter now lives in one
  `QueryBuilder<Bookmark>.filterByTag(_:boundaries:)` helper that both controllers
  call, so there is no expression left to drift.
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
  (no extra query), and the count badge is hidden when 0 like the others.
  ✅ **The JSON API now honors these sentinels too** (see the app sidebar entry
  below) — both controllers route the `tag` query through one shared
  `QueryBuilder<Bookmark>.filterByTag(_:boundaries:)` helper, and
  `dateBoundaries(now:)` moved from `AppWebController` to `Bookmark` so the date
  math is also single-source. ⚠️
  Like "Untagged", the web filter banner renders "Filtered by tag Today", a slight
  wording mismatch carried over from the shared template path.
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

- **✅ No comments of any kind inside method/function bodies.** The code and
  tests are the documentation. Neither `//` nor `///` comments explaining *what*
  the code does belong inside a body; the code should be readable without them.
  All documentation lives at the declaration level. (Exception: the backend
  tests' `// Given` / `// When` / `// Then` structure markers, below.)
- **🔁 `///` doc comments allowed on any declaration** (supersedes the earlier
  "types only" rule). Doc comments are permitted — and idiomatic — on **types,
  properties, and methods/functions**, not just types. This matches SwiftFormat's
  `--doc-comments before-declarations`, which converts any comment placed before a
  declaration into a `///` doc comment, so a "types only" rule was never
  tooling-enforceable: a `//` written above a method is auto-upgraded to `///`.
  The rule now reflects what the formatter actually produces; documentation is
  written at the declaration level rather than inside bodies.
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
  `StashKit/README.md`, and later `Extension/README.md`) were deleted; the root
  `README.md` became a concise landing page that links into `Docs/`. The folder
  holds one guide per concern — `backend-build`, `backend-local`,
  `backend-docker`, `backend-docker-caddy`, `configuration`, `api`, `cli-build`,
  `mobile-build`, `stashkit`, `browser-extension`. `PRODUCT.md` and
  `DECISIONS.md` remain at the repo root.
- **✅ Convention: new user-facing docs go in `Docs/`, not a component README.**
  This is the standing rule — a new component or feature gets one guide in
  `Docs/` (linked from the root `README.md` table), never a `Component/README.md`.
  The browser extension followed this: it shipped with an `Extension/README.md`
  first, which was then folded into `Docs/browser-extension.md` and deleted to
  match every other component.
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
- **✅ `refreshCache` only mutates the lock-guarded snapshot, never
  `Application.storage`.** The cache holder is seeded by `loadAndCache` during
  `configure`, before the server accepts connections, so it always exists by the
  time a request can trigger a refresh. `refreshCache` therefore only calls
  `cache.update(...)` (which takes the `NSLock`); it does **not** write back into
  `Application.storage`, an unsynchronized dictionary that would data-race the
  concurrent `req.siteChrome()` reads if mutated at runtime. The earlier
  `else { storage[...] = … }` fallback was unreachable but encoded exactly that
  unsafe write, so it was removed — a missing holder now logs and leaves renders
  on the `.default` snapshot until the next boot rather than racing storage.
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

- **✅ A per-view match mode: `all` (AND) or `any` (OR).** Mirroring macOS Music's
  "Match all/any of the following rules", each Smart View carries a `match_mode`
  string (`all`/`any`, default `all`, validated at the boundary like condition
  types and `accentTheme` — no Fluent DB enum). `all` ANDs the conditions as
  top-level filters; `any` wraps them in a single `.group(.or)`. There is still no
  per-rule grouping or boolean-expression parser — one global combinator covers the
  vast majority of "saved query" use cases without a query DSL. Added via a separate
  `AddSmartViewMatchMode` migration (column with `default("all")`) so existing rows
  backfill to the prior AND behavior without an edit to the already-applied
  `CreateSmartViews`.
- **✅ The non-archived default is an outer AND in both modes.** `applyConditions`
  applies `isArchived == <default>` as a top-level filter unless an `isArchived`
  condition is present, *then* combines the rules (AND or OR). So `any` mode can't
  leak archived bookmarks just because one OR-branch happens to match — archived
  results still require an explicit `isArchived` rule. The match-mode + archived
  logic lives only in `SmartView.applyConditions(to:archivedDefault:)`; the web
  results handler passes its archived-toggle state as `archivedDefault` and the API
  uses the `false` default, so the two callers share one mechanism (this also
  retired the duplicated inline loop a prior review flagged).
- **✅ Conditions stored as a JSON array of `{ type, value }` objects.** The
  `conditions` column is a single `.json` column holding an array of
  discriminated-union objects (`{ "type": "urlContains", "value": "youtube" }`).
  Adding a new condition type is a code-only change — no schema migration — and the
  flat `{ type, value }` shape (all values are strings; dates are ISO-8601,
  `isArchived` is `"true"`/`"false"`) is the same on the wire and in the DB, so the
  API response is a direct projection of the stored value. `SmartViewCondition` is a
  Swift `enum` whose `Codable` round-trips that shape; its `validated(type:value:)`
  factory is the single choke point that rejects unknown types, empty values, and
  unparseable dates/booleans with `422 validation_failed`. Adding `hasTags` (a
  boolean condition: `true` = the bookmark has any tags, `false` = none) was exactly
  this code-only change — no migration, no StashKit change — and it reuses the
  derived `tags_search` column (`!= ""` / `== ""`, the same basis as the
  `__untagged__` filter) rather than introducing new storage.
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

---

## Smart View import / export

- **✅ Smart Views ride the existing Stash JSON envelope as an optional sibling node.** Rather than
  a new format or a separate file, the `stash-json` exporter/importer gained a `smartViews` array
  alongside `bookmarks` (`{ id, name, matchMode, conditions: [{type,value}], createdAt, updatedAt }`,
  the API wire shape). The node is **optional on import**, so older exports without it still import
  and the format `version` stays `"1"` — no version bump, fully backward-compatible (the decoder
  only reads keys it knows). One file, one upload, round-trips both.
- **✅ Dedup by name, mirroring bookmark dedup-by-URL.** A Smart View whose `name` already exists for
  the user is updated in place (matchMode + conditions overwritten); otherwise it is created. This
  makes re-import idempotent. `id`/`createdAt`/`updatedAt` are ignored on import, exactly as the
  bookmark importer ignores `id`/`updatedAt`.
- **✅ Validation is reused, not reimplemented.** The importer calls the existing
  `SmartViewController.validatedName` / `validatedMatchMode` / `validatedConditions` (and through
  them `SmartViewCondition.validated`), so an imported Smart View is held to exactly the same rules
  as one created via the API. A Smart View with an empty name or no valid conditions is **counted and
  reported** (`smartViewsSkipped` + an `errors` line), never thrown — the same parse-failure-vs-bad-
  record split bookmarks already use.
- **✅ `ImportResult` extended with defaulted counts.** Three new fields
  (`smartViewsImported`/`Updated`/`Skipped`) carry `= 0` defaults so the Anybox importer (bookmarks
  only) is untouched. The web summary banner shows the Smart View line only when the file carried any
  (a precomputed `hasSmartViews` Bool on `ImportSummaryContext`, dodging Leaf's `#if(count … )`
  Int-truthiness gotcha).
- **✅ CLI reaches parity over the public API.** `stash export` lists Smart Views via
  `SmartViewRequestFactory.makeListRequest()` and folds them into its local `ExportDocument`; `stash
  import` parses the `smartViews` node and submits each via create/update (matched by name, listing
  existing views once). Unlike the web importer with direct DB access, the CLI **cannot preserve a
  Smart View's `createdAt`** — the same accepted limitation already documented for bookmarks under M7.
- **✅ Per-record failures are reported; connectivity/auth failures abort the import.** A shared
  `CLIErrorReporter.abortsBatch(_:)` splits errors into per-record rejections (`validation_failed`,
  `duplicate_url`, `not_found`, `username_taken` → skip this record, record a reason) and everything
  else (auth, server, transport, unrecognized → rethrow, so `runCLI` prints the message and exits
  non-zero). Without this, a dropped session mid-import was silently counted as "skipped", making a
  recoverable failure look like bad data. Smart View skip reasons print after the summary (matching
  the web importer's per-record error lines); the same classifier was applied to the bookmark
  `submit` path so both halves of `stash import` behave consistently.

---

## Tags & Smart Views web UI — table layout and delete confirmation

- **✅ The Tag Browser now renders as a table mirroring the Smart Views management
  page.** The tag list was a `<ul class="tag-list">`; it became a `.card`-wrapped
  `<table>` with `Tag` / `Bookmarks` / `Actions` columns, so `/app/tags` and
  `/app/smart-views` read as one consistent surface. Rename was a `secondary`
  `<button>`; it is now an accent `<a>` matching the Smart Views `Edit` link (it
  still toggles the inline rename form — the only action that needs a text input —
  via `preventDefault()`). The now-unused `.tag-list` / `.tag-row*` rules were
  dropped from the shared `layout.leaf`; each page keeps its small action styles in
  a scoped `<style>` block.
- **✅ The Tag column absorbs the table's slack so the actions sit flush.** A table
  with only short cells (`Tag`, a count, two actions) stretches the last column and
  leaves a large gap after the Delete button — the Smart Views table doesn't show
  this because its wide `Conditions` column eats the slack. Fix is pure CSS:
  `.tag-table` sets the first column to `width: 100%` and `white-space: nowrap` on
  the rest, pinning the actions to their content width. No layout change to Smart
  Views, whose `Conditions` column already does this naturally.
- **✅ Delete switched from an inline-reveal form to a native `confirm()` dialog.**
  Both pages previously toggled a per-row confirmation form into view on Delete,
  which mutated the table in place and reflowed the row (visible "things out of
  place" while one row's form was open). Both now use `onsubmit="return
  confirm(…)"` on a small `inline` POST form — the exact pattern already used to
  delete a bookmark — so Delete never alters the table before submit. This removed
  the `.sv-delete-form` toggle script entirely from the Smart Views page and the
  delete half of the tag browser's toggle script; only the tag Rename reveal
  remains. The confirm copy is a static string (not interpolated with the tag name)
  to avoid breaking the JS string on tags containing quotes.

---

## Public landing page at `/`

- **✅ A server-rendered landing page now lives at the root path.** Before this,
  `/` returned a bare 404 — the only entry points were `/app` and `/admin`. The
  new page (PRD §1) is a product pitch reflecting the self-hosted, data-ownership
  philosophy: a hero ("Your bookmarks. Your server. Your data."), two CTA buttons
  (Sign in → `/app`, Admin → `/admin`, the latter visually secondary), and a 2×2
  feature grid (self-hosted, multi-platform, organised, multi-user) that
  collapses to a single column under 600px. It reuses `layout.leaf` wholesale: the
  nav header is gated on `adminUsername`/`appUsername`, neither of which is set for
  an anonymous visitor, so the layout degrades to `<main>` + footer with no change
  needed. All colours come from the existing CSS variables, so dark mode and the
  admin's accent theme apply for free. Per-page styles sit in a scoped `<style>`
  block in the template, matching the Tags/Smart Views convention. The CTAs point
  at `/app` and `/admin` rather than their `/login` sub-paths: both surfaces are
  session-protected, so an anonymous visitor is redirected to the right login page
  anyway, while a still-signed-in user lands straight on their content.
- **✅ The page touches no session — it renders the same for everyone, signed in
  or not.** An earlier revision tried to redirect a logged-in visitor to `/app` by
  reading the `stash_session` cookie at `/`. That backfired: the `stash_session`
  cookie is path-scoped to `/app` (see routes.swift), so a browser never sends it
  to `/`. Merely *reading* `req.session` there created a fresh empty session, and
  the sessions middleware then wrote a `Set-Cookie: stash_session=…; Path=/app`
  that **overwrote the visitor's real session cookie** — i.e. visiting `/` silently
  logged you out of `/app`. The redirect and the sessions middleware were removed
  from the landing route entirely; `LandingController` now does a pure render with
  no session access. The trade-off: a signed-in user who navigates to `/` sees the
  landing page instead of being bounced to `/app`. That was preferred over the
  alternative fix (widening the `stash_session` cookie path to `/`), which would
  have changed the session scope for the whole `/app` surface just to power a
  cosmetic redirect.
- **✅ `aboutText` is surfaced on the landing page as well as the footer.** When
  the admin has set an "About this instance" message (`SiteSettings.aboutText`,
  PRD §7.6), it renders in a `.card` between the hero and the features
  ("About this instance: …"); when empty/nil the section is omitted entirely. This
  is a deliberate dual use — the same text already appears in the shared footer via
  `chrome` — so the one admin-editable blurb does double duty as the landing
  page's instance description without adding a new settings field. The dedicated
  `LandingPageContext.aboutText` is populated from `chrome.aboutText` (which is
  already `nonEmpty`-filtered), so the Leaf `#if(aboutText)` test behaves correctly
  and never trips the empty-string-is-truthy gotcha (§21).
- **✅ Route placement.** The root route is registered after the `/app` frontend in
  `routes.swift` via `app.register(collection: LandingController())` — no group, no
  middleware. It is the sole unauthenticated web page besides the two login screens;
  no new tests beyond a throwaway Leaf smoke test (render + aboutText card — run
  then removed, per §19.6).
- **✅ Copy and styling refreshed to match the shipped product.** The original 2×2
  feature grid (self-hosted, multi-platform, organised, multi-user) had fallen behind:
  it never mentioned the CLI or browser extension as clients, nor 2FA, import/export,
  or theming. The grid is now **six cards** — *Self-hosted & private* (incl.
  self-hosted favicons), *Every platform* (iOS/macOS/web/CLI/browser extension),
  *Organised* (tags, search, Smart Views), *Secure by default* (TOTP + recovery
  codes), *Portable* (Anybox/Stash JSON import-export), and *Yours to theme*
  (Light/Dark/Auto + the admin accent theme). The hero subline now names every
  client. The styling moved into the scoped `landing.css` (per the §1903 split): an
  accent-tinted `color-mix` gradient hero panel, a decorative platform-badge row, and
  card hover polish (shadow + lift + accent top-border, disabled under
  `prefers-reduced-motion`). All still resolve from the existing CSS variables, so
  dark mode and the admin accent theme apply for free; the grid steps 3→2→1 columns at
  760px/520px. No controller or `LandingPageContext` change — the page still renders
  from `chrome` + `aboutText` only. Markdown URL copy was deliberately **not**
  advertised here: it is a native-app action, off-topic for the web landing page.
- **✅ API docs CTA added to the hero.** Now that the Swagger UI is served at
  `/docs.html` (see *OpenAPI specification*), the hero carries a third, secondary
  CTA — *API docs →* `/docs.html` — alongside *Sign in* and *Admin*. It is a
  same-tab static page like the other two CTAs, reuses the existing
  `.landing-cta a.secondary` style (the row already wraps, so no CSS change), and
  surfaces the machine-readable API surface to anyone evaluating a self-hosted
  instance without making them guess the URL.

---

## Browser Extension

A WebExtension (`Extension/`) that saves the current page to a Stash instance
from Firefox or Chrome (including Zen). It talks directly to the REST API
(`/api/v1/`) — **no backend, StashKit, or native-app changes**.

- **✅ Plain HTML + vanilla JS, no build step.** No npm, no bundler, no
  framework — the same philosophy as the server-rendered web UI (§13). The
  extension is small enough (a popup, an options page, a service worker) that a
  framework would add tooling and a build artifact for no real gain. All files
  load directly in the browser. The popup/options CSS copies the web UI's CSS
  variables (system font stack, the same light/dark palette) and resolves dark
  mode via `prefers-color-scheme`, so it reads as part of Stash without sharing
  any code with the Leaf templates.
- **✅ Manifest v3, one manifest for both browsers.** v3 is required by Chrome;
  Firefox supports it too. The background is declared with **both**
  `service_worker` (used by Chrome) **and** `scripts` (used by Firefox/Zen, which
  do not enable `background.service_worker` by default and reject a
  service-worker-only manifest with "background.service_worker is currently
  disabled. Add background.scripts."). Each engine uses the key it supports and
  ignores the other, so one `manifest.json` serves both without per-browser
  variants. No `type: "module"` — `background.js` has no ES imports, so a classic
  script is valid as both a Chrome service worker and a Firefox event-page
  script, and dropping the key avoids depending on module-background support
  (newer Firefox only).
- **✅ `background.js` owns all token storage and API calls.** The service worker
  is the only place that touches `chrome.storage.local` for tokens; the popup and
  options page communicate with it over `chrome.runtime.sendMessage` (a small
  message API: `login`, `verify2FA`, `logout`, `getStatus`, `apiCall`). This
  keeps token logic in one place — login, the silent-refresh window, the
  refresh-on-401 retry, and logout all live in the worker — and means the popup
  never needs storage permissions or its own copy of the refresh logic. It
  mirrors the app's `AuthRepository.refreshIfNeeded()` centralization (§16) and
  the CLI's `CLIRuntime` proactive refresh (M7).
- **✅ JWT `exp` decoded by hand, 60-second skew.** Like the CLI's `JWTDecoder`
  and the app's `TokenManager`, the worker base64url-decodes the access token's
  payload and reads `exp`, refreshing when within 60 s of expiry (and once more
  on a `401`, after which it clears the session). No JWT library — `atob` in the
  service worker is enough.
- **✅ 2FA handled inline on the settings page.** `POST /api/v1/auth/login`
  returns either a token pair or `{ requires2FA, tempToken }`, both as HTTP 200
  (§8.2) — the worker switches on the body shape exactly as the CLI and app do.
  When 2FA is required the options page reveals a code field and calls
  `verify2FA` (→ `/api/v1/auth/totp`, with a "use a recovery code" toggle →
  `/api/v1/auth/recovery`). The extension must work for users who have 2FA
  enabled, so this can't be deferred. After a 2FA login the username isn't known
  locally, so it is resolved via `GET /api/v1/me` for the status line.
- **✅ `host_permissions: ["<all_urls>"]`.** A self-hosted tool's server URL is
  user-supplied and unknown at build time (a LAN IP, a `.local` host, a public
  domain), so there is no narrower host pattern to request — both engines require
  this for cross-origin fetch from the extension.
- **✅ URL field is read-only.** The extension saves the page you are on; the URL
  is pre-filled from the active tab and shown read-only (with a ↗ link-out).
  Making it editable would mean the user has to navigate away from the page they
  want to save, which defeats the purpose. Title, description, and tags are
  editable; "Fetch metadata" (`POST /api/v1/metadata`) fills only the empty
  fields so it never clobbers what the user typed. Save sends
  `fetchMetadata: false` — the extension drives metadata explicitly.
- **✅ No undo and no "save another" in the popup.** The popup lifecycle is too
  short for the timer-based undo the Share Extensions use (M9/M10) — closing the
  popup would cancel the timer. Instead: save → confirmation (a single View
  bookmark link, auto-closing after 3 s) → done. There is deliberately no "save
  another" either: the extension saves the page you are on, so once that tab is
  saved there is nothing more to add for it. Duplicate URLs surface inline as
  "Already saved" with a link to the existing bookmark (the `409`'s `existingID`
  → `/app/bookmarks/:id`); deletion is left to the web UI or a native app.
- **✅ Tag autocomplete reuses the web UI's per-segment prefix rule.** The popup
  fetches `GET /api/v1/tags` on open and offers suggestion chips matching the
  comma-segment under the cursor, where a fragment matches any `/`-delimited
  segment that starts with it (so `music` finds `kind/music-gear`) — the same
  behavior as the Leaf forms' `data-known-tags` autocomplete (§13).
- **✅ Icons generated programmatically.** `icons/icon.svg` is the master vector
  (the Stash bookmark ribbon, deep indigo `#231468`); `icons/generate-icons.py`
  rasterizes it to the four manifest sizes (16/32/48/128) with Pillow only, so
  the PNGs are reproducible from source rather than committed opaquely.
- **✅ "Build" = package, not compile.** With no build step, the only build-time
  task is zipping the folder for store submission. An `Extension/Makefile`
  (mirroring `Backend/Makefile`'s `## help` style) wraps it: `lint`, `icons`,
  `package` (→ `dist/stash-extension-<version>.zip`, named from the manifest
  version), and `clean`. The core targets use only `zip`/`python3`/`node` — no
  npm or bundler, keeping the no-build-step promise. `package` zips just the
  runtime files, excluding the Makefile and the icon source/generator.
  `dist/` is gitignored.
- **✅ `lint` degrades gracefully, no npm required.** Mozilla's `web-ext` is the
  proper extension linter but it is an npm tool, which the project deliberately
  avoids. `make lint` uses `web-ext` *if it happens to be installed*, otherwise
  falls back to dependency-free checks (manifest is valid JSON; the three JS
  files pass `node --check`). This is the one automated guard that matters, since
  there is no compiler to catch a malformed manifest or a JS typo.
- **✅ CI validates, release packages.** A small `extension` job in `ci.yml` runs
  `make lint` on every push/PR (python3 + node are preinstalled on the ubuntu
  runner; no npm step added). `release.yml` runs `make package` on a `v*.*.*` tag
  and attaches `Extension/dist/*.zip` to the GitHub Release alongside
  `docker-compose.yml`. The extension's manifest version is independent of the
  image semver tag, so the attached zip reflects the extension's own version.

---

## Web CSS and JS extracted to static assets

- **🔁 CSS moved out of the Leaf templates into static `.css` files served by
  `FileMiddleware`.** Until now every style lived in `<style>` blocks: one large
  block in `layout.leaf` (the shared design system + theme variables) plus
  per-page blocks in `landing.leaf`, `app-tags.leaf`, `app-smart-views.leaf`, and
  `app-smart-view-form.leaf` (the "scoped `<style>` block" convention noted under
  *Public landing page* and *Tags & Smart Views web UI*, now superseded). The
  shared block became `Public/css/stash.css`; each per-page block became its own
  file (`landing.css`, `tags.css`, `smart-views.css`, `smart-view-form.css`).
  `FileMiddleware(publicDirectory:)` is registered once in `configure.swift`
  (after `StashErrorMiddleware`); it falls through to the router when no file
  matches, so the API and web routes are untouched. The Dockerfile staging step
  now copies `Public/` next to `Resources/`.
- **✅ Shared CSS linked in `layout.leaf`'s `<head>`; per-page CSS via an
  `#import("css")` slot.** The layout carries `<link rel="stylesheet"
  href="/css/stash.css">` plus an `#import("css")` placeholder in `<head>`. A page
  that needs extra styles provides them with an `#export("css"): <link …>
  #endexport` sibling of its `#export("content")`. Pages without that export
  render nothing there — LeafKit's `ignoreUnfoundImports` defaults to `true`, so
  an unmatched `#import` is dropped silently rather than erroring (verified in the
  leaf-kit source before relying on it). No layout edits are needed per page.
- **✅ The accent-theme override stays inline.** The second `<style>` block in
  `layout.leaf` injects `--accent` from the `SiteSettings` cache
  (`#(chrome.accentLight)` / `#(chrome.accentDark)`) and is therefore
  Leaf-templated per request — it can't be a static file, so it remains inline,
  immediately after the `stash.css` link so it overrides the defaults. The
  flash-prevention `<script>` (§13) likewise stays inline (it must run before
  first paint).
- **🔁 The inline `<script>` blocks moved to `Public/js/` the same way.** Every
  page's JavaScript was inline: the shared tag-autocomplete (`stashTagAutocomplete`
  + the `data-known-tags` auto-wiring, §13) lived at the end of `layout.leaf`'s
  `<body>`; per-page scripts lived in `app-bookmarks` (the `/` search shortcut),
  `app-settings` (delete-all reveal/confirm), `app-tags` (rename-row toggle),
  `app-smart-view-form` (the condition builder), and `appearance` (the about-text
  char counter). None referenced Leaf variables — they all read DOM attributes or
  query the DOM — so each became a static file (`tag-autocomplete.js`,
  `bookmarks.js`, `settings.js`, `tags.js`, `smart-view-form.js`, `appearance.js`)
  served by the same `FileMiddleware`. The shared `tag-autocomplete.js` is linked
  once in `layout.leaf`'s `<head>`; per-page scripts use an `#import("scripts")`
  slot fed by an `#export("scripts")` sibling, mirroring the `css` slot.
- **✅ All extracted scripts are `defer`red; the theme-flash script stays inline.**
  External scripts use `<script defer …>` so they execute after parse, in document
  order, before `DOMContentLoaded`. The shared `tag-autocomplete.js` link precedes
  the `#import("scripts")` slot in `<head>`, so it always runs before any page
  script that depends on `window.stashTagAutocomplete` (e.g. the Smart View form).
  The one script that must **not** be deferred is `layout.leaf`'s
  flash-prevention snippet (§13): it sets `data-theme` from the cookie before first
  paint, so it stays inline at the top of `<head>` — externalizing or deferring it
  would reintroduce the wrong-theme flash. Inline event-handler attributes
  (`onsubmit="return confirm(…)"`) were left as-is; they are markup, not script
  blocks.
- **✅ Verified.** `swift build` clean; a throwaway smoke test (run then removed,
  per §19.6) confirmed `GET /css/stash.css` returns `200 text/css` and
  `GET /js/tag-autocomplete.js` returns `200` JavaScript, that the landing page's
  `<head>` links the static assets (no residual inline `<style>`/`<script>`
  definitions), and that the flash-prevention script still precedes the deferred
  shared script in head order.

## Favicon Caching

- **✅ Cached per domain, not per bookmark or per user.** Favicons belong to a
  domain, not to a private collection, so one `FaviconCache` row keyed by a
  unique, lowercased, `www.`-stripped `domain` is shared across every user and
  every bookmark on that host. A new bookmark for any URL on `github.com` reuses
  the existing image with no fetch. The practical win: the cache fills in
  proportion to **unique domains**, not bookmark count, which scales far better
  for a heavy collection. `DomainExtractor` parses with `URLComponents` (the same
  parser `Bookmark.validatedURL` uses, so a URL that validates resolves a
  consistent host) and **keeps an explicit port** in the key (`192.168.1.5:8080`)
  — without it, two services on one LAN host (the documented `http://192.168.1.x:8080`
  use case) would collide on one row and show each other's icon.
- **✅ Three-tier fetch, declared icon first.** `FaviconFetcher.fetchAndCache`
  tries, in order: the page's declared `<link rel="icon">` (handed in from the
  metadata fetch that already ran at bookmark creation), then a `/favicon.ico`
  guess, then Google's `s2/favicons?sz=64&domain=` service as a last resort. This
  mirrors the order the macOS app's `FaviconView` reaches for conceptually, now
  centralized server-side. The `/favicon.ico` guess is built from the bookmark's
  **origin** (`scheme://host[:port]`, derived by `DomainExtractor.origin` and
  threaded through `enqueue(forURL:)`) rather than a hardcoded `https://` — an
  http-only LAN box would never answer an https probe. The declared-icon URL is
  an optional parameter, so the manual-refresh path — which has no page HTML and
  no origin in hand — falls back to `https://<domain>/favicon.ico`.
- **✅ Stored as a binary column, not a filesystem volume.** `image_data` is
  `bytea` on Postgres / BLOB on SQLite. One database volume to back up, no extra
  Docker volume to configure, acceptable because favicons are tiny — anything over
  **100KB** is rejected as "not a favicon" and stored as `failed`. A
  `Content-Length` header over the cap is rejected **before** the body is read;
  a chunked response without one is still bounded by the post-read byte count plus
  the 5-second read timeout. The `Content-Type` must start with `image/` **and**
  must not be SVG: `image/svg+xml` is refused because it is active content, and
  the serve endpoint returns favicon bytes from the Stash origin — an SVG with an
  embedded `<script>` opened directly would execute in that origin. The serve
  response also carries `X-Content-Type-Options: nosniff` as defense in depth so a
  mistyped `image/*` body can't be MIME-sniffed into markup.
- **✅ Fetch-once, manual-refresh-only.** A favicon is fetched exactly once, when
  its domain is first encountered, and **never** automatically re-fetched — no
  background polling, no scheduled refresh, no per-render staleness check. A site
  changing its icon is rare enough that a user-triggered
  `POST /api/v1/favicons/:domain/refresh` (which deletes the row and re-fetches)
  is sufficient. Refresh is available to **any** active user, since favicons are
  shared rather than privileged.
- **✅ Detached, non-blocking, deduped via the unique index.** The fetch runs in a
  `Task.detached` kicked off after the bookmark save responds, so it never blocks
  creation (the same non-blocking philosophy as metadata fetching). Both create
  controllers and the refresh endpoints funnel through one
  `FaviconFetcher.enqueue(forURL:)` / `refresh(domain:)` pair so the URL→domain→
  enqueue policy lives in a single place. `fetchAndCache` guards against duplicate
  concurrent fetches for a brand-new domain by **inserting a `pending` row first**;
  the `unique(on: "domain")` index makes the first writer win, and the insert
  `catch` is **narrowed to `DatabaseError.isConstraintFailure`** (skip silently —
  that is the dedup) while any other insert error is logged, so a transient DB
  failure is no longer mistaken for "already in flight" and silently dropped. The
  terminal `save` is likewise wrapped: on failure it logs and best-effort deletes
  the row, so a failed write can't strand a permanent `pending` row that `serve`
  would 404 forever (the unique index would otherwise block every future re-fetch).
  This dedup is why two bookmarks on the same domain produce one row and one fetch.
- **✅ `GET /api/v1/favicons/:domain` is unauthenticated.** Favicons are not
  sensitive, and `<img>` tags can't easily attach Bearer tokens, so the serve
  endpoint is open. A `cached` row returns the bytes with
  `Cache-Control: public, max-age=2592000, immutable` (30 days) to push caching
  out to the browser too; `failed`/`pending`/missing all return `404`, which the
  web UI handles with an `onerror` handler that hides the `<img>` — graceful
  degradation to no icon, never a broken-image glyph.
- **✅ Bookmark `faviconURL` is no longer written, but the column stays.** New
  bookmarks leave `favicon_url` `nil`; the web UI resolves favicons by domain at
  render time instead (`AppBookmarkRow.faviconDomain`, computed via
  `DomainExtractor`). Dropping the column would be a destructive migration for no
  benefit this session, so existing values are simply left untouched and unread by
  the web UI. The web row DTO's old `faviconURL` field was removed once nothing
  read it, so the row carries only `faviconDomain`.
- **✅ Imports backfill favicons.** The import path is web-only (the CLI imports
  over the public API, where `BookmarkController.create` already enqueues), so a
  successful web import calls `FaviconFetcher.enqueueBackfill(forUser:)`. That
  spawns **one** detached task that walks the user's bookmark URLs, dedupes to
  distinct domains, and calls `fetchAndCache` for each **sequentially**. A single
  serial sweep — rather than one detached task per bookmark — bounds the outbound
  fetch concurrency a bulk import would otherwise unleash, and the per-domain
  `fetchAndCache` dedup means already-cached domains cost one rejected insert and
  no HTTP. The sweep covers every domain the user owns, so re-importing also heals
  any domain that previously failed or was never fetched.
- **⚠️ No rate limiting on the manual refresh endpoint.** It could be used to
  hammer a domain's server or Google's service repeatedly. Accepted for a
  self-hosted single/small-team tool; flagged here for future hardening if abuse
  ever becomes a concern.
- **⚠️ The detached fetch is skipped under the `.testing` environment.**
  `FaviconFetcher.enqueue` returns early when `app.environment == .testing` so the
  test suite never makes real network calls from the create/refresh paths (the
  in-memory test app has no mock HTTP client wired into `app.client`). The fetcher
  logic itself is exercised directly against a `MockClient` `Client` conformance
  — including the three-tier order, content-type/size rejection, the failure path,
  and the same-domain dedupe — so coverage doesn't depend on the detached path.
- **✅ Native apps moved onto the cached endpoint.** iOS/macOS `FaviconView` now
  loads `GET <serverURL>/api/v1/favicons/:domain` (the unauthenticated, browser-
  cacheable route) instead of hitting Google directly. It reads `serverURL` from
  the `AppSettings` already in the SwiftUI environment, and the domain comes from
  a `Bookmark.faviconDomain` computed property that **mirrors the backend's
  `DomainExtractor`** (lowercased host, `www.` stripped, port kept) so the client
  produces the exact cache key the server stored. A 404 (uncached/failed domain)
  falls through `AsyncImage` to the existing `link` placeholder. The normalization
  is duplicated in Swift on both sides because no module spans the backend and the
  app (StashKit, the shared layer, is deliberately logic-free) — the property
  carries a comment pointing at the server source of truth.
- **✅ Favicons render on an always-light backdrop.** Both the native
  `RoundFaviconModifier` and the web `.favicon` CSS draw the icon over a fixed
  white background regardless of color scheme — many favicons are designed for
  white backgrounds and look poor on the dark-mode surface, so the chip stays
  light in both modes rather than following the theme. The icon keeps its nominal
  16×16 size and a 1 px inset grows the chip to 18×18 (the app re-frames after the
  background; the web CSS uses `box-sizing: content-box`) — earlier the inset ate
  into the icon, shrinking it.
- **✅ Verified.** Backend: `swift build` clean, `swift test --no-parallel` green
  (133 tests incl. 23 favicon tests across domain extraction, the fetcher, the
  per-domain import backfill, and the serve/refresh endpoints). Apps: `Stash`
  builds for both iOS and macOS. All: `swiftformat . --lint` idempotent and
  `swiftlint lint` reports 0 violations.

---

## macOS Share Extension — three platform-specific fixes

The Share Extension worked on iOS but failed on macOS, always landing on the
"Sign In to Stash" screen even with a signed-in app. Three separate, macOS-only
defects were stacked behind that one symptom — each masked the next, so they
were found and fixed in sequence. iOS was never affected by any of them.

- **✅ Keychain sharing needs `kSecUseDataProtectionKeychain` on macOS.**
  `KeychainStore` shares the token pair with the extension via an App-Group
  access group (`kSecAttrAccessGroup`). On iOS that works because the
  data-protection keychain is the *only* keychain; on macOS the default is the
  legacy file-based keychain, which does **not** honor App-Group access-group
  sharing — so the extension's read returned `errSecItemNotFound` and
  `tokenManager.refreshToken` was `nil`. Adding `kSecUseDataProtectionKeychain:
  true` to every query opts both processes into the modern keychain on macOS
  (no-op on iOS, where it is already the default), so the extension reads the
  tokens the app wrote. The `application-groups` entitlement already authorizes
  the access group; **no `keychain-access-groups` entitlement is required**.
  One-time cost: tokens previously written to the legacy keychain become
  invisible, so existing users sign in once more after this change. Accepted for
  a self-hosted app.
- **✅ macOS Safari delivers `public.url` as `Data`/`String`, not `NSURL`.**
  Even with auth fixed, the screen persisted because `bootstrap()` falls back to
  the *same* `.signedOut` screen when `SharedItemLoader.loadURL` returns `nil`
  (the screen conflates "not signed in" with "no shareable URL"). The attachment
  *was* a `public.url` provider, but `provider.loadItem(...)` on macOS returns
  the URL as `Data` (or a string), so the old `item as? URL` cast failed where
  on iOS it succeeds (iOS hands back an `NSURL`). `SharedItemLoader.coerceURL`
  now coerces `URL`/`String`/`Data` (the `URL` arm also catches the bridged
  `NSURL`), keeping iOS unchanged. It is `nonisolated` so it runs synchronously
  inside `loadItem`'s off-actor completion handler without sending the
  non-`Sendable` item across the `@MainActor` boundary.
- **✅ Toolbar actions don't render in the extension's hosting controller on
  macOS.** With the URL loading, the form appeared but had no Save/Cancel — the
  shared `AddBookmarkView` puts them in a `NavigationStack` `.toolbar`
  (`.cancellationAction`/`.confirmationAction`), which the chrome-less
  `NSHostingController` in the macOS share popover renders nowhere. The fix adds
  a macOS-only bottom action bar via `.safeAreaInset(edge: .bottom)`, gated by a
  new `usesInlineActionBar` flag (default `false`). Only the extension passes
  `true`; the app's `AddBookmarkSheet` keeps its working toolbar buttons and the
  `#if os(macOS)` guard keeps iOS on the toolbar. The flag — rather than a blanket
  `#if os(macOS)` — is deliberate: the app's normal `.sheet` *does* render the
  toolbar on macOS, so an unconditional bar would double the buttons there.
- **✅ Verified.** Confirmed end-to-end via Safari → Share → Stash on macOS:
  signs in from the shared session, extracts the page URL, and saves with the
  inline Save button. Temporary on-screen diagnostics used to pinpoint the three
  defects were removed before commit. iOS share flow unchanged. Style: American
  English, `///` on types only, no inline comments.

---

## Bookmark detail — consistent macOS Form action buttons

On the macOS bookmark detail page the three action rows rendered with mismatched
styles: "Open in Browser" (a `Link`) appeared as a borderless row in macOS's
native system link blue, while "Archive" and "Delete" (`Button`s) picked up
macOS's default bordered push-button chrome — a grey rounded rectangle sitting
inside the grouped `Form` row. iOS was unaffected: a grouped `Form` there renders
`Link` and `Button` rows identically (full-width, tinted, whole-row tappable).

- **✅ All three rows are `Button`s sharing a macOS-only `formButtonRowStyle()`
  helper.** The first attempt — keep the `Link` and restyle the two `Button`s to
  match it — failed: macOS renders `Link` in its **native system link colour**,
  which is not the app accent and cannot be overridden by `foregroundStyle`. So
  "Open in Browser" was converted to a `Button` driving `@Environment(\.openURL)`
  too, making all three the same control type. The helper (in `PlatformModifiers`)
  applies `buttonStyle(.plain)`, a full-width leading frame,
  `contentShape(Rectangle())` (whole-row tappable), and an explicit colour
  (`Color.accentColor`, or `.red` when `isDestructive: true`) since `.plain`
  otherwise drops to the primary label colour. It is a no-op on iOS, where the
  grouped form already renders buttons this way — keeping the shared
  `BookmarkDetailView` as plain SwiftUI with the platform divergence concentrated
  in `PlatformModifiers`, per the M10 convention. (The separate URL-display
  `Link` showing the bookmark's address is unchanged — only the action row
  moved.) Verified: the macOS app builds, `swiftformat --lint` and `swiftlint
  lint` are clean.

---

## iOS account settings — password change + 2FA at macOS parity

`AccountSettingsView` (change password, enrol / disable two-factor) shipped with
the macOS Settings window in M10 but was wrapped entirely in `#if os(macOS)`, so
the iOS app's `SettingsView` was only Server URL + Sign Out. A parity audit across
the clients flagged it as the highest-impact native gap — iOS users could not
change their password or manage 2FA from the app at all, only from the web `/app`
or macOS.

- **✅ Un-gated the existing screen rather than writing a new one.** Every
  dependency was already cross-platform: `AuthRepository`'s `changePassword` /
  `beginTOTPSetup` / `completeTOTPSetup` / `disableTOTP` / `currentUser`, the
  `TOTPSetup` model (`Common/Models`), and crucially `QRCodeView`, which renders a
  `CGImage` via `CIContext` (no `UIImage`/`NSImage`), so the enrolment QR works on
  iOS unchanged. Removing the `#if os(macOS)` wrapper from `AccountSettingsView`
  and `TwoFactorEnrollView` was the bulk of the change.
- **✅ Only window chrome stayed platform-specific.** The macOS-only bits — the
  form's outer `.padding()` and the enrolment sheet's fixed
  `.frame(width: 380, height: 460)` — moved behind a shared `settingsChromeStyle()`
  (in `PlatformModifiers`) and a private `enrollSheetSize()` `View` helper
  (`#if os(macOS)`, no-op on iOS), keeping the divergence at the edges per the M10
  convention. `settingsChromeStyle()` is shared because the **Smart Views** tab
  (whose `SmartViewManagementView` is a `List`, not a grouped `Form`) needs the same
  macOS padding to line up with the General and Account tabs — without it the tab
  sat flush against the settings-window edges while the others were inset. The two
  TOTP code fields gained `.oneTimeCodeFieldStyle()` (from `PlatformModifiers`) for
  an iOS numeric keyboard; it is already a no-op on macOS.
- **✅ Entry points: a push on iPhone, a sheet on iPad.** iPhone's `SettingsView`
  (inside the tab's `NavigationStack`) gains an Account `NavigationLink`. The
  **iPad** `SidebarSplitView` previously had *no* Settings surface at all — not
  even Sign Out — so it gains a sidebar toolbar gear that presents `SettingsView`
  in a sheet, closing that gap too.
- **✅ Verified.** Both platforms build (iOS Simulator + macOS), `swiftformat
  --lint` idempotent, `swiftlint lint` 0 violations. Style: American English,
  `///` on types only, no inline comments.

---

## Native apps — hierarchical tag sidebar (iOS + macOS)

The web sidebar had a nice nested tag tree (a Views section over a hierarchical,
indented tag tree); the native apps showed a **flat** tag list (iPhone Tags tab,
iPad sidebar, macOS sidebar) with at most an "All"/"Untagged" entry. This brought
the apps to web parity.

- **✅ Tree built client-side, ported from the web's `buildSidebar`.** StashKit's
  `GET /api/v1/tags` returns the flat `[{name, count}]` list (no tree endpoint), so
  `[Tag].hierarchy() -> [TagNode]` (in `Common/Models/Tag.swift`, beside the
  existing per-segment `autocomplete`) reproduces the server algorithm: every
  `/`-delimited ancestor becomes a node, **synthetic parents** that exist only to
  nest children carry no count, and children are alphabetical at each level. The
  one shape difference from the web's flattened `[SidebarTag]` (which carries a
  `depth` for CSS indentation) is that `TagNode` is **genuinely nested**
  (`children: [TagNode]?`) — SwiftUI's `OutlineGroup` wants a recursive structure,
  not a pre-flattened one.
- **🔁 Collapsible, not flat-indented (the deliberate divergence from web).**
  *Superseded by "Flat-indented (web-parity) tag tree".* The web is always-expanded with
  `padding-left: calc(depth * 0.9rem)`; the apps originally used
  `OutlineGroup(children: \.children)` so parents expand/collapse with native
  disclosure triangles. Chosen at the time over a faithful flat-indent port because it
  read as native and composed with `List(selection:)` and `NavigationLink` leaves for
  free — but collapsed-by-default meant the whole list was never visible and the
  picker's search was undercut, so this was later reversed to the flat-indent web port.
- **✅ `count: Int?`, nil for synthetic parents.** Modeling the hidden count as
  `nil` rather than `0 + "hide when zero"` both reads cleaner (`if let count`) and
  sidesteps SwiftLint's `empty_count` rule, which fires on any `.count > 0`.
- **✅ One shared row, three call sites.** `TagTreeLabel` (label + optional count)
  is reused by the iPhone `TagBrowserView`, the iPad `SidebarSplitView`, and the
  macOS `MacContentView`. Each surface keeps its own `OutlineGroup` wrapper because
  selection (sidebars) vs. navigation (Tags tab) differ.
- **✅ Full Views parity required a backend change.** The web Views are All /
  Untagged / Today / This Week, but the **JSON API only honored `__untagged__`** —
  `__today__`/`__this_week__` were web-frontend-only (they had been deliberately
  left out of the API as web conveniences). To expose Today/This Week in the apps,
  the `tag`-query filter (sentinels + the hierarchical prefix match) was extracted
  into one shared `QueryBuilder<Bookmark>.filterByTag(_:boundaries:)` that both
  `BookmarkController.list` and `AppWebController` call — no duplicated filter
  expression to drift (it had drifted once before; see the Tag-sidebar section).
  `dateBoundaries(now:)` likewise moved up to `Bookmark` (Monday week start, server
  timezone). A `BookmarkTests` case backdates a bookmark and asserts
  `?tag=__today__` / `?tag=__this_week__` filter correctly.
- **✅ Sentinel constants single-sourced in StashKit.** The three `tag` sentinels
  live on `BookmarkListQuery` (`untaggedTag` already existed; `todayTag`/
  `thisWeekTag` were added beside it) and the app references those — rather than
  re-declaring the `"__untagged__"` literal on the app's `Bookmark` model.
  `BookmarkListView` maps each sentinel to a friendly title and empty-state message.
  (The backend keeps its own `Bookmark` sentinels — a separate package that can't
  depend on StashKit; the wire values are the shared contract.)
- **✅ Tree cached on the repository, not rebuilt per redraw.** `[Tag].hierarchy()`
  (Set + dict + recursion + per-level sort) is computed once in
  `TagRepository.performLoad` and stored as `tagHierarchy`; the three sidebars read
  the cached value. Calling `hierarchy()` inline in a view body rebuilt the whole
  tree on every body evaluation — i.e. on every sidebar selection tap.
- **✅ Verified.** Both platforms build (iOS Simulator + macOS), full backend suite
  green (134 tests, incl. the new recency case), all three components
  `swiftformat --lint` idempotent and `swiftlint lint` 0 violations.

---

## Smart Views on the CLI and native apps (consumption-only)

Smart Views existed on the backend, in StashKit, and on the web (M12). This pass
brought them to the `stash` CLI and the iOS/macOS apps as a **consumption-only**
first step — list Smart Views and open their live results — deliberately deferring
create/edit to a later step (users who want to author a Smart View do it on the
web, or round-trip it through Stash JSON import/export, which already carries
Smart Views). No backend or StashKit change was needed: `SmartViewRequestFactory`
(`makeListRequest` / `makeBookmarksRequest(id:page:perPage:)`) and the DTOs were
already in place from M12.

- **✅ CLI: a `smart-views` group, two read subcommands.** `stash smart-views`
  (default subcommand `list`) prints a table — NAME, MATCH (`all`/`any`), a
  `type=value` CONDITIONS summary, and the **full** UUID last (mirroring
  `usersTable`, not the truncated bookmark table, because the id is the input to
  the next command). `stash smart-views bookmarks <id>` runs the saved query via
  `makeBookmarksRequest` and reuses `OutputFormatter.bookmarksTable` / the `--json`
  page shape, so a Smart View's results look exactly like `stash list`. The id is
  validated locally with the shared `requireUUID`; a foreign/missing view surfaces
  the server's `Not found.` Both honor `--json`. No top-level alias (unlike
  bookmarks) — `smart-views` is a less-frequent surface, so it stays under its
  group.
- **✅ App: a `SmartViewRepository` mirroring `TagRepository`.** Smart Views are a
  small, per-user list browsed from the sidebar — not a paginated query — so the
  repository is a shared `@Observable` singleton on `AppEnvironment` that loads
  once and caches (`load`/`reload`/`reset`), reset on sign-out alongside the tag
  cache. `SmartView` / `SmartViewCondition` domain models map from the DTOs in
  `Common/` (compiled into both app and extension targets, consistent with the
  other models), though the extension does not use them.
- **✅ `BookmarkListView` reused via a `BookmarkListSource`, not a second list
  screen.** Rather than duplicate the list (rows, pagination, context menu, detail
  navigation, empty state), the existing view gained a `source` —
  `.tag(String?)` or `.smartView(SmartView)` — with two initializers
  (`init(tag:)` is unchanged, so every existing call site is untouched). In Smart
  View mode the title is the view's name, and the search field, archived toggle,
  and add button are hidden (the `:id/bookmarks` endpoint takes no `q`/archived,
  and adding a bookmark to a saved query is meaningless). `BookmarkRepository`
  gained a private `Source` enum (`.query` / `.smartView(UUID)`) stored so
  `loadNextPage()` re-fetches the right endpoint; `fetch(page:)` switches on it.
  The create/archive list-mutation guards that compared against the query's
  `archived` flag now read a `displaysArchived` computed value (a Smart View
  displays non-archived by default), so an archived bookmark still drops out of a
  Smart View list.
- **✅ Sidebars gained an optional Smart Views section.** The iPad
  (`SidebarSplitView`), macOS (`MacContentView`), and iPhone (`TagBrowserView`)
  sidebars show a **Smart Views** section between Views and Tags, only when the
  user has at least one (matching the web's "section appears only when non-empty"
  rule and its no-count choice). The two `List(selection:)` sidebars added a
  `.smartView(SmartView)` case to their selection enum and branch the detail
  between `BookmarkListView(tag:)` and `BookmarkListView(smartView:)`; the iPhone
  Tags tab uses a `NavigationLink` to the Smart View list. Icon:
  `line.3.horizontal.decrease.circle` (a saved-filter glyph), the native stand-in
  for the web's `⊞`.
- **✅ Search field made conditional via a small `SearchableIfNeeded`
  `ViewModifier`.** `.searchable` can't be toggled in place, so the search field
  (and its ⌘F shortcut) is applied through a modifier that no-ops in Smart View
  mode — keeping one list body rather than forking it.
- **✅ Verified.** CLI built and exercised live (`smart-views list` and
  `smart-views bookmarks <id>` against a running backend); iOS Simulator and macOS
  apps build clean; all three components `swiftformat --lint` idempotent and
  `swiftlint lint` 0 violations. No app/CLI unit tests by design (§19.6).

---

## Smart View create / edit / delete in the native apps

The previous pass made Smart Views consumption-only on the apps. This pass adds
authoring (create / edit / delete) to iOS and macOS. The CLI stays consumption-only
(a condition-builder CLI is lower value — authoring there is covered by import/export).
Still no backend or StashKit change: `SmartViewRequestFactory`'s create/update/delete
and the `SmartViewRequest` body already existed.

- **✅ Management lives in Settings, sidebar stays browse-only.** The user chose a
  dedicated management screen over inline sidebar editing. A shared
  `SmartViewManagementView` (a `List` with New / Edit / Delete) is reached from
  Settings — a `NavigationLink` on iOS, a third `Settings` tab on macOS. The
  sidebars (`MainView`, `MacContentView`, `TagBrowserView`) were **not** touched;
  because the shared `SmartViewRepository` cache is updated on every write (see
  below), the always-mounted sidebar Smart Views section reflects edits/deletes
  live without any sidebar code.
- **✅ Repository writes update the cache in place, no refetch.** `create` /
  `update` / `delete` on `SmartViewRepository` map the domain
  `[SmartViewCondition]` → `[SmartViewConditionDTO]`, run the factory, then
  insert / replace-by-id / remove in the cached `smartViews` and re-sort by name
  (`localizedCaseInsensitiveCompare`, matching the API's name-sorted list). Mirrors
  `BookmarkRepository`'s optimistic list mutations; avoids a round-trip and keeps
  the small per-user list authoritative. Conditions/matchMode cross the repository
  boundary as **domain** types so the views never touch StashKit DTOs (consistent
  layering).
- **✅ One shared `SmartViewFormView` sheet for create and edit.** Two inits
  (`init(repository:onSaved:)` and `init(editing:repository:onSaved:)`); the edit
  init pre-fills name, match mode, and condition rows. Built like `EditBookmarkView`
  (`NavigationStack { Form }.formStyle(.grouped)`, Cancel/Save toolbar, macOS min
  frame, inline error via `stashUserMessage`). A segmented All / Any picker maps to
  the wire `matchMode`.
- **✅ Condition rows model every editor kind, switch by `valueKind`.** A
  `SmartViewConditionType` enum (one case per wire type) carries a `title` and a
  `valueKind` (`text` / `tag` / `date` / `boolean`); a `ConditionRow` struct holds
  a value for each kind (`text` / `date` / `bool`) so switching a row's type
  preserves what was typed in the others. `ConditionRowView` renders the editor for
  the active kind: a text field, a tag field that reuses `TagSuggestionView` chips
  (`tagRepository.autocompleteTags(prefix:)`, the same autocomplete as the bookmark
  forms), a `DatePicker`, or a Yes/No segmented picker. Rows serialize to the domain
  `SmartViewCondition` by reading the field the type selects.
- **✅ Dates serialized to full ISO-8601 client-side.** The web form submits a bare
  `YYYY-MM-DD` and the *web controller* appends `T00:00:00Z`; the JSON API does no
  such normalization, so `SmartViewConditionDate` formats the picked day as
  `yyyy-MM-dd` + `T00:00:00Z` (and parses it back for editing). This was the one
  contract subtlety that would have produced a silent `422` if missed. Booleans go
  as lowercase `"true"`/`"false"`.
- **✅ Client-side validation pre-empts the generic 422.** `StashAPIError`
  collapses `validation_failed` to a single generic string, so the form validates
  locally (non-empty name ≤ 100, ≥ 1 condition, every text/tag row non-empty) and
  disables Save until valid — the user rarely reaches the server error. Delete uses
  the established `confirmationDialog` pattern; per-row swipe (iOS) + context menu
  (both) expose Edit/Delete.
- **✅ Verified.** iOS Simulator and macOS apps build clean; `swiftformat --lint`
  idempotent and `swiftlint lint` 0 violations. New files
  (`Common/Models/SmartView.swift` additions, `SmartViewFormView`,
  `SmartViewManagementView`) sit in synchronized Xcode folder groups — no
  `.xcodeproj` edit. No app unit tests by design (§19.6).

---

## SwiftUI view decomposition convention (native apps)

- **✅ Subviews are `make…() -> some View` functions, not computed-`var` subviews.**
  The owner's preferred style (used throughout the sibling project Triton): a view
  sub-piece is a `private func makeXxx() -> some View`, named `make` + what it
  produces (`makeEmptyState()`, `makeURLSection()`, `makeRowContextMenu(for:)`),
  taking parameters when it needs data. `var body` stays a small composition of
  `make…()` calls rather than one monolithic tree. `@ViewBuilder` is added only
  when the function body branches (`if`/`switch`) or returns sibling views with no
  single container; a function returning one container/modifier chain needs none.
  Non-view computed properties (`isValid`, `navigationTitle: String`, …) stay
  computed `var`s — only `some View`-returning members are functions.
- **✅ Applied across all of `StashApp/` in one pass.** Converted the 14
  computed-`var` subviews and renamed the 5 non-`make` view functions
  (`row(for:)` → `makeRow(for:)`, `viewLink` → `makeViewLink`, `rowContextMenu` →
  `makeRowContextMenu`, `setupView`/`recoveryCodesView` → `make…`), and sliced the
  larger `body`s (bookmark detail, login, the auth screens, the Smart View form,
  the sidebars) into `make…Section()` / `make…()` pieces. Purely structural — same
  view trees, same modifier order, no behavior change. New views must follow this.
- **✅ SwiftFormat places and marks them.** With `organizeDeclarations`
  (`--organization-mode type`, SwiftUI-aware), view-returning functions are filed
  under `// MARK: Content Methods` and re-sorted automatically — so we write the
  functions and run `swiftformat .`; MARKs are never hand-placed. Verified: iOS +
  macOS build clean, `swiftformat --lint` idempotent, `swiftlint lint` 0
  violations. Recorded in `CLAUDE.md` → Code style.

---

## App icon: the bookmark-ribbon mark (native apps)

- **✅ The app now wears the same mark as the browser extension.** Replaced the
  stock treasure-chest art with the Stash bookmark ribbon — the vertical ribbon
  with a V-notch at the bottom that `Extension/icons/` already uses — so the app
  and the extension share one identity.
- **✅ Generated, not hand-drawn — mirroring the extension.** `StashApp/icon/`
  `generate-app-icon.py` is the app-side twin of `Extension/icons/generate-icons.py`:
  same ribbon polygon (rounded top corners + V-notch), same supersample-then-resize
  approach. It renders the ribbon as a **white** glyph on a transparent 1024×1024
  canvas and writes `AppIcon.icon/Assets/Ribbon.png`. Regenerate, don't hand-edit
  the PNG. The folder lives outside the synchronized Xcode groups so the script is
  never compiled into a target.
- **✅ Icon Composer (`.icon`) supplies color and glass, the glyph stays flat.**
  The app uses the Xcode 26 `AppIcon.icon` bundle, not an `.appiconset`. `icon.json`
  keeps the single `glass: true` layer but now points at `Ribbon.png`, sets the
  background `automatic-gradient` to the brand indigo `#231468`
  (`extended-srgb:0.13725,0.07843,0.40784`), and resets the layer `scale`/
  `translation` to `1`/`[0,0]` (the old `1.35` + offset were positioning the wide
  chest art; the new glyph is already centered and sized in a square canvas). White
  ribbon on indigo glass.
- **✅ Renamed the layer asset `Foobar.png` → `Ribbon.png`** (and the layer `name`),
  retiring the placeholder name. iOS Simulator build succeeds; no `.xcodeproj` edit
  (the `.icon` bundle is referenced as-is).

---

## Accent palette: added the Terracotta theme

- **✅ Added a tenth accent theme, `terracotta` (`#d17e4c`).** Appended to
  `AccentTheme.all` after `slate`, keeping the existing nine untouched. It uses the
  same hex for light and dark — a muted clay-orange that reads well on either
  background — so unlike most themes its light and dark values are identical.
- **✅ Name over hex.** "Terracotta" was chosen to match the palette's evocative
  one-word style (Ocean, Aurora, Dusk, Slate) rather than a literal "Orange", since
  the tone is a soft clay rather than a pure orange.
- **✅ No other code changes.** `AccentTheme.validIdentifiers`, the admin picker, and
  the swatch CSS all derive from `all`, so the new theme is selectable, validates,
  and previews automatically. `PRODUCT.md` §7.6 (theme table + count) updated.

---

## Offline Sync — Phase 1 (backend sync endpoints + StashKit)

Phase 1 of the native-app offline-sync feature: the **two backend endpoints** and
the **StashKit additions** a sync engine will need, with no client behaviour change
yet. The native apps, web frontend, CLI, and browser extension are untouched.

- **✅ Tombstones for server-side deletions (`deleted_bookmarks` table).** A hard
  delete removes the row from `bookmarks`, so a `changes?since=` query can never
  report it — a client offline during the delete would keep the bookmark forever.
  The new `DeletedBookmark` model records every hard delete (`user_id`,
  `bookmark_id`, `deleted_at`), kept indefinitely (no cleanup this version). It is a
  plain table with no FK to `users` — when a user is deleted the account is gone and
  its tombstones are irrelevant, so a cascade buys nothing.
- **✅ Tombstones written on *every* hard-delete path, not just the API.** Recorded
  in `BookmarkController.delete` (JSON API), `AppWebController.deleteBookmark` (web
  single delete), and `AppWebController.deleteAllBookmarks` (web bulk delete) — any
  of which a synced user can trigger. A shared `DeletedBookmark.record(bookmarkID:
  userID:on:)` helper keeps the call site one line; it runs *after* the row is
  removed. The admin "delete user" cascade is intentionally excluded (see above).
- **✅ `GET /bookmarks/changes?since=&page=&per=`** returns a `Page<BookmarkResponse>`
  of all bookmarks — **archived included** — with `updated_at > since`, sorted
  ascending by `(updated_at, id)` so incremental pagination is stable. Default
  `per` 100, max 500 (higher than the 100-cap list endpoint, since this is a bulk
  sync read). Omitting `since` returns everything (the initial full sync). Unlike
  the list endpoint it does **not** split on `archived` — a sync needs both halves
  in one stream.
- **✅ `GET /bookmarks/deleted?since=`** returns a flat `[DeletedBookmarkResponse]`
  (no pagination — tombstones are tiny), sorted ascending by `deleted_at`. The
  response `id` is the **deleted bookmark's** ID (not the tombstone's own row id),
  so a client matches it straight against a local copy. Omitting `since` returns all
  tombstones.
- **✅ `since` parsed as a string, not a `Content` `Date`.** Vapor's
  `URLEncodedFormDecoder` date strategy is ambiguous for query params, so `since` is
  read as a raw string and parsed with `ISO8601DateFormatter`, trying the
  fractional-seconds variant first and plain internet-date-time second — matching
  StashKit's `.iso8601` JSON strategy. A malformed value is a `validation_failed`
  422 rather than a silent "no filter".
- **✅ StashKit stays thin.** Added `DeletedBookmarkDTO { id, deletedAt }` and
  `BookmarkRequestFactory.makeChangesRequest(since:page:perPage:)` /
  `makeDeletedRequest(since:)`. The factories format `since` as
  `[.withInternetDateTime]` ISO-8601. No formatter is held as a `static let` —
  `ISO8601DateFormatter` isn't `Sendable` under StashKit's strict-concurrency
  (swift-tools 6.2), so a tiny `iso8601String(from:)` builds one per call.
- **✅ Tests.** `BookmarkSyncTests` covers changes-since (archived included),
  changes-no-since, the delete→tombstone path, deleted-since, deleted-no-since, and
  per-user isolation for both endpoints. Deterministic timestamps are set with a
  query-builder `.set(\.$updatedAt, to:).update()` — a bulk update bypasses the
  `@Timestamp(on: .update)` auto-touch that a model `save()` would apply, so the
  controlled value persists. StashKit factory tests assert the paths, paging, and
  ISO-8601 `since` items (and their omission when `since` is nil).
- **Boundary.** No SwiftData, `SyncEngine`, connectivity monitoring, or UI — those
  are Phases 2–4. The backend is deployable; the apps behave exactly as before.

## Offline Sync — Phase 2 (SwiftData local store)

Phase 2 gives the native apps a persistent local copy of the user's bookmarks and
makes `BookmarkRepository` read from it. There is still no delta sync or offline
write queue (Phase 3) and no sync UI (Phase 4) — but the app now survives being
killed and reads entirely from disk.

- **✅ `LocalBookmark` (`@Model`) + `LocalStore`, app-only.** `LocalStore` owns the
  `ModelContainer` (configuration `"StashLocal"`, schema `[LocalBookmark]`) and is
  created once by `AppEnvironment`; every per-list `BookmarkRepository` and the
  `TagRepository` share its `mainContext`. Both files live under `Stash/` (the
  app-only group) — **not** `Common/` — so the Share Extension never links SwiftData
  and stays online-only. `LocalBookmark` carries a unique local `id` (stable SwiftUI
  identity) plus `serverID` (the sync match key) and the sync-metadata fields
  (`pendingSyncAt`, `locallyDeletedAt`, `isLocalOnly`) that Phase 3 will drive.
- **✅ Write-through, not local-only (deviation from the brief's literal write path).**
  The brief sketched Phase 2 writes as local-only (`pendingSyncAt = now`, no API
  call), with the offline queue arriving in Phase 3. Because each phase is deployed,
  shipping that would mean creates/edits/deletes silently never reach the server
  until Phase 3. Instead, every write calls the API first (exactly as before) and
  then mirrors the authoritative server result into the store (`upsert`/`remove`),
  leaving the sync-metadata fields clean. The local store stays consistent with the
  server, and no write is lost. Confirmed with the product owner. Phase 3 replaces
  this with the real offline queue that sets and pushes `pendingSyncAt`.
  🔁 Superseded: the write path is now optimistic-first for every write — see
  *Offline Sync — Optimistic writes*.
- **✅ Reads filter in memory, not via `#Predicate`.** `BookmarkRepository` fetches
  the active records (`locallyDeletedAt == nil`), maps them to domain `Bookmark`s,
  and filters/sorts/paginates in Swift via `BookmarkFilter`. SwiftData `#Predicate`
  can't express the hierarchical tag-prefix match (`swift` matches `swift/*`), the
  multi-column case-insensitive search, the recency sentinels, or the Smart View
  rule set; the dataset is one user's bookmarks, so an in-memory pass is simpler and
  exact. `BookmarkFilter` deliberately mirrors the backend (`QueryBuilder+Search`,
  `SmartView.applyConditions`): pipe-wrapped `tags_search`, `__untagged__` /
  `__today__` / `__this_week__`, `createdAt`-desc-then-`id` ordering, archived
  default, match-any/all. Smart Views are evaluated locally (the repository now takes
  the full `SmartView`, not just its id); their **definitions** still load from the
  API via `SmartViewRepository`.
- **✅ Pagination is a window over the filtered array.** `loadNextPage()` grows a
  `shownCount` slice of the in-memory result instead of fetching a page; writes
  recompute the filtered set and clamp the window, so a create/delete updates the
  visible list without resetting scroll depth or re-hitting the network.
- **✅ `TagRepository` derives from the store.** It counts each raw tag across the
  active local bookmarks — the same aggregation `GET /tags` performs (all bookmarks,
  archived included, no prefix expansion) — instead of calling the API. `refresh()`
  recomputes after a mutation.
- **✅ One-time full fetch, gated on first launch.** `AppEnvironment.bootstrapLocalStore()`
  seeds the store via `GET /bookmarks/changes` (no `since`, paginated at 200,
  archived included), guarded by a `localStoreSynced` flag in the App Group defaults.
  `MainFlowView` shows a brief `ProgressView` until it completes so lists read a
  populated store rather than flashing empty. On failure (offline) the flag is left
  unset and the next launch retries; the app still opens (empty) rather than hanging.
  Sign-out wipes the store and clears the flag so the next user re-fetches clean.
- **✅ Previews seed an in-memory store.** `AppEnvironment(inMemory:)` builds the
  container with `isStoredInMemoryOnly`; `AppEnvironment.preview` inserts
  `Bookmark.samples` so sidebars and lists still render in Xcode previews.
- **Boundary.** No `SyncEngine`, `NWPathMonitor`, `BGAppRefreshTask`, or sync UI —
  Phases 3–4. The Share Extension, web frontend, CLI, and browser extension are
  untouched. Both platforms build; lints clean.

## Offline Sync — Phase 3 (SyncEngine, connectivity, background refresh)

Phase 3 adds the real sync: a delta pull + push cycle with last-write-wins, an
offline write queue, connectivity-triggered sync, and iOS background refresh. The
sync state (`isSyncing`, `lastSyncedAt`, `lastSyncError`, `pendingCount`) is
published but **not yet consumed by any view** — that is Phase 4.

- **✅ `SyncEngine` (`@MainActor @Observable`), pull-then-push, last-write-wins.**
  Pull pages `GET /bookmarks/changes?since=` (per 500) and applies each DTO by
  `serverID`: insert if new; if the server's `updatedAt` is newer than the local
  `serverUpdatedAt`, apply it unless a local pending edit is newer (then keep local
  for the push). Then `GET /bookmarks/deleted?since=` removes tombstoned records.
  Push sweeps every `pendingSyncAt != nil` record — create (`POST`), update
  (`PUT`), or delete (`DELETE`) — clearing the metadata on success. Single-flight
  via an `inflightSync: Task` (same pattern as `AuthRepository.refreshIfNeeded`).
- **✅ The cursor subsumes the Phase 2 seed (supersedes `localStoreSyncedKey`).**
  `lastSyncedAt` (persisted in App Group defaults) is the delta cursor; when it is
  `nil` the pull omits `since` and fetches the whole library — exactly the Phase 2
  one-time seed. So Phase 2's `bootstrapLocalStore()` and the `localStoreSyncedKey`
  flag were removed in favor of `SyncEngine.sync()`. `RootView`'s `MainFlowView`
  now blocks on the first cycle (`hasSyncedBefore == false`) and otherwise shows
  content immediately while a delta sync runs in the background.
- **✅ The cursor is the cycle's *start* time, not its end.** Set to the timestamp
  captured before the pull, only after pull **and** push succeed. Using the start
  (rather than `Date()` at the end) means any change racing the cycle is re-pulled
  next time — `upsert` is idempotent, so over-fetching the boundary is harmless,
  whereas using the end could skip it. Client-vs-server clock skew is accepted under
  the last-write-wins simplicity.
- **✅ Offline write queue replaces Phase 2's pure write-through (per the brief's
  Phase 3 directive).** `BookmarkRepository` routes on `ConnectivityMonitor.isOnline`:
  online it stays write-through (API first, then mirror — instantaneous and
  conflict-free); offline (or when the API call fails with a transport error,
  `StashAPIError.unknown`, surfaced as `Error.isConnectivityError`) it queues
  locally — create inserts an `isLocalOnly` record with a temp `serverID`, update/
  archive mutate the record, delete soft-deletes — all stamping `pendingSyncAt`, and
  returns optimistically. The push drains the queue on the next cycle.
  🔁 Superseded: the `isOnline`-routed write-through online path was later dropped —
  all writes are now optimistic-first (apply locally, push in the background). See
  *Offline Sync — Optimistic writes*.
- **✅ Push conflict handling.** Create `409 duplicate_url` → the URL exists
  server-side (saved on another device); local content wins, so `PUT` the local
  title/description/tags onto the existing record and collapse onto whichever local
  copy holds that id. Update/delete `404` → the bookmark is gone server-side, so the
  local record is removed. A connectivity error mid-push aborts the cycle (cursor
  not advanced, `lastSyncError` set); other per-record errors are skipped so one bad
  record can't wedge the sweep. Push is a full sweep, never paginated (per the
  stopping rules).
- **✅ `ConnectivityMonitor` (`NWPathMonitor`).** Publishes `isOnline` and fires
  `onReconnect` on an unsatisfied→satisfied transition, wired to `syncEngine.sync()`.
  Starts optimistically online; the first path update corrects it.
- **✅ Sync triggers.** First launch / post-login (`MainFlowView.task`), reconnect
  (`onReconnect`), and return-from-background (`scenePhase` `.background → .active`,
  authenticated only). Single-flight coalesces overlaps.
- **✅ Background refresh is iOS-only this phase; `.backgroundTask(.appRefresh)`
  over raw `BGTaskScheduler.register`.** The SwiftUI scene modifier registers the
  handler and signals completion automatically — cleaner than an `AppDelegate` in a
  multiplatform SwiftUI app, and it sidesteps the launch-time `register` crash if the
  identifier is missing. `syncInBackground()` syncs then reschedules; the identifier
  `cc.otavio.stash.backgroundSync` is in both `Info.plist`s (`BGTaskSchedulerPermitted`
  `Identifiers`), with `UIBackgroundModes: [fetch]` on iOS. macOS `.appRefresh` is
  unavailable (`BackgroundTasks.framework` is iOS-only), so `BackgroundSyncScheduler`
  is `#if os(iOS)` and the modifier is on the iOS scene only; macOS needs no
  background entitlement (see the Phase 4 entry).
- **✅ Client provisioning via `StashClientProvider` + `SessionRefreshing`.** The
  brief's `init(client:context:)` is adapted to the app's pattern so a silent token
  refresh runs before each cycle and the engine always uses the configured server.
- **Known Phase 3 limitations (no UI yet).** A reconnect/background sync that
  changes the store does not live-refresh an already-visible list (lists refresh on
  their own triggers); `pendingCount` updates per sync cycle, not the instant an
  offline write is queued. Both are intentional — Phase 4 surfaces sync state and
  can wire live refresh.
- **Boundary.** No offline banner, pending row indicator, Settings sync section, or
  the macOS background entitlement — Phase 4. The Share Extension, web frontend,
  CLI, and browser extension are untouched. Both platforms build; lints clean.

## Offline Sync — Phase 4 (sync status UI) — feature complete

Phase 4 surfaces the sync state Phase 3 published. No new sync behavior — only the
banner, the pending indicator, and the Settings section. This completes the
offline-sync feature.

- **✅ Offline banner as `.safeAreaInset(edge: .top)` on `MainView` / `MacContentView`.**
  Chosen over a toolbar item (would shift toolbar content inconsistently and compete
  with existing buttons) and a modal (far too intrusive for an informational, fully
  supported state). `OfflineBanner` is a slim, muted (`.secondary` on `.bar`) strip —
  "Working offline — changes will sync when reconnected" — shown only while
  `connectivityMonitor.isOnline == false`, animating in/out with a top move +
  opacity transition driven by `.animation(_:value:)` on `isOnline`.
- **✅ Pending indicator on the row/detail, not a count badge.** A trailing muted
  `arrow.triangle.2.circlepath` (`PendingSyncBadge`) appears in `BookmarkRowView` and
  the `BookmarkDetailView` header when a bookmark has unpushed local changes. A badge
  with a number would imply *action required*; a row indicator is purely
  informational and clears itself once the change syncs. It never blocks
  interaction — a pending bookmark can still be opened, edited, archived, or deleted.
- **✅ Pending state rides the domain model (`Bookmark.isPendingSync`).** The views
  render the domain `Bookmark`, not `LocalBookmark`, so the badge needs the flag on
  the domain type. `Bookmark(local:)` sets `isPendingSync = (pendingSyncAt != nil)`;
  `Bookmark(dto:)` leaves it `false`. So list rows (built from local records) show
  the badge and reflect it the instant an offline write re-runs the owning
  repository's `refreshVisible()`. A reconnect/background sync that clears pending in
  the store updates a *visible* list on its next refresh trigger (the Phase 3
  cross-repository-refresh limitation stands — deliberately not widened here).
- **✅ Sync status in Settings, not a persistent toolbar item.** Sync is a background
  concern, not a primary action, so it lives where users look for it. A shared
  `SyncStatusSection` (used by the iOS `SettingsView` and the macOS General tab)
  shows "Last synced" (`RelativeDateTimeFormatter`, or "Never"), "Pending changes"
  (only when `pendingCount > 0`), and a "Sync Now" button (disabled with a spinner
  while syncing). It calls `refreshPendingCount()` on appear so the count reflects
  offline writes queued since the last cycle (`pendingCount` otherwise updates only
  per cycle, per Phase 3).
- **✅ Sync errors are a dismissible inline notice, never a modal.** When
  `lastSyncError != nil`, the Sync section shows a muted "Sync failed — tap Sync Now
  to retry" row with an `xmark` dismiss button (`SyncEngine.dismissError()`); the
  next cycle also clears it. Sync failures are non-blocking — the user keeps working
  offline — so a modal alert would be wrong.
- **✅ `BGAppRefreshTask`, not `BGProcessingTask`** (carried from Phase 3): the delta
  sync is short and network-bound, which is exactly what app-refresh tasks are for;
  processing tasks are for long CPU-bound work.
- **✅ Background refresh is iOS-only, and macOS needs no entitlement.**
  `BGTaskScheduler` / `BGAppRefreshTask` / SwiftUI's `.backgroundTask(.appRefresh)`
  live in `BackgroundTasks.framework`, which **does not exist on macOS**, so
  `BackgroundSyncScheduler` and the scene modifier are correctly `#if os(iOS)`
  guarded. The `com.apple.developer.background-task-scheduler` entitlement is for
  that iOS framework; it was briefly added to `Config/App-macOS.entitlements` by
  mistake (it has no effect on macOS and is noise during provisioning / App Store
  review) and has since been **removed**. `NSBackgroundActivityScheduler` — the
  macOS mechanism for scheduling work while the app is running — was evaluated and
  deliberately **not** added: macOS apps are rarely fully quit, and the existing
  launch/sign-in, return-from-background (`scenePhase → .active`), and reconnect
  (`ConnectivityMonitor.onReconnect`) triggers cover all practical sync needs. macOS
  background sync is therefore **complete as-is** — no additional mechanism is needed
  or planned.
- **Scope.** Only the four specified surfaces. No new sync logic, no
  cross-repository live-refresh-on-sync, no macOS background scheduler. The Share
  Extension, web frontend, CLI, and browser extension are untouched. Both platforms
  build; lints clean. **Offline sync is feature complete.**

## Offline Sync — Code review fixes

Three issues from the post-feature code review, fixed in a targeted pass (no
refactoring beyond the fixes).

- **✅ [High] Involuntary auth failure no longer wipes pending offline writes.**
  `clearSession()` (on an involuntary `tokenExpired` / `tokenInvalid` /
  `invalidCredentials` / `accountSuspended` during a refresh) calls
  `onSessionCleared` → `LocalStore.wipe()`, which previously deleted **all** local
  bookmarks. `wipe()` now deletes only the clean rows
  (`#Predicate { $0.pendingSyncAt == nil }`), preserving every record with a queued
  offline change (`pendingSyncAt != nil`, which also covers offline soft-deletes).
  On the next sign-in the cursor-less pull repopulates the store; preserved records
  survive it — `mergePulled` only applies a server DTO when it is newer than the
  local pending edit (last-write-wins), and `isLocalOnly` records carry a temporary
  `serverID` the server never returns, so a pull never touches them. They push on
  the first sync cycle after re-login.
- **✅ `SyncEngine.reset()` intentionally still clears `lastSyncedAt` (audit
  outcome).** The review fix suggested preserving the cursor so re-login is a delta
  "that would not stomp pending writes." On inspection, a full (cursor-less) pull
  does **not** stomp pending writes — the `mergePulled` LWW guard protects pending
  edits and `isLocalOnly` records never match a pulled DTO — so the premise does not
  hold. Preserving the cursor would instead break the explicit sign-out → *different
  user* login path: the new user would inherit the previous user's cursor and get a
  delta pull, leaving their library incomplete. So `reset()` keeps clearing the
  cursor; a full pull on re-login is correct and safe for pending writes.
  The explicit-logout case is handled separately — see "Explicit logout vs
  involuntary expiry" below.
- **✅ [Medium] Pull results are saved before the push begins.** `performSync()` now
  calls `localStore.save()` immediately after `pull()` and before `push()`, so
  server changes (inserts, merges, tombstone removes) are durable even if the push
  later fails or the app is killed mid-cycle. The cursor is still advanced
  (`setLastSyncedAt`) only after the push succeeds, so a push failure still re-pulls
  the same delta next time — just without re-fetching a large initial pull from
  scratch.
- **✅ [Medium] `LocalStore` wipe-and-retries instead of crashing on container
  failure.** A corrupt or schema-incompatible on-disk store previously hit a
  `fatalError` on every launch. `init` now deletes the store file (and its
  `-wal` / `-shm` sidecars) and recreates the container once; only a second failure
  on a fresh store still traps. Because the recovery leaves the store empty,
  `AppEnvironment` clears `lastSyncedAt` from the App Group defaults when
  `LocalStore.didResetOnInit` is set, so the next sync is a **full** cursor-less pull
  (a complete rebuild) rather than a delta that would leave the store partial — and
  `RootView` blocks on that first pull as it does on a fresh install. The local store
  is a disposable cache, so degrading to a re-seed beats crashing.
- **Scope.** Only the three review fixes. The [Low] findings (clock-skew cursor,
  `serverID` uniqueness, `serverUpdatedAt` client-clock semantics, sign-out race)
  and the missing backend tests are deliberately left for later. No view, web, CLI,
  or extension changes. Both platforms build; lints clean.

### Explicit logout vs involuntary expiry

Resolves the residual from Fix 1: an explicit sign-out must not leave the previous
user's unpushed writes in the store (they would push into the next user's account).

- **✅ Two teardown callbacks on `AuthRepository`.** `clearSession(explicit:)` now
  routes to one of two closures. **Involuntary expiry** (the `clearSession()` calls
  in `performRefresh()` — token expired/revoked, account suspended) fires
  `onSessionCleared`, wired in `AppEnvironment` to the preserving `LocalStore.wipe()`
  (keeps `pendingSyncAt != nil` records). **Explicit logout** (`logout()`, via
  `defer { clearSession(explicit: true) }`) fires the new `onExplicitLogout`, wired
  to `LocalStore.wipeAll()` (deletes every record, including pending). Both paths
  also reset the tag/Smart View caches and the sync cursor.
- **✅ No new public method, no view changes.** `logout()` was already the only
  user-initiated sign-out (both the iOS `SettingsView` and the macOS General tab
  call `authRepository.logout()`), so the explicit/involuntary split lives entirely
  inside `clearSession(explicit:)` plus the new `wipeAll()` — the cleanest fit for
  the existing funnel. The Settings views are unchanged; they already call
  `logout()`, which now takes the full-wipe path. Chosen over adding a separate
  `logoutExplicitly()` method, which would have duplicated `logout()`.
- **Trade-off (intended).** A user who signs out explicitly with pending offline
  writes loses them. This is correct: the next user must not inherit another user's
  unsynced data. Involuntary expiry still preserves the queue, since it is the same
  user whose session will resume.

| Scenario | Path | Wipe | Result |
|----------|------|------|--------|
| Token expired/revoked | `onSessionCleared` | `wipe()` | Pending writes survive, push on next login |
| Account suspended | `onSessionCleared` | `wipe()` | Pending writes survive, push when unsuspended |
| User taps "Sign Out" | `onExplicitLogout` | `wipeAll()` | Complete clean slate, no pending records left |

### Follow-up: serverID uniqueness + backend sync tests

- **✅ `LocalBookmark.serverID` is now `@Attribute(.unique)`.** `serverID` is the
  sync match key for `upsert`/`record(forServerID:)`; the constraint makes the model
  self-enforcing rather than relying solely on fetch-before-insert under `@MainActor`.
  Adding `.unique` to an existing attribute is a non-additive schema change that
  SwiftData will not auto-migrate, but no `VersionedSchema`/`SchemaMigrationPlan` is
  needed: `ModelContainer` creation throws on the incompatible store, and
  `LocalStore.init()`'s existing wipe-and-retry deletes the store and recreates it,
  setting `didResetOnInit` → `AppEnvironment` clears `lastSyncedAt` → the next sync is
  a full cursor-less re-seed. The store is a disposable cache, so this one-time
  rebuild on upgrade is acceptable (already-decided recovery strategy).
- **✅ Backend sync test gaps from the review are closed.** `BookmarkSyncTests` now
  also verifies: the **web single delete** (`POST /app/bookmarks/:id/delete`) and
  **web bulk delete** (`POST /app/settings/delete-all-bookmarks`) each record
  tombstones — so "tombstone on every hard-delete path" is covered for all three
  user-facing paths, not just the JSON API; `/changes` returns results **ascending by
  `updatedAt`** (the ordering the sync cursor pagination depends on); `/changes`
  **clamps `per` to 1…500** (oversized and zero both 200, not 422); and a **malformed
  `since` returns 422 `validation_failed`**. Web routes authenticate via a
  `stash_session` cookie helper mirroring the existing `adminWebSession` pattern.
  145 backend tests pass.

## Offline Sync — Optimistic writes (supersedes write-through)

🔁 **Supersedes the Phase 2/3 write-through write path.** Write-through awaited the
API on the UI path whenever `ConnectivityMonitor.isOnline` was true. But
`NWPathMonitor` reports the *network path*, not *server reachability* — with the
server down but Wi-Fi up, `isOnline` stays true, so a create/delete blocked on the
URLSession timeout (tens of seconds) before the offline-queue fallback ran. Result:
the Add sheet didn't dismiss and the row appeared/disappeared only after the
timeout, instead of instantly. The connectivity-based routing could not fix this —
the only way to be instant regardless of server state is to not await the network on
the UI path.

- **✅ Writes are now optimistic-first.** `create`/`update`/`setArchived`/`delete`
  apply to the local store and return immediately (the UI updates instantly, online
  or off), then call `scheduleSync()` — a detached `SyncEngine.sync()` followed by
  `refreshVisible()` — to push the queued change and reconcile this list with the
  server's authoritative result (real `serverID`, normalized tags, fetched metadata).
  The `isOnline` write routing and the per-write API calls are gone from
  `BookmarkRepository`; pushing is entirely the sync engine's job. `BookmarkRepository`
  now holds the `SyncEngine` (injected via `makeBookmarkRepository`) instead of the
  `ConnectivityMonitor`.
- **✅ Metadata fetch preserved across the optimistic path.** An online create still
  gets server-fetched title/description: `LocalBookmark.wantsMetadataFetch` records
  the create's `fetchMetadata` flag, and `SyncEngine.pushCreate` sends it on the
  `POST` (replacing the previous hard-coded `false`). The row first shows the local
  values, then updates to the server's when the push reconciles.
- **Trade-offs (accepted, per product owner).** An online create briefly shows local
  data before the background push replaces it with the server's normalized version (a
  short flicker; the optimistic record's `serverID` also changes from a temp UUID to
  the real one, so the list row re-identifies). When the server is unreachable but the
  network is up, the background push still wastes one request timeout — but off the UI
  path, so writes stay instant; the pending change pushes on the next sync trigger
  (foreground, reconnect, manual "Sync Now", or the next write). The pending badge on
  the detail view clears on the next list refresh, not instantly (the standing
  cross-repository-refresh limitation).
- **Scope.** `BookmarkRepository`, `LocalBookmark` (+`wantsMetadataFetch`),
  `SyncEngine.pushCreate`, and the `AppEnvironment` wiring. No `SyncEngine` algorithm
  change, no view changes, no backend/CLI/extension changes. Both platforms build;
  lints clean.

## Offline Sync — Live list refresh after an external sync

Resolves the standing cross-repository-refresh limitation (flagged since Phase 3).

- **Problem.** Each visible list owns its own `BookmarkRepository`, refreshed only by
  its own triggers and its own writes' `scheduleSync()`. A sync started **elsewhere**
  — the Settings "Sync Now", a reconnect, foreground, or background refresh — mutates
  the shared store (clears pending flags, applies server data) but left the visible
  list's published `bookmarks` stale. Repro: add a bookmark while the server is down,
  bring it back, tap "Sync Now" — the row kept its pending badge even though the push
  succeeded.
- **✅ The list observes sync completion.** `BookmarkListContent` now has
  `.onChange(of: environment.syncEngine.isSyncing)`; when it goes `true → false` (any
  cycle finished) it calls a new `BookmarkRepository.refresh()`. This covers every
  externally-triggered sync, not just the list's own writes.
- **✅ `refresh()` preserves the pagination window.** It calls the private
  `refreshVisible()` (re-read + re-filter, clamping the existing `shownCount`), unlike
  `reload()`/`load()` which reset to the first page. So a background sync reconciles
  the visible rows in place without snapping a scrolled list back to the top.
- **Scope.** `BookmarkRepository.refresh()` and one `.onChange` in
  `BookmarkListContent`. No `SyncEngine` change. Both platforms build; lints clean.

## Offline Sync — "Last synced" ticks live

- **Problem.** The Settings "Last synced" value was computed with
  `RelativeDateTimeFormatter` against `Date()` only when the view body re-evaluated.
  With the Settings view mounted and no observed value changing, it froze (e.g. stuck
  at "5 seconds ago") even as time passed or the user navigated between screens.
- **✅ Fix.** `SyncStatusSection` renders the value inside
  `TimelineView(.periodic(from: lastSyncedAt, by: 1))`, computing the relative string
  against the timeline's `context.date`, so it advances once a second on screen
  ("5 seconds ago" → "2 minutes ago"). "Never" still shows when there is no
  `lastSyncedAt`. One view method; no other changes.

## Offline Sync — Cross-user data integrity fixes

Two cross-user bugs from the full-feature code review (findings #1 and #2).

- **✅ [Critical] `LocalBookmark.userID` stops one user's pending writes pushing into
  another's account.** `LocalBookmark` gained a non-optional `userID: String` (the
  owner's server ID), set at every insert from the authenticated session and never
  changed (`apply(dto)` leaves it alone). Source: the access token's `sub` claim —
  `TokenManager.currentUserID` decodes it (reusing the existing base64url JWT
  parsing), exposed as `StashClientProvider.currentUserID()`. This is synchronous and
  offline-safe (no `/me` round-trip), so it's available both in `SyncEngine` (tagging
  pulled records) and in `BookmarkRepository.queueCreate` (tagging optimistic
  creates). `String` not `UUID` to keep the model free of a Foundation-UUID Codable
  dependency.
- **✅ Push is scoped to the current user.** `LocalStore.fetchPending(userID:)` (and
  `pendingCount(userID:)`) filter on `pendingSyncAt != nil && userID == current`.
  `SyncEngine.performSync` captures the user ID once per cycle and threads it into
  `pull` (inserts) and `push` (the pending sweep), so even when a previous user's
  pending records are preserved in the store, they are never fetched for push under a
  different user's token. This is the airtight guard for the Critical bug.
- **✅ Schema migration via the existing wipe-and-retry.** Adding a required `userID`
  is a non-additive change; `ModelContainer` creation throws on the old store,
  `LocalStore.init()` deletes and recreates it, sets `didResetOnInit`, and
  `AppEnvironment` clears `lastSyncedAt` so the next launch does a full re-seed that
  re-tags every record. No `VersionedSchema` needed (same strategy as the `serverID`
  uniqueness change).
- **✅ `wipe()` userID predicate — filter-if-known, else conservative.**
  `LocalStore.wipe(currentUserID:)` preserves only the current user's pending records
  when an ID is given (dropping any other user's leftovers), and falls back to
  preserving all pending records when it is `nil`. In practice `onSessionCleared`
  fires *after* `AuthRepository.clearSession()` has already cleared the tokens, so
  `currentUserID()` is `nil` there and the conservative branch runs — which is safe
  because the `fetchPending(userID:)` filter, not the wipe, is what prevents a
  wrong-user push. `wipeAll()` (explicit logout) is unchanged.
- **✅ [High] `SyncEngine.reset()` cancels the in-flight cycle.** `reset()` now calls
  `inflightSync?.cancel()` first. Previously a cycle racing a sign-out would resume,
  `save()` the rows the wipe just deleted, and `setLastSyncedAt()` re-persist the
  cursor — so the next user skipped the blocking full pull and browsed the previous
  user's bookmarks. `SyncEngine` is `@MainActor`, so the cancel and the caller's wipe
  do not interleave; `pull()` and `push()` each call `try Task.checkCancellation()` at
  entry (plus the cancellation-aware `URLSession` awaits), so a cancelled cycle aborts
  before `save()`/`setLastSyncedAt` rather than completing.
- **✅ A finishing cycle clears `inflightSync` only if it still owns the slot.** `sync()`
  and `pushPending()` previously ended with an unconditional `inflightSync = nil`. When
  `reset()` cancelled a cycle mid-flight and a new cycle then registered, the old cycle's
  resume would null out the *new* cycle's registration — letting a third caller see an
  empty slot and start a second concurrent cycle (two cycles sharing one `@MainActor`
  `ModelContext`, double-pushing the same pending rows). Each registration now bumps a
  `syncGeneration` counter and captures its value; the completion clears `inflightSync`
  only when `syncGeneration` still matches, so a cancelled cycle's resume is a no-op once
  a newer cycle has taken the slot. Narrow (needs a sync racing sign-out) and largely
  self-healing — a double create surfaces as `duplicate_url`, which `resolveDuplicate`
  handles — but the guard is trivial and removes the race outright.
- **Residual (not in scope here).** Reads (`LocalStore.fetchActive`, used by
  `BookmarkRepository` and `TagRepository`) are still **not** user-scoped, so a
  previous user's preserved/pulled records could be *visible* in a new user's list
  until they are cleared. The push leak (writing to the wrong account) is fully
  closed; fully closing the read-side visibility would need user-scoped reads or a
  different-user-login wipe, which touches `TagRepository`/read paths excluded from
  this change. Logged as a follow-up.

## Offline Sync — Sync correctness fixes (#4 + #8)

Two correctness bugs from the full-feature review.

- **✅ [#4] `isArchived` is preserved on offline-created bookmarks.** A bookmark
  created offline then archived offline (still `isLocalOnly`) lost its archive state
  on push: `pushCreate`'s `CreateBookmarkRequest` had no `isArchived`, the backend
  always created unarchived, and `apply(dto)` then reset the local flag. Added
  `isArchived` to the backend's `CreateBookmarkInput` and StashKit's
  `CreateBookmarkRequest` as `Optional<Bool>` (default `nil` ⇒ `false`), so existing
  clients (CLI, web, extension) that send no field are unaffected;
  `BookmarkController.create` applies `input.isArchived ?? false`. `SyncEngine.pushCreate`
  now sends `record.isArchived`, and `resolveDuplicate` (the 409 path) adds
  `isArchived` to its `PUT` so the merge keeps the local archive state too.
- **✅ [#8] `/changes` uses keyset, not offset, pagination — no row can be silently
  skipped.** Offset `.paginate()` over the mutable `updatedAt` sort key could skip a
  row when a concurrent edit shifted the offsets mid-pagination, and the
  `cycleStart` cursor never re-fetched it. Replaced with a `(updatedAt, id)` keyset:
  the query filters `updatedAt > since AND (updatedAt > afterUpdatedAt OR (updatedAt
  == afterUpdatedAt AND id > afterId))`, sorts `updatedAt, id` ascending, and fetches
  `per + 1` to compute `hasMore`. `id` (a UUID) breaks ties deterministically, so a
  bumped row simply re-appears on a later page (idempotent upsert) rather than being
  skipped. The `Page<T>` envelope is replaced by `ChangesPage<T>` (`items`,
  `hasMore`, `nextAfterUpdatedAt`, `nextAfterId`); `SyncEngine.pull()` now loops on
  `hasMore`, carrying the cursor forward, instead of a page counter.
- **⚠️ The keyset timestamp cursor is an opaque string, not a `Date` (deviation from
  the task's typing).** The API serializes timestamps at second precision (the
  StashKit decoder is non-fractional), so round-tripping the cursor as a `Date` would
  truncate it — and a same-second cluster larger than `per` (e.g. a tag rename
  touching hundreds of bookmarks at once) would make `updatedAt > afterUpdatedAt`
  perpetually true, never advancing: an infinite pull loop. Instead the server emits
  `nextAfterUpdatedAt` formatted with **fractional** precision and parses
  `afterUpdatedAt` fractionally; the client (`ChangesPageDTO.nextAfterUpdatedAt: String`)
  treats it as an opaque continuation token echoed back verbatim, never interpreting
  it — so no precision is lost and the keyset stays exact. `nextAfterId` stays a
  `UUID` (round-trips exactly).
- **Tests.** Backend `BookmarkSyncTests`: the existing `/changes` tests now decode
  `ChangesPage`; `changesClampsPer` asserts via `hasMore`/`items.count` (no
  `metadata`); a new `changesKeysetStable` proves a row bumped after page 1 reappears
  on page 2 with nothing skipped; `createArchived` proves `isArchived: true` on
  create persists. StashKit factory tests cover the new keyset parameters. 147
  backend tests pass; StashKit 23; both app platforms build; all lints clean.

## Offline Sync — Sync correctness fix (#3)

A pending record whose push hit a permanent error (e.g. 422/403) kept `pendingSyncAt`
set, so every cycle retried it forever while `pendingCount` stayed elevated, no
error surfaced, and the user had no way to clear it short of signing out.

- **✅ `LocalBookmark.syncError: String?`** holds the user-facing message of a
  permanent push failure; `nil` means none. Set alongside clearing `pendingSyncAt`
  (which stops the retry), and re-cleared whenever the record is synced (`apply`) or
  re-queued by a later edit/delete (`markPending`/`queueDelete` set it back to `nil`).
- **✅ Error classification in `push(_:)`.** The per-record `catch` now splits errors:
  connectivity is rethrown (aborts the cycle, as before), `CancellationError` is
  rethrown (preserves the reset-cancellation from the #2 fix), and the rest go through
  `isPermanentFailure`. **Recoverable** (left pending, retried): connectivity, auth
  (`tokenExpired`/`tokenInvalid`/`accountSuspended`), and transient `serverError`
  (5xx) — a server hiccup should not burn the offline write. **Permanent** (marked
  failed, dequeued): `validationFailed` (422), `forbidden` (403), and the other
  deterministic API errors. This treats `serverError` as recoverable, a deliberate
  refinement of the task's "everything non-connectivity/non-auth is permanent" so a
  transient 5xx doesn't discard a user's offline change.
- **✅ `SyncEngine.failedCount` + `clearFailedRecords()`.** `failedCount` is recomputed
  (user-scoped, like `pendingCount`) by `refreshPendingCount()` and at each cycle end.
  `SyncStatusSection` shows a "Failed to sync — N bookmarks [Clear]" row when
  `failedCount > 0`; **Clear** calls `clearFailedRecords()`, which deletes the current
  user's failed records (the user accepts losing the unrecoverable change).
- **✅ `Bookmark.hasSyncError`** (mapped from `syncError != nil` in `Bookmark(local:)`)
  drives `PendingSyncBadge(failed:)`: the muted `arrow.triangle.2.circlepath` for
  pending becomes an orange `exclamationmark.arrow.triangle.2.circlepath` for failed.
  The row/detail show it when `isPendingSync || hasSyncError`.
- **Schema migration (correction to the task's assumption).** `syncError` is an
  *optional* attribute, so it is an **additive** change — SwiftData lightweight-migrates
  existing stores in place (existing rows get `nil`), no wipe needed. The
  `LocalStore.init()` wipe-and-retry remains only as the fallback for a genuinely
  incompatible store.
- **Known limitation.** Clearing failed records from Settings updates `failedCount`
  immediately, but an already-visible bookmark list reflects the removal on its next
  refresh (the standing cross-repository-refresh behavior), not instantly. Both app
  platforms build; lints clean.

## Offline Sync — Cleanup sweep

Four no-behavior-change cleanups from the review.

- **✅ Dead `LocalStore` methods removed.** `remove(serverID:)` had no callers (grep
  confirmed) and is gone; `upsert(_:)` was already removed when the `userID` init
  change orphaned it (the #1 fix), so only `remove(serverID:)` remained to delete.
- **✅ `scheduleSync()` pushes only, no pull.** A write-triggered sync has nothing to
  pull — the device just produced the change — yet it ran a full `sync()` (pull then
  push) on every create/edit/delete, costing an extra round-trip and a redundant list
  refresh per write. Added `SyncEngine.pushPending()`, a push-only cycle that reuses
  the single-flight `inflightSync` guard; `scheduleSync()` now calls it. Full `sync()`
  (pull + push) still runs on launch/sign-in, foreground, reconnect, "Sync Now", and
  background refresh. Trade-off of the shared guard: if a write-push is in flight when
  a full sync is requested, the full sync coalesces onto it and skips that cycle's
  pull; this is rare and self-heals on the next pull trigger (foreground/launch/Sync
  Now), and is preferable to racing two cycles.
- **✅ Duplicated favicon-domain logic removed.** The host-derivation lived on both
  `Bookmark.faviconDomain` (instance) and `LocalBookmark.faviconDomain(for:)` (static).
  Made `Bookmark` the single owner — added `Bookmark.faviconDomain(for: URL)` static
  with the instance property delegating to it — and pointed `LocalBookmark`'s inserts
  at `Bookmark.faviconDomain(for:)`, deleting its copy. (The stored
  `LocalBookmark.faviconDomain` column is unchanged; only the duplicated derivation
  was removed.)
- **✅ `ConnectivityMonitor` doc comment corrected.** It claimed `BookmarkRepository`
  routes writes through the monitor to an offline queue — removed by the
  optimistic-write refactor. Now it states the monitor backs the offline banner
  (`MainFlowView`) and gates `SyncEngine` cycles, fires `onReconnect`, and is not used
  by `BookmarkRepository`.

## Offline Sync — Sync correctness fix (#5)

- **Problem.** Every hard-delete deleted the bookmark row and recorded its
  `DeletedBookmark` tombstone as two separate `await`s with no transaction. A crash
  or dropped connection in the gap left the bookmark gone server-side with no
  tombstone — a synced client would never see it again via `changes?since=` (gone)
  nor `deleted?since=` (no tombstone), orphaning the local copy forever.
- **✅ Fix.** All three hard-delete paths now wrap the delete and the tombstone
  record(s) in a single `req.db.transaction { db in … }`: `BookmarkController.delete`
  (API single), `AppWebController.deleteBookmark` (web single), and
  `AppWebController.deleteAllBookmarks` (web bulk — the whole delete-then-record loop
  is inside one transaction). Either the bookmark is deleted **with** its tombstone or
  neither takes effect. Fluent's `db.transaction {}` is honored by both SQLite (tests,
  in-memory) and PostgreSQL (production). The `bookmarkCount`/`user.save` update stays
  outside the transaction (a denormalized counter, not part of the delete/tombstone
  atomicity).
- **Tests.** The existing tombstone tests (`deleteRecordsTombstone`,
  `webDeleteRecordsTombstone`, `webBulkDeleteRecordsTombstones`) cover the success path
  under the transaction (147 backend tests pass). The rollback-on-failure assertion was
  **skipped**: there is no clean failure-injection point in the current harness —
  `DeletedBookmark` has no unique/NOT-NULL constraint to trip mid-transaction, and the
  only alternative is a production test-only hook, which the task explicitly directed to
  avoid over a fragile workaround. The atomicity rests on Fluent's transaction wrapper.

## Offline Sync — landing page copy

- **✅ Landing page now advertises offline.** The public landing page
  (`Backend/Resources/Views/landing.leaf`) predated offline sync and described the
  native apps with no mention of local storage or sync. Updated the hero lead to say
  the iOS/macOS apps "work offline" and rewrote the "Every platform" feature card to
  spell out the differentiator: the apps keep a full local copy of the library, browse
  and save offline, and sync automatically on reconnect (mirroring `PRODUCT.md` §16 and
  the Offline Sync phases above).
- **Folded into the existing card, not a 7th.** Offline was added to the "Every
  platform" card rather than as a new feature card, to preserve the balanced 3×2
  features grid (`landing.css` `repeat(3, 1fr)`) — a 7th card would have left a lone
  card on the last row. Content-only change: no template structure or CSS touched.

## Offline Sync — Refresh button triggers a sync

- **✅ ⌘R / the list Refresh button now runs `SyncEngine.sync()`.** Before offline
  sync, the bookmark list's Refresh action (`reload()` → `BookmarkRepository.load`)
  re-fetched from the server. After M13 the repository reads entirely from the local
  SwiftData store, so `load()` only re-read what was already on screen — the button
  reached nothing remote and was effectively a no-op. `BookmarkListView`'s Refresh
  button (and its ⌘R shortcut) now call a new `sync()` that awaits
  `environment.syncEngine.sync()`, the same single-flight pull-then-push cycle the
  Settings "Sync Now" button uses. The existing
  `.onChange(of: syncEngine.isSyncing)` handler repopulates the visible list when the
  cycle ends, so pulled-in bookmarks appear without an extra refresh call.
- **`reload()` / `load()` left alone.** They still back the local-only filter re-runs
  (search submit, search clear, source change, archived toggle) and the initial
  `.task` load — those must not hit the network, so only the Refresh button's action
  was repointed.
- **Pull-to-refresh removed.** The iOS `.refreshable { await load() }` had the same
  dead behavior (local re-read only) and was dropped rather than rewired — the ⌘R /
  toolbar sync is the single "get fresh data" affordance now.

## Tag picker (native apps)

- **✅ `TagPickerSheet` replaces the comma-separated tag field.** The add and edit
  bookmark forms previously edited tags through a comma-separated `TextField` plus the
  `TagSuggestionView` autocomplete chips (`TagInputSection`). Both forms now show a
  read-only tag summary (capsule `TagPill`s, or a muted "No tags") and an "Add Tags"
  button that presents `TagPickerSheet` — a touch-first surface where existing tags are
  picked from the hierarchical tree with no keyboard required. `TagInputSection` was the
  only caller of the comma-field machinery and is deleted; the picker is the sole
  tag-editing surface on the forms.
- **`TagSuggestionView` retained for `SmartViewFormView`.** The Smart View editor's `tag`
  condition value is a *single*-tag field, so the inline autocomplete chip pattern is
  still the right fit there — `TagSuggestionView` keeps that one caller and is not removed.
- **Search-as-create.** The picker's search field doubles as new-tag input: it filters
  the tree live, and when the normalized query matches no existing tag path a `+ Create
  "…"` row appears at the top. Tapping it (or pressing return) adds the tag and clears the
  field *without closing the sheet*, so several new tags can be added in a row. The query
  is normalized before adding via the shared `String.normalizedTagQuery()` — trim,
  lowercase, strip wrapping slashes, drop pipes — mirroring the backend's
  `Bookmark.normalizeTagQuery`. That helper now lives in `Common` (`Tag.swift`) and
  `BookmarkFilter` delegates to it, so the offline filter and the picker share one
  normalization (and the extension, which can't see the app-only `BookmarkFilter`, gets it
  too). The backend's normalization does **not** collapse duplicate `/`, so the client
  doesn't either.
- **Parent-visible filtering.** `TagPickerSheet.filtered` walks the `[TagNode]` tree
  recursively: a node survives if its own label matches or any descendant matches, so a
  matching child keeps its ancestors visible and the hierarchy stays navigable. A parent
  that matches by name keeps its full unfiltered subtree (all children stay selectable); a
  parent kept only because a descendant matched shows just the matching branch. The
  `OutlineGroup` disclosure behaviour is left native on both platforms.
- **Live binding, no Cancel.** Every tap toggles the tag in the `selectedTags` binding
  immediately, so Done and swipe-down both commit the same state — consistent with how iOS
  pickers generally behave. iPhone gets `.presentationDetents([.medium, .large])`; macOS
  uses a fixed-frame sheet.
- **Shared into the Share Extension.** `AddBookmarkView` (and thus the picker) is shared
  with the Share Extension, so `tagHierarchy: [TagNode]` was added to the
  `TagAutocompleting` protocol. The app's `TagRepository` already caches it;
  `ExtensionTagRepository` derives it on access via `[Tag].hierarchy()` (cheap — the
  process is short-lived). `TagTreeLabel` and `TagPill` moved from the app-only
  `Stash/Views/` into `Common/Views/` so the shared picker and summary can use them.
  Offline, the extension's tag list is empty and the picker shows a "No Tags Yet" empty
  state with only the Create path available — the same graceful degradation the old
  autocomplete had.

---

## Tag pills mirror the web's hierarchy rendering (native apps)

- **✅ `TagPill` displays `swift › server`, not `swift/server`.** The web frontend
  already presents a hierarchical tag with a middot separator (`AppWebController.display(_:)`
  → `tag.components(separatedBy: "/").joined(separator: " › ")`), which reads far better than
  the raw slash slug. The apps now match it: `TagPill` (`Common/Views/TagPill.swift`) renders a
  `displayName` computed from the same split-and-join (`" › "`, U+2023). **Presentation-only** —
  the stored tag, the `tag=` filter slug, and every query keep the raw `swift/server` form; only
  the pill's `Text` changes. Because `TagPill` is the single shared capsule, the change lands on
  the bookmark rows, the detail view, and the add/edit tag summary (and thus the Share Extension)
  at once. `TagTreeLabel` is deliberately left showing the leaf segment (`node.label`) — the tree
  conveys hierarchy by nesting, so it needs no separator.
- **🔁 Default-expanded tag trees were considered and deferred.** *Superseded by "Flat-indented
  (web-parity) tag tree" below.* Making the four `OutlineGroup(_:children:)` trees open expanded
  would require replacing `OutlineGroup` (which exposes no default-expanded / expansion-binding
  option) with a recursive `DisclosureGroup` wrapper across all four call sites — judged too much
  machinery for the payoff at the time. That recursive-`DisclosureGroup` path remains rejected; the
  simpler flat-indent port below was taken instead.

## Flat-indented (web-parity) tag tree (native apps)

- **✅ The four tag trees are always-visible and indented, not collapsible.** The
  `OutlineGroup(_:children:)` at all four call sites (iPad `MainView`, macOS `MacContentView`,
  iPhone `TagBrowserView`, and the add/edit `TagPickerSheet`) was collapsed-by-default with no way
  to open it — to browse or pick a tag you had to expand each parent, and the whole list was never
  visible at once. Replaced with `ForEach(nodes.flattened())`, mirroring the always-expanded web
  sidebar (which flattens to `[node, depth]` and indents with `padding-left`). **Why:** the entire
  tag list is now visible without expanding; it is *less* machinery than `OutlineGroup` (a flat
  `ForEach`, no recursion/disclosure state), not a workaround. The rejected alternative was the
  recursive-`DisclosureGroup` wrapper noted just above.
- **✅ Nested model kept; only rendering flattened.** `[Tag].hierarchy() -> [TagNode]` and the
  picker's parent-visible `filtered` (both walk `TagNode.children`) are unchanged. A new
  `[TagNode].flattened() -> [FlatTagNode]` (`Common/Models/Tag.swift`) produces a depth-tagged,
  pre-order sequence; the shared `TagTreeLabel` gained a `depth` that applies `padding(.leading,
  depth * indentPerLevel)`, so indentation lives in the one row used by all four sites (depth 0 = no
  padding, so top-level tags stay aligned with the `Views` section).
- **✅ Flattened form cached on `TagRepository`, like `tagHierarchy`.** The two sidebars and the Tags
  tab read a cached `flattenedTagHierarchy` (computed in `derive()` beside `tagHierarchy`, cleared in
  `reset()`) rather than calling `.flattened()` in the view body — same reasoning that cached
  `tagHierarchy`: a sidebar body re-evaluates on every selection tap, and re-walking the tree each
  time would defeat that cache. The picker keeps `filteredHierarchy.flattened()` inline (the filtered
  set changes per keystroke, so there is nothing to cache); `flattened()` itself uses an append
  accumulator rather than `[node] + recurse` to avoid per-level array reallocation.
- **✅ Search composes instead of fighting.** In `TagPickerSheet`, `OutlineGroup` undercut its own
  search: `filtered` narrowed the set but the collapsed-by-default tree still hid matching children
  behind a triangle. Flattening the already-filtered `filteredHierarchy` renders every surviving
  branch visible and indented, so matches appear immediately — no new search mechanism, just a flat
  render of the existing filtered subset.
- **✅ Verified.** Both platforms build (iOS Simulator + macOS), `swiftformat --lint` idempotent and
  `swiftlint lint` 0 violations. Drag-to-tag (`bookmarkTagDropDestination`) stays per-row and the
  Views-section sentinels are untouched.

## Drag-and-drop tagging (native apps)

- **✅ Drag a bookmark row onto a sidebar tag to add that tag — iPad and macOS only.**
  Those are the two layouts where the tag sidebar and the bookmark list share the screen
  (`SidebarSplitView` on iPad, `MacContentView` on macOS). On iPhone the tags are a separate
  tab, so there is no on-screen drop target; the gesture would also compete with the row's
  long-press context menu. Dragging is therefore gated off in compact width:
  `draggableBookmark(_:enabled:)` (`Common/Support/PlatformModifiers.swift`) applies
  `.draggable` only when enabled, and `BookmarkListContent.isDragEnabled` is `true` on macOS
  and only at `horizontalSizeClass == .regular` on iOS. `.draggable` and the existing row
  `.contextMenu` coexist (long-press lifts into the menu on iPad; drag = mouse, menu =
  right-click on macOS).
- **✅ `Bookmark` is `Transferable` via a custom UTType, not generic JSON.** `Bookmark`
  gained `Codable` and a `CodableRepresentation(contentType: .stashBookmark)` where
  `.stashBookmark = UTType(exportedAs: "cc.otavio.stash.bookmark")`. The dedicated type stops
  the tag rows from accepting arbitrary dropped JSON. **The type must be declared** in the app's
  Info.plist (`UTExportedTypeDeclarations`, conforming to `public.data`) on both platforms —
  without the declaration the drag still lifts, but `dropDestination(for: Bookmark.self)` can't
  resolve the conformance for an unregistered exported type and silently rejects every drop (the
  bug that "intra-app drags need no declaration" assumed away). Only the two App Info.plists need
  it; the Share Extension does no drag-and-drop. The drag carries a snapshot of the bookmark's tags at lift
  time — an accepted trade-off, since the append is a single field and last-write-wins sync
  reconciles any drift.
- **✅ The drop reuses the optimistic `update` path; no new write API.** A
  `BookmarkTagDropModifier` (`Stash/Views/`, app-only because it depends on
  `AppEnvironment`/`BookmarkRepository`, which are not in `Common/`) wraps each `TagTreeLabel`
  via `.dropDestination(for: Bookmark.self)` in both sidebars' `makeTagsSection()`. On drop it
  appends `node.slug` to each dropped bookmark's tags (skipping ones that already have it) and
  calls `BookmarkRepository.update(id:title:description:tags:)`, then
  `TagRepository.refresh()` to update the sidebar counts. It builds a throwaway repository via
  `makeBookmarkRepository()` — every repository writes to the one shared `LocalStore`, so the
  drop lands regardless of which list owns the visible state. **Gotcha:** the handler passes
  `description: bookmark.description` (not `nil`) because `queueUpdate` assigns
  `record.bookmarkDescription = description` unconditionally — `nil` would wipe the description.
- **✅ Sentinels are never drop targets.** `__untagged__`, `__today__`, and `__this_week__`
  live in the **Views** section, not in `tagHierarchy`, so only real tag nodes get the drop
  modifier. Synthetic parent nodes (count `nil`, e.g. `swift`) carry a real `slug` and are valid
  targets. A drop highlights the targeted row with a translucent accent `listRowBackground`.

## Native share (bookmark row menu + detail actions)

- **✅ Native `ShareLink`, not a pasteboard-style `#if` helper.** A **Share…** entry was added to
  both the bookmark row context menu (`makeRowContextMenu(for:)` in `BookmarkListView`) and the
  detail actions section (`makeActionsSection()` in `BookmarkDetailView`), placed after the Copy
  actions and before Archive so read/copy/share group above the mutating Archive/Delete actions.
  It uses SwiftUI's `ShareLink(item: bookmark.url)`, which is cross-platform and presents the system
  share sheet itself — no action closure and, unlike `copyToPasteboard(_:)`, no `#if` platform
  branch. Shares the URL only (the request was "share the URL"); `bookmark.url` is already a typed
  `URL`, exactly what `ShareLink(item:)` wants. In the detail it carries the sibling
  `.formButtonRowStyle()`.

## Smart View relative date conditions (olderThan / newerThan)

- **✅ Two new condition types — `olderThan` / `newerThan` — filter by age relative to now.** They
  join the existing absolute `createdBefore` / `createdAfter` conditions without replacing or altering
  them (§7.7). `olderThan` matches `createdAt < now - offset`; `newerThan` matches `createdAt > now -
  offset`. Added to the backend `SmartViewCondition` enum, the web condition builder, the native
  `SmartViewFormView`, and the offline `BookmarkFilter`.
- **✅ Value is a compact duration string (`Nd` / `Nm` / `Ny`, N ≥ 1).** A positive integer with a
  unit suffix — `d` days, `m` months, `y` years (`"30d"`, `"3m"`, `"1y"`). `"0d"`, `"-7d"`, `"1w"`,
  `"abc"`, `""`, and `"30"` (no unit) are invalid and rejected with `422 validation_failed`, the same
  way a malformed ISO-8601 date is for the absolute conditions. A shared `SmartViewDuration` value
  type owns the parse-or-`nil` logic and the cutoff calculation; it is duplicated deliberately on the
  backend (`Sources/App/Models/SmartView.swift`) and in the native `Common/Models/SmartView.swift`,
  the same DTO-vs-domain split used elsewhere (StashKit stays a thin wire layer).
- **✅ Evaluated at query time against `Date()`, with `Calendar` arithmetic.** The cutoff is computed
  when the query runs (server time on the backend via `Calendar.current`, device time in
  `BookmarkFilter`), never frozen at Smart View creation — so "older than 6 months" stays current as
  time passes. Months and years are **calendar** units (`Calendar.date(byAdding:)`), not fixed-second
  multiples, so `"1m"` is one calendar month rather than 30 days. Same server-timezone trade-off
  already accepted for the `__today__` / `__this_week__` sentinels.
- **✅ Code-only — no schema migration.** The `conditions` JSON column already stores arbitrary
  `{ type, value }` objects, so a new type costs nothing at the storage layer (the precedent set when
  `hasTags` was added). StashKit's `SmartViewConditionDTO` is unchanged beyond a doc comment — `type`
  and `value` are already generic strings.
- **✅ Distinct value editors per surface, both assembling the wire string.** The web condition
  builder renders a compound control (a number `<input>` + a Days/Months/Years `<select>`) that a
  small vanilla-JS handler assembles into the hidden `conditionValue[]` carrier on change; the native
  form renders an `Int`-bound `TextField` (number-pad on iOS, clamped to ≥ 1) plus a segmented unit
  `Picker`, serialized through `SmartViewDuration.wireValue`. The management table's condition summary
  renders the duration readably ("older than 30 days") rather than the raw `30d`.
- **✅ The web form clears a row's value carrier on type change, not on render.** Because the shared
  text `<input>` doubles as the hidden carrier for the assembled duration, switching a row's type
  (e.g. `olderThan` → `titleContains`) would otherwise leave the stale `"30d"` visible in the now-text
  field. The reset lives in the type `<select>`'s `change` handler (fires only on user interaction),
  never in `syncRow` (which also runs on page load) — so editing an existing Smart View still shows
  its saved values, while a switch to a duration type is immediately repopulated by `assembleDuration`.

## OpenAPI specification

- **✅ Hand-written YAML, not generated — zero new dependencies.** `Backend/Public/openapi.yaml` is an
  OpenAPI 3.0.3 description authored by hand from `PRODUCT.md` §7–§9 / §19.4, `Docs/api.md`, and the
  backend's `Content` response structs / StashKit DTOs. No code-generation step, no new Swift package,
  no generated Swift. The spec is the source of truth and lives alongside the other docs.
- **🔒 Rule — the spec is part of the API contract and is kept in lockstep, by hand.** Because nothing
  generates it, any change to the `/api/v1/` + `/health` surface — a new or removed endpoint, a renamed
  or added field, a changed status code, a new error case, a new query param — **must update
  `Backend/Public/openapi.yaml` in the same commit**, and re-validate (`npx @apidevtools/swagger-cli
  validate Backend/Public/openapi.yaml`). A spec that lags the code is treated as a bug. The wire shapes
  mirror the backend `Content` structs and StashKit DTOs — those two and the spec must agree. This rule
  is also stated in `CLAUDE.md` (Backend conventions) so every session sees it.
- **✅ Served statically from `Public/openapi.yaml` via the existing `FileMiddleware`.** No new route —
  the spec and the Swagger UI page are plain static assets picked up by the `FileMiddleware` already
  registered in `configure.swift`. No Swift source was touched.
- **✅ Swagger UI served from a CDN at `/docs.html` — no library, no build step.** `Public/docs.html`
  loads `swagger-ui` 5.29.1 from cdnjs and points it at `/openapi.yaml`. Browsing needs network access
  (CDN); the spec file itself is self-contained. Served at `/docs.html` rather than a bare `/docs`
  alias deliberately — the alias would have required a new Swift route, which was out of scope.
- **✅ Covers `/api/v1/` and `/health` only — web UI routes excluded.** The `/app` and `/admin`
  surfaces are session-cookie driven and not part of the public token API, so they are left out.
- **⚠️ Spec reflects the *implemented* API, not the PRD where they diverge.** `Bookmark`, `SmartView`,
  and `UserProfile` schemas follow the actual wire shapes (no `userID`; `UserProfile` has no `updatedAt`),
  and `GET /bookmarks/changes` is documented as keyset-paginated (`afterUpdatedAt`/`afterId`), matching
  the controller rather than the older offset-page wording in `Docs/api.md`. (Initially `POST
  /auth/totp/disable` and `POST /admin/users/:id/reset-totp` were also omitted as web-only; they were
  subsequently implemented on the JSON API — see "2FA disable / reset land on the JSON API" below.)
- **✅ Validated with `@apidevtools/swagger-cli`.** `npx @apidevtools/swagger-cli validate` reports the
  spec valid. Schema-level `examples` (an OpenAPI 3.1 feature) was reduced to a single 3.0.3 `example`
  on `SmartViewCondition`; the full per-type value catalogue lives in that schema's `description`.

## 2FA disable / reset land on the JSON API

- **✅ Closed the two PRD §9.2/§9.6 endpoints that previously existed only on the web UI.** `POST
  /api/v1/auth/totp/disable` (self-service) lives in `UserController` under the existing
  `auth/totp` group; `POST /api/v1/admin/users/:id/reset-totp` lives in `AdminController` under the
  `:userID` group (admin-only via `AdminMiddleware`). StashKit's `makeTOTPDisableRequest` /
  `makeResetTOTPRequest` already targeted these exact paths, so no client change was needed — this only
  catches the backend up to the spec, PRD, and StashKit.
- **✅ Both invalidate refresh tokens, matching PRD §8.4/§8.6.** Each handler deletes the user's recovery
  codes, clears `totpSecret`, sets `isTOTPEnabled = false`, and **deletes all refresh tokens** so other
  sessions are signed out. (The web self-service disable historically skipped the token revocation; the
  API does it per spec — a deliberate, spec-aligned divergence from the older web handler.)
- **✅ Behavioural choices.** Self-service disable requires a current TOTP code; a wrong code — or a call
  when 2FA isn't enabled — is `401 totp_invalid` (consistent with `verify-setup`). Admin reset needs no
  code and allows self-reset. Both teardown endpoints return **`204 No Content`** — matching each other and
  the shipped StashKit `VoidResponse` factories (`makeTOTPDisableRequest`/`makeResetTOTPRequest`). Admin
  reset is a **true no-op for a user with no 2FA footprint** (`isTOTPEnabled` false *and* `totpSecret`
  nil): it returns `204` without touching the user, so it never silently revokes the sessions of someone
  who never had 2FA. (Earlier this endpoint returned `200` + `UserResponse` and ran the teardown
  unconditionally; both were changed during the `/code-review` pass — the `200`+body drifted from the
  `VoidResponse` factory and the sibling `204`, and the unconditional teardown signed out non-2FA users.)
- **✅ Tests + docs in the same change.** Added `TwoFactorTests` cases (disable success revokes
  codes/tokens, wrong code, not-enabled, unauthenticated) and `AdminTests` cases (reset success,
  not-enabled no-op, unknown user 404, non-admin 403). Updated `Backend/Public/openapi.yaml`
  (`disableTOTP` + `adminResetUserTOTP` operations, `TOTPDisableRequest` schema — re-validated) and
  `Docs/api.md`, per the spec-lockstep rule. PRD §9.2/§9.7 now match the implementation.

## Visual polish — bookmark list, detail, empty states (native apps)

- **✅ A content-first polish pass on the bookmark row, detail header, and empty states — no new
  features, no navigation or data-flow changes.** Aesthetic reference is Things / Craft: structured,
  generous whitespace, refined typographic details, chrome that disappears.
- **Typographic hierarchy — three levels via semantic styles.** Each row reads as a clear scale instead
  of three equal-weight elements: **title** primary (`.body` weight `.medium`, `.primary`, 2-line),
  **domain** secondary (`.caption` weight `.medium`, `.secondary`), **tags** tertiary (`.caption2`,
  `.tertiary`). The same scale is applied in the detail header (`.title2` semibold title, identical
  domain line, `.caption` `.secondary` URL). No hardcoded point sizes — semantic text styles throughout,
  so Dynamic Type and dark mode work for free.
- **Domain as the visual anchor.** The row's secondary line is now `favicon + domain`
  (`bookmark.faviconDomain ?? hostname`, `www.`-stripped) rather than the full URL — more scannable and
  more meaningful. The favicon sits on the domain line, vertically centred. The detail view keeps the
  full URL too, but demoted to a quiet `.caption` `.secondary` `Link` *below* the domain line.
- **Tags text-only in the list row; styled capsule retained in the detail view.** `TagPill` gained an
  `isPlain` parameter: the default is the accent-tinted capsule (used in the detail Tags section and the
  add/edit summary), `isPlain: true` drops the background to quiet `.tertiary` text for the row. The
  `swift › server` hierarchy rendering and the 3-tags-+N overflow logic are unchanged — only the
  treatment.
- **Increased row padding.** Row vertical padding went `4` → `10`, inner `VStack` spacing `4` → `6`, so
  rows breathe. No fixed row height — content drives it.
- **Favicon monogram fallback.** `FaviconView`'s placeholder (shown while loading and on a 404) is now a
  rounded-square monogram of the domain's first letter (`.quaternary` fill, `.secondary` text, matching
  the 18×18 / 4pt-radius favicon frame) instead of the `link` SF Symbol — a calmer, less broken-looking
  empty state.
- **`BookmarkEmptyState` — one shared empty-state component with specific, actionable copy per context.**
  Symbol (`.system(size: 44)`, `.quaternary`) → title (`.title3` semibold) → message (`.body`
  `.secondary`, centred, max width 280pt), centred in the available space. Replaces the per-context
  `ContentUnavailableView` calls for the first-run, archived, tag-filter, and Smart-View cases with copy
  that names the active filter and says what to do next ("No bookmarks yet" → "Save your first bookmark
  using the + button, the Share Extension, or the browser extension"; tag filter shows the
  `›`-separated display name; the untagged/today/this-week sentinels keep their own tailored copy).
  The active-search case keeps Apple's `ContentUnavailableView.search(text:)` — already well-designed.
  No buttons on any empty state: the toolbar `+` already provides the action.
- **Scope.** Touched only `BookmarkRowView`, `BookmarkDetailView` (header section only — the grouped
  `Form` and its action rows are unchanged), `BookmarkListView` (empty states), `TagPill`, `FaviconView`,
  and added `BookmarkEmptyState`. No backend / StashKit / CLI / web / extension changes; no app unit
  tests (§19.6). Builds clean on both iOS and macOS.
- **Follow-up — two-line description in the row (native apps).** The original pass kept description
  detail-only; the row was domain → title → tags. After the web list adopted a two-line description
  excerpt (see *Visual polish — bookmark list mirrors the native row (web frontend)*), the native
  `BookmarkRowView` was brought back to parity: a `makeDescription()` line (`.subheadline`, `.secondary`,
  `lineLimit(2)`) now sits between the title and the tags, shown only when the bookmark has a non-empty
  description. The web's two-line clamp and the native `lineLimit(2)` are the same idea — a short,
  proportionate excerpt rather than a fixed character count. iOS/iPadOS/macOS share the one row view.

## Add/Edit Bookmark — custom layout (native apps)

- **✅ Replaced the grouped `Form` in both the add (`AddBookmarkView`) and edit (`EditBookmarkView`)
  screens with a plain `ScrollView` + `VStack(spacing: 0)` of field groups.** The grouped form's
  table-cell chrome (inset rounded sections, separators, system row insets) is gone; spacing and thin
  dividers do the structural work instead, giving precise control over a calmer, more breathable layout.
  Same Things / Craft direction as the bookmark-list polish.
- **Label-above-field pattern (Things-style).** Each field group is a small `FieldLabel` (`.caption`
  `.medium` `.secondary`, the same tertiary level as the list/detail scale) floating above a `.body`
  field, rather than a `Form` section header to the left. New shared `FieldLabel` view in `Common/`.
  Each group is padded `.horizontal 20` / `.vertical 14`, separated by `Divider().opacity(0.3)`.
- **Borderless fields.** Text fields use `.textFieldStyle(.plain)` and sit directly on the sheet
  background (no per-field box). Title/description are `axis: .vertical` with `lineLimit(1...3)` /
  `lineLimit(3...6)` so they grow in place. `.scrollDismissesKeyboard(.interactively)` keeps the
  keyboard out of the way as the user scrolls.
- **Metadata preview row.** After a successful fetch (manual on the app, auto-on-appear in the
  extension) a compact `favicon 24×24 + domain` row fades in (`.transition(.opacity)`) between the URL
  and title groups — visual confirmation of *which* site was fetched, without a separate status line.
  Editing the URL clears it (and re-shows the Fetch button). The Fetch button itself shows only while
  the URL is non-empty and unfetched, becoming a small `ProgressView` while in flight.
- **Favicon across the target boundary.** `FaviconView` is app-only (it reads the `@Observable`
  `AppSettings`), but the add form lives in `Common/` and compiles into the Share Extension, which has
  no `AppSettings`. Rather than push that dependency into the extension, the shared favicon **styling**
  (`RoundFaviconModifier` / `roundedFavicon(size:)`) and the **monogram fallback** (`FaviconMonogram`)
  moved to `Common/Views/FaviconStyle.swift`, and a sibling `MetadataFaviconView` (also `Common/`) reads
  the server URL straight from the App Group's shared `UserDefaults` (`AppGroup.serverURLKey` — the same
  value `AppSettings` writes through). The app's `FaviconView` data flow is unchanged; list/detail
  favicons are untouched. Both views now share one look. `FaviconView` also gained a `size` parameter
  (default 18) so the preview can render at 24.
- **Save/Cancel stay in the navigation toolbar** (cancellation/confirmation placements) on all
  platforms, consistent with the rest of the app's chrome; Save is disabled until the URL parses and
  becomes a `ProgressView` while saving. The macOS Share Extension's inline bottom action bar
  (`usesInlineActionBar` → `.safeAreaInset(edge: .bottom)`) is preserved.
- **Share Extension compatibility preserved.** `isURLEditable` (read-only `.body` URL text, no paste /
  fetch when locked), `autoFetchOnAppear` (fetch in `.task`), and `usesInlineActionBar` all continue to
  work unchanged. `TagSummarySection` was reworked from a `Form` `Section` into the label-above-field
  layout (up to three `TagPill` chips + `+N`, trailing "Add Tags →" button presenting the unchanged
  `TagPickerSheet`); it is shared by both forms so tag editing stays identical everywhere.
- **Scope.** No backend / StashKit / CLI / web / extension-folder changes; `TagPickerSheet` untouched
  (a later pass); no data-layer changes; no app unit tests (§19.6). Builds clean on iOS and macOS
  (extension target included).

## Tag Picker Sheet — visual polish (native apps)

- **✅ A visual polish pass on `TagPickerSheet` matching the bookmark-list / Add-Edit aesthetic.**
  Functional behaviour is unchanged — single-tap toggles, search-as-create, Done commits. Two visible
  improvements plus minor row/empty-state refinements.
- **Leading selection circle replaces the trailing checkmark.** Each tag row now leads with
  `circle` (unselected, `.secondary`) / `circle.fill` (selected, accent), the iOS multi-select pattern
  from Mail / Reminders / Shortcuts. The circle is flush-left for every row; `TagTreeLabel` (unchanged)
  still carries the per-depth indent, so the hierarchy reads from the label's inset while the circles
  form a clean leading column. Row stays fully tappable (`contentShape(Rectangle())`).
- **Selected-tags chip strip above the list.** When `selectedTags` is non-empty a horizontally
  scrollable strip of chips appears between the search field and the list, in insertion order (the
  `[String]` selection already preserves order). It animates in/out with
  `.transition(.move(edge: .top).combined(with: .opacity))` driven by
  `.animation(.default, value: selectedTags.isEmpty)`, so it slides in on the first selection and out
  when the last is removed. The strip's horizontal scroll and the list's vertical scroll don't conflict.
- **`SelectedTagChip` — a new view in `Common/Views/TagPickerSheet.swift`.** Renders the tag in the
  same `›`-separated format as `TagPill` (logic re-derived, not a dependency) with a `×` remove button,
  but on a muted `.quaternary` capsule rather than the accent tint — deliberately quiet so the strip
  doesn't compete with the accent selection circles below. Kept distinct from `TagPill`, which remains
  the styled summary chip for the detail view and the add/edit forms.
- **Create row distinguished from tag rows.** The search-as-create row now leads with
  `plus.circle.fill` in the accent colour and a `.body` `.medium` label, instead of a plain `circle`,
  so the create action reads as an action rather than another selectable tag.
- **Empty state reuses `BookmarkEmptyState`.** That component (pure SwiftUI, no app dependencies)
  moved from `Stash/Views/` to `Common/Views/` so the shared picker — which compiles into the Share
  Extension — can use it; the bookmark list (in `Stash/`) still references it unchanged. The no-tags
  state shows the calm symbol / title / message ("No tags yet" / "Type a name above to create your
  first tag."); the no-search-match case keeps a `magnifyingglass` `ContentUnavailableView`.
- **Scope.** Only `TagPickerSheet.swift` changed (plus relocating `BookmarkEmptyState`); `TagTreeLabel`,
  `TagPill`, the selection/normalisation logic, and `TagPickerSheet`'s interface are all untouched. No
  backend / StashKit / CLI / web / extension-folder changes; no data-layer changes; no app unit tests
  (§19.6). Builds clean on iOS and macOS (extension target included).

## Add/Edit Bookmark — tag chip strip (native apps)

- **✅ Follow-up to the Add/Edit custom layout: the tag row (`TagSummarySection`) now uses the
  removable `SelectedTagChip` strip instead of static `TagPill`s.** Selected tags render as the same
  muted `.quaternary` capsules with a `×` dismiss as in `TagPickerSheet`; tapping `×` removes the tag
  from the binding immediately (`selectedTags.removeAll { $0 == tag }`) — no need to reopen the picker
  to drop a tag. The strip scrolls horizontally and the trailing "Add Tags" button (arrow dropped, the
  chips make the context clear) stays put to add more. With no tags selected the strip is absent and the
  button is the only element, as before.
- **`SelectedTagChip` moved to its own `Common/Views/SelectedTagChip.swift`** (it had been file-scoped
  in `TagPickerSheet.swift`) so it reads as the shared chip it now is — used by both the picker's
  selected-tags strip and the forms' tag row, and compiled into the Share Extension. Pure SwiftUI, no
  app dependencies. `TagPickerSheet` is otherwise unchanged.
- **Scope.** Only `TagSummarySection` (chip strip) and the `SelectedTagChip` relocation; `TagPickerSheet`
  selection logic/interface and `TagPill` untouched. No backend / StashKit / CLI / web / extension-folder
  changes; no data-layer changes; no app unit tests (§19.6). Builds clean on iOS and macOS (extension
  included).

## Settings — visual polish (native apps)

- **✅ A polish pass on the Settings screens (iOS `SettingsView`, macOS `GeneralSettingsView`, the
  shared `AccountSettingsView` / `SmartViewManagementView` / `SyncStatusSection`).** Same Things / Craft
  direction. The recurring problem was in-place action buttons inheriting `Form` cell styling (full-width
  tappable rows) and cramped, undifferentiated sections.
- **In-place actions now look like buttons.** Buttons that act in place — Sync Now, Sign Out, Change
  Password, Enable/Disable Two-Factor, New Smart View — are explicit `.bordered` / `.borderedProminent`
  buttons, sized to content and left-aligned, not `Form` rows. Navigation rows (Account →, Smart Views →)
  stay as `NavigationLink`s, the correct native pattern. Destructive actions (Sign Out, Disable
  Two-Factor) use `.bordered` + `.tint(.red)`; the primary New Smart View action uses
  `.borderedProminent` (accent fill).
- **iOS `SettingsView` / macOS General stay `Form`-based** (appropriate for a compact settings list and
  the editable macOS server URL field) — only the buttons changed: Sync Now and Sign Out are now
  left-aligned bordered buttons (`HStack { … ; Spacer() }` inside their section), Sign Out red-tinted in
  its own section so it reads as a standalone dangerous action rather than a row tucked under Sync Now.
  `SyncStatusSection` is shared by both, so the Sync Now restyle lands in one place; its spinner-while-
  syncing behaviour is preserved.
- **`AccountSettingsView` converted from `Form` to a `ScrollView` + `VStack`** with the label-above-field
  pattern from Add/Edit: a `FieldLabel` floats above each `SecureField` (kept `.roundedBorder` so a
  password box still reads as an input), `spacing: 16` between fields, `spacing: 32` between the Change
  Password and Two-Factor sections for clear air. Section headers are `.headline`; the "At least 12
  characters" helper is `.caption .secondary`; the 2FA status is a `.body .secondary` line (a status, not
  a cell) above its bordered action. The password-change and 2FA enrol/disable logic is unchanged.
- **`SmartViewManagementView` restructured.** The "New Smart View" button moved out of the `List` to the
  top of a `VStack` as a left-aligned `.borderedProminent` button (was a chip-like `Form` row), removing
  the redundant section divider that sat between it and the list. Rows now show a two-level hierarchy —
  name `.body .medium .primary`, condition summary `.caption .secondary` — and keep their swipe-to-delete
  and context menu (still a `List` below the button). The empty state uses the shared `BookmarkEmptyState`
  ("No Smart Views" / "Create a saved filter to quickly find bookmarks matching specific conditions.").
- **Scope.** Touched only the Settings views listed above; no navigation/routing changes, no behavioural
  changes to any settings action, `SmartViewFormView` untouched. No backend / StashKit / CLI / web /
  extension-folder changes; no data-layer changes; no app unit tests (§19.6). Builds clean on iOS and
  macOS (extension target included).

## Share Extension — visual polish (native apps)

- **✅ A refinement pass on the four Share Extension states (loading, signed out, add form,
  confirmation).** The add form is the shared `AddBookmarkView` and already carries the redesigned
  layout (label-above-field, metadata preview, tag chip strip) plus the iOS toolbar / macOS inline
  action bar — that flows through untouched, so this pass is the extension-specific chrome only. Same
  Things / Craft direction; semantic colours throughout.
- **Loading.** Replaced the `ProgressView` + "Stash" text label with a large `.quaternary`
  `bookmark.fill` ribbon mark above a `.secondary`-tinted spinner — a quiet, distinctive presence with
  no redundant label, centred in the popover.
- **Signed out.** Replaced the generic `ContentUnavailableView` with the shared `BookmarkEmptyState`
  (`person.crop.circle`, "Sign in to Stash", "Open the Stash app to sign in, then share this page
  again.") — calm and directive rather than apologetic. The toolbar Cancel to dismiss the extension is
  kept.
- **Confirmation.** Reworked into a calmer moment: `checkmark.circle.fill` (48pt, `.green`), "Saved to
  Stash" (`.title3 .semibold`), the saved bookmark's **domain** (`faviconDomain`, `.body .secondary`) as
  a concrete confirmation of what was saved, the bookmark's **tags** as read-only `SelectedTagChip`s
  (shown only when present), and an unobtrusive `.plain` `.secondary` "Undo" text button (was a bordered
  destructive button). The form→confirmation swap cross-fades via `.transition(.opacity)` wrapped in
  `withAnimation`.
- **`SelectedTagChip` gained `showsDismissButton: Bool = true`** so the confirmation can render the
  read-only (no-`×`) variant while the picker/forms keep the removable one; existing call sites are
  unaffected by the defaulted parameter.
- **Auto-dismiss shortened from 3s to 1.5s.** The confirmation's `Task.sleep` before
  `completeRequest` is now 1.5 seconds; the Undo button still cancels the task by removing the view, and
  the delete-on-undo logic is unchanged.
- **Scope.** Only `ShareExtensionView.swift` (the four state views + timer) and the `SelectedTagChip`
  parameter changed; `AddBookmarkView`, `SharedItemLoader`, the `Phase` enum / transition logic, the
  view controllers, and the extension repositories/session are untouched. No backend / StashKit / CLI /
  web / extension-folder changes; no data-layer changes; no app unit tests (§19.6). Builds clean on iOS
  and macOS (extension target included).

## Settings — General tab follow-up (macOS)

- **✅ Fixed the macOS General tab, which the first Settings pass missed.** It was still a grouped
  `Form`, so "Sync Now" and "Sign Out" rendered as full-width cells (the `.bordered` styling was being
  swallowed by the section-row chrome) and the tab carried noticeably more empty space than the
  `ScrollView`/`VStack`-based Account and Smart Views tabs.
- **Converted `GeneralSettingsView` to `ScrollView` + `VStack`** matching `AccountSettingsView` — same
  `.padding(20)`, `.headline` section headers, `spacing: 32` between sections — so all three tabs start
  at the same vertical position and share horizontal margins. "Sync Now" and "Sign Out" are now genuine
  left-aligned bordered buttons (Sign Out red-tinted, separated by the 32pt section gap). The Server URL
  stays an editable `LabeledContent`-style value row (label leading, trailing inline field).
- **`SyncStatusSection` split into `SyncStatusSection` + `SyncStatusRows`** to share the rows across the
  two containers without disturbing iOS. `SyncStatusRows` is a flat `Group`, so the iOS settings `Form`
  still renders each row as its own cell (`SyncStatusSection` remains the thin `Section("Sync")`
  wrapper, unchanged in appearance) while the macOS `VStack` stacks the same rows under its own "Sync"
  header. The once-per-appearance `refreshPendingCount()` `.task` now hangs off the single always-present
  "Last synced" row rather than the container, so it still fires exactly once. iOS `SettingsView` is
  unchanged (a `Form` remains appropriate there).

## Settings — General tab URL field follow-up (macOS)

- **✅ The General tab's Server URL converted from a `LabeledContent` value row to the label-above-field
  pattern** — a `FieldLabel("Server URL")` over a `.roundedBorder` `TextField` (keeping `.urlFieldStyle`)
  — matching the Account tab's field styling so it reads as an editable input rather than a static data
  row. No change to URL validation or how it persists to `AppSettings`.

## Smart View form — condition row buttons follow-up (native apps)

- **✅ The condition row's small bordered `−`/`+` buttons replaced with `minus.circle` / `plus.circle`
  SF Symbol buttons** (`.plain` style, `.title3` size): `minus.circle` in `.secondary` (neutral remove),
  `plus.circle` in `Color.accentColor` (primary add). The remove button keeps its single-condition
  disabled state, now shown as `.opacity(0.3)`. Add/remove logic unchanged.

## Settings — Server URL is read-only while signed in (native apps)

- **✅ The macOS General tab's Server URL is now read-only, matching iOS.** The Settings screens are only
  reachable while signed in, and changing servers requires a fresh login + setup against the new
  instance — so an editable field there was misleading (the earlier macOS "editable field" follow-up
  was wrong). macOS now shows the URL as a read-only `Text` under the `FieldLabel` (replacing the
  `TextField`); `GeneralSettingsView` no longer needs the `@Bindable` server-URL binding. iOS already
  displayed it read-only (`LabeledContent`) and is unchanged in that respect.
- **Both platforms gained a "Sign out to connect to a different server." footnote** so the read-only
  field is self-explanatory (a `Section` footer on iOS, a `.caption .secondary` line on macOS). No
  change to how the server URL is stored or validated.

## Add/Edit Bookmark — description field fill + scroll (native apps)

- **✅ The description field converted from `TextField(axis: .vertical)` to a `TextEditor`** (new shared
  `DescriptionEditor` in `Common/Views/`, used by both forms and the Share Extension). `TextField` isn't
  a scroll view, so on macOS it ignored the mouse wheel once the text overflowed; `TextEditor` is a
  proper scrollable text view (wheel on macOS, touch on iOS). Quirks handled: the placeholder is drawn
  manually in a `ZStack` (TextEditor has no placeholder), and `.scrollContentBackground(.hidden)` +
  `.background(.clear)` keep the borderless look from the form redesign; `.font(.body)` set explicitly.
- **✅ The description now fills the sheet's remaining vertical space**, removing the dead gap between the
  tags section and the action buttons when the description is short. The form holder no longer scrolls:
  each body is a fixed `VStack` pinned to `maxHeight: .infinity` (top-aligned), and the description
  section is the lone `maxHeight: .infinity` sibling (120pt floor), so it absorbs the slack while the
  URL/title/tags and the action buttons stay put. Only the description scrolls — internally, within the
  `TextEditor` — when its text overflows; the surrounding view does not. This dropped the outer
  `ScrollView` (and with it `.scrollDismissesKeyboard`), which was the holder that previously scrolled.

## Settings — grouped background for custom-layout sheets (native apps)

- **✅ Restored the system grouped background on the custom (non-`Form`) settings/Smart View sheets.**
  Root cause: a grouped `Form`/`List` supplies `systemGroupedBackground` automatically; once
  `AccountSettingsView` and `SmartViewFormView` moved to a plain `ScrollView + VStack` (for the
  label-above-field layout / custom condition rows), they fell through to the plain white system
  background on iOS — visibly inconsistent with the `Form`-based Settings and the `List`-based Smart
  Views screens. (macOS was unaffected: a plain `ScrollView` there already shows the window background,
  matching the other tabs.)
- **A shared `groupedBackgroundStyle()` view modifier** lives in `PlatformModifiers.swift` (where the
  repo concentrates `#if os` chrome): iOS uses `Color(uiColor: .systemGroupedBackground)`, macOS
  `Color(nsColor: .windowBackgroundColor)` — `.systemGroupedBackground` is UIKit-only, so an inline
  modifier wouldn't compile on macOS. Applied to both `AccountSettingsView` and `SmartViewFormView`; the
  second call site is what confirmed this is a reusable pattern rather than a one-off paint job.

## Tag count badge (native apps)

- **The plain tag-count number in the sidebar tag tree is now a styled badge that surfaces archived
  items.** `Tag` gains a second count: `count` is the active (non-archived) bookmarks carrying the tag,
  `totalCount` includes archived ones (the badge derives "has archived items" inline as `totalCount >
  count`). `TagRepository.derive()` computes both in one pass over the local SwiftData store — `fetchActive()`
  already excludes soft-deleted records (`locallyDeletedAt == nil`), so it just splits each tag's tally
  by `isArchived`. The tag map is keyed off the total tally so a tag whose bookmarks are *all* archived
  still appears (active 0, total N). The backend `/tags` endpoint and StashKit `TagDTO` are unchanged —
  they return the active count only; `totalCount` is a purely client-side derivation (the DTO init sets
  both equal).
- **`TagNode` / `FlatTagNode` propagate both counts.** `TagNode` gains `totalCount: Int?` (still `nil`
  for synthetic parents); its initializer defaults `totalCount` to `nil` so `TagPickerSheet`'s
  `filtered()` rebuild — which doesn't carry the total — keeps compiling unchanged. `hierarchy()` builds
  a parallel `totals` dictionary alongside `counts`.
- **`TagCountBadge` (`Common/Views/`) is the shared badge.** The colour language is consistent: accent
  always means "visible", dimmed always means "hidden/archived". A plain **accent** capsule (white text)
  when `count == totalCount` (everything is visible); a split pill when `totalCount > count` — accent
  left half (visible count, white text), a hairline divider, and a muted right half showing the
  **hidden** count (`totalCount - count`), *not* the total. So `4|2` reads "4 visible, 2 hidden" with no
  mental math, and an all-archived tag reads `0|5`.
- **`TagTreeLabel` gained `showsCountBadge` (default `false`).** The three sidebar call sites (iPhone
  size-class sidebar `MainView`, the Tags tab `TagBrowserView`, and the macOS `MacContentView`) opt in
  with `showsCountBadge: true` to render the badge. `TagPickerSheet` is deliberately left untouched: it
  uses the default, showing the active count as plain text — a picker is about finding and selecting
  tags, so archival state is not relevant there. Defaulting to `false` is what keeps the picker's call
  site (and behavior) unchanged while the sidebars opt in.

## Tag count badge (web frontend)

- **The web `/app` sidebar tag tree gained the same split count badge** so the web UI reads identically
  to the native apps. Previously the sidebar showed a single muted `(N)` per tag where `N` was the
  *total* (active + archived) tally — misleading, since the list itself defaults to active-only. The
  count is now split the same way the native apps split it: `count` is the visible (non-archived) tally,
  `totalCount` includes archived, and the badge is accent-visible / muted-hidden.
- **`SidebarTag` carries `count`, `totalCount`, and a precomputed `hiddenCount`** (`totalCount - count`).
  Leaf has no arithmetic, so the hidden tally is computed server-side rather than in the template.
  `AppWebController.sidebarTags` tallies both maps in its single pass over the user's bookmarks (every
  tag into `totalCounts`, non-archived also into `counts`); `buildSidebar` iterates `totalCounts.keys`
  (the superset) so an all-archived tag still produces a row. Synthetic parents — slugs with no exact
  bookmark — land at `totalCount == 0` and render no badge, matching the native `count == nil` rule and
  the prior `count > 0` guard.
- **The badge is pure CSS in `stash.css` (`.count-badge` / `.count-badge.split`)**, reusing `--accent`
  for the visible half and `--tag-bg` / `--text-muted` for the hidden half — the same colour language as
  `TagCountBadge` (accent = visible, muted = hidden). The Views section (All / Untagged / Today / This
  Week) keeps its plain `(N)` count: those are not real tags and the native Views rows carry no badge
  either.

## Sidebar selection occasionally stops refreshing the detail list

- **Problem.** On the iPad (`SidebarSplitView`) and macOS (`MacContentView`) split views, the sidebar
  selection would, intermittently, stop driving the detail list: tapping a different tag/View
  re-highlighted the sidebar row but the bookmark list never changed, and once it happened it stayed
  stuck for every subsequent selection until the app was relaunched. Hard to reproduce because it is
  navigation-history- and timing-dependent.
- **Root cause — not a missing reload trigger.** The reload path was already wired
  (`BookmarkListContent.onChange(of: source)` → `reload()`), and `BookmarkRepository.load` is synchronous
  main-actor work (it filters the local store), so whenever that fires the list *does* update. The
  fragility was the detail column: `detail: { NavigationStack { makeDetail() } }` had **no stable
  identity and no path binding**, while two things mutated the stack's *root*: `makeDetail()` returns
  `BookmarkListView` from two distinct `if/else` branches (`.smartView` vs the tag list — separate
  `_ConditionalContent` identities), and bookmark rows push `BookmarkDetailView` *into* that same stack
  via closure-based `NavigationLink`s. Changing the selection while a detail was pushed (or across the
  Smart View ↔ tag branch flip) swapped the stack's root underneath its pushed view; with nothing keying
  the stack, its internal navigation state desynced from the swapped root and wedged. After that the
  root list was no longer re-presented, so further selection changes updated `selection` (sidebar
  highlight) but never refreshed the detail column.
- **✅ Fix — key the detail `NavigationStack` to the selection.** Both split views apply
  `.id(selection)` to the detail `NavigationStack`. Each selection now deterministically builds a fresh
  stack — discarding any pushed `BookmarkDetailView` and any wedged state — with a fresh
  `BookmarkListView` that loads the new filter from its initial `.task`. This is the idiomatic pattern
  for a selection-driven detail column and has the welcome side effect that selecting a new tag resets
  the detail to the top of that tag's list (and clears the per-tag search), rather than stranding a
  pushed detail from the previous selection. The in-place `onChange(of: source)` reload becomes
  redundant for selection changes (source is now fixed per stack identity) but is harmless and left in
  place. Scope: one line each in `MacContentView` and `MainView`; no repository, StashKit, or backend
  change.

## Visual polish — bookmark list mirrors the native row (web frontend)

- **✅ The `/app` bookmark list now reads with the same content-first hierarchy as the native apps'
  `BookmarkRowView`** (see *Visual polish — bookmark list, detail, empty states (native apps)*). A
  presentation-only pass on `app-bookmarks.leaf` rows — no new fields, no controller, StashKit, or
  backend change; the same context (`faviconDomain`, `tags[].display`, `description`, `createdAt`) feeds
  the new layout.
- **Domain replaces the full URL as the row's source line.** The prominent green full-URL line under the
  title is gone; in its place a muted **domain eyebrow** (`favicon + faviconDomain`) sits *above* the
  title — more scannable and meaningful, matching the native row's domain anchor. The domain still links
  to the bookmark's URL (`target=_blank`); the title links to the `/app` detail page as before.
- **Typographic hierarchy.** Title is the hero (`1.1rem`, weight `600`); domain and date are quiet
  `0.8rem` `--text-muted`; description stays readable (`--text-2`) but is sized down to `0.9rem` and
  clamped to two lines (`-webkit-line-clamp`) so rows stay even. Per the answered design choice the web
  keeps the description and date that the native row omits — the web is a denser reading surface.
- **Tags are text-only in the list.** Scoped `.list-item .tags .tag` overrides drop the filled capsule to
  muted middot-separated text links (`background: none`, `--text-muted`, accent + underline on hover),
  mirroring the native row's `isPlain` tags. The capsule `.tag` style is unchanged everywhere else (the
  "Filtered by tag" pill, the tag browser). The `swift › server` display rendering is untouched.
- **Cards retained.** Per the answered design choice the rows keep their bordered-card container
  (`--surface` + border + radius) rather than switching to hairline dividers — only the inner hierarchy
  changed. The detail page (`app-bookmark-detail.leaf`) is unchanged and still shows the full URL via the
  retained `.url` style.

## Tag sidebar refreshes after a sync (not just after a local write)

A bug closing the Phase 3/4 "cross-repository live-refresh-on-sync" limitation, scoped to the tag list.

- **Symptom.** After launch (or a manual "Sync Now" / pull-to-refresh / reconnect), the bookmark list
  updated with newly pulled bookmarks, but the **sidebar tag list did not** — a bookmark synced in with a
  brand-new tag showed in the list while its tag was missing from the Views/Tags sidebar. The tag only
  appeared after fully quitting and relaunching the app.
- **Root cause.** `TagRepository` derives its tags from the local store and is a shared singleton, but
  the sidebars (`SidebarSplitView`, `MacContentView`, `TagBrowserView`) only called `load()` once on
  appearance (a no-op after the first derive) — they never re-derived when a sync mutated the store. Only
  *local* bookmark writes refreshed it (`AddBookmarkSheet`, `EditBookmarkView`, the tag drop modifier all
  call `tagRepository.refresh()`). A sync's pulled changes had no such trigger, so the cached tag tree
  went stale. `BookmarkListView` already had the right pattern — `.onChange(of: syncEngine.isSyncing)`
  re-filtering the list when a cycle ends — but no sidebar mirrored it for tags.
- **✅ Fix — refresh tags when a sync completes.** Each of the three tag sidebars now re-derives its tags
  on the sync engine's syncing-to-idle transition. `refresh()` re-derives from the local store and leaves
  the current tags visible until the new set is ready (no empty flash). Scope: the two split-view sidebars
  (`MainView`, `MacContentView`) and the iPhone Tags tab (`TagBrowserView`); no repository, StashKit, or
  backend change. The pending-row cross-repository limitation noted in Phase 4 is unrelated and still
  stands.
- **✅ Shared `.onSyncCompleted` modifier (cleanup).** The observation was originally a near-identical
  `onChange(of: syncEngine.isSyncing)` block inlined at each call site — three new copies plus the one
  `BookmarkListView` already had. All four now use a single `.onSyncCompleted { … }` view modifier
  (`Stash/Support/SyncModifiers.swift`, app-only since it reads `AppEnvironment` — which the shared
  `Common/` target lacks). The per-view opt-in is kept deliberately (views own their refresh triggers, per
  Phase 3/4); the modifier only removes the duplication, it does not centralize the trigger into
  `SyncEngine`.

## Per-machine signing & bundle identifier (xcconfig)

The maintainer builds the app under two different Apple developer accounts on two machines — one uses
the `cc.otavio.stash*` bundle prefix, the other `com.otaviocc.stash*`. Previously the team id and the
prefix were hardcoded throughout the committed `Stash.xcodeproj`, four entitlements, four `Info.plist`s,
and several Swift constants, so switching machines meant editing tracked files (and risking a commit of
the wrong account).

- **✅ One source of truth — `StashApp/Config/Stash.xcconfig`.** A committed base xcconfig defines two
  settings: `STASH_BUNDLE_PREFIX` (the reverse-DNS org prefix, everything before `.stash`) and
  `DEVELOPMENT_TEAM`. It is wired as the `baseConfigurationReference` on the **project-level** Debug/Release
  configs, so both targets inherit the values. The committed defaults (`cc.otavio` / `S9X9XY5GF8`) keep the
  primary machine building with no extra file.
- **Machine-local override via optional include.** The base xcconfig ends with
  `#include? "Stash.local.xcconfig"` — the `?` makes it optional. A second machine drops a gitignored
  `Config/Stash.local.xcconfig` (templated by the committed `Stash.local.xcconfig.example`) overriding
  either setting; it wins when present and is silently absent otherwise. `Stash.local.xcconfig` is in the
  root `.gitignore`.
- **The prefix drives every bundle-keyed identifier in lockstep.** `PRODUCT_BUNDLE_IDENTIFIER` for the app
  (`$(STASH_BUNDLE_PREFIX).stash`) and extension (`…​.stash.ShareExtension`) reference it directly; the
  four entitlements declare the App Group as `group.$(STASH_BUNDLE_PREFIX).stash`; the two app `Info.plist`s
  build the `BGTaskSchedulerPermittedIdentifiers` and the exported `UTType` from it. Build-setting
  substitution in entitlements/plists is standard Xcode behaviour (the "Process Product Packaging" step).
- **Runtime reads it back, never hardcodes it.** Each `Info.plist` carries `STBundleBase =
  $(STASH_BUNDLE_PREFIX).stash`. `AppGroup.bundleBase` reads that key from `Bundle.main` (fallback
  `cc.otavio.stash` for previews, which have no bundle) and **derives** `AppGroup.identifier` (the App
  Group / Keychain access group / defaults suite), the token/cursor keys, `BackgroundSyncScheduler.taskIdentifier`,
  and `UTType.stashBookmark`. So the build settings and the Swift constants can never drift — change the
  one xcconfig line and the whole graph follows. The Keychain item *account names* and the
  `UserDefaults` suite both move with the prefix; the actual cross-process sharing is scoped by the App
  Group, which is the same derived value in both processes.
- **Verified.** `xcodebuild -showBuildSettings` resolves the prefix, team, and bundle IDs at the target
  level (proving project→target inheritance); the built `Info.plist`s show `cc.otavio.stash`-derived
  values; and a temporary `Stash.local.xcconfig` flips the resolved prefix to `com.otaviocc.stash` and the
  team, confirming the override path. Builds clean on iOS and macOS; the token-key *names* changing shape
  per machine is harmless (they are account names within the App Group, not OS-registered identifiers).

## Bookmark row tags — accent capsules (native apps)

- **✅ The list row's tags now use the accent-tinted capsule `TagPill`, not the plain text-only
  variant.** The row was otherwise colourless — grey domain, primary title, secondary description,
  `.tertiary` text tags — with the favicon the only spot of colour. Dropping `isPlain: true` in
  `BookmarkRowView.makeTags()` gives the row a deliberate touch of the app accent while keeping the
  content-first typographic hierarchy intact (the capsule is `.caption2`, still the smallest, quietest
  line). This reverses the earlier *Visual polish — bookmark list* call ("Tags text-only in the list
  row; styled capsule retained in the detail view"); the row and detail view now share the one styled
  treatment, so a tag reads identically everywhere.
- **Scope.** One line in `BookmarkRowView`; `TagPill`'s `isPlain` parameter is retained (still used by
  other call sites). The `swift › server` rendering and 3-tags-+N overflow are unchanged. No backend /
  StashKit / CLI / web changes; builds clean on macOS.

## Documentation — Podman runtime & local-dev compose override

- **✅ Podman documented as a supported container runtime alongside Docker.** `Docs/backend-docker.md`
  now lists Podman 4+ as a prerequisite option and adds a *Running with Podman* section. Rationale:
  Podman is API-compatible, so the published image and committed `docker-compose.yml` run unchanged —
  the only work is on the operator's machine (point the `docker` CLI at Podman's socket, or use `podman
  compose`), so **nothing in the repo changes** to support it. The committed Makefile and compose files
  stay Docker-native by design (CI builds/pushes the image with Docker buildx on GitHub runners, and the
  published artifacts are unaffected); documenting Podman at the CLI level rather than editing the
  Makefile keeps a personal-machine runtime choice out of shared code. The macOS/Windows `podman machine
  start`-after-reboot caveat is called out (no always-on daemon like Docker Desktop). Machine-specific
  setup troubleshooting (provider choice, stale forwarder processes) is deliberately kept out of the
  user guide.
- **✅ The local-dev compose override is now documented.** `Docs/backend-docker.md` gains a *Local
  development (build from source)* section explaining `Backend/docker-compose.override.yml` — Compose
  auto-merges it from `Backend/`, switching the `app` service from `ghcr.io/otaviocc/stash:latest` to a
  build of the working tree (`image: stash-local` + `build: .`) — and how the `Backend/Makefile` targets
  (`make build-up`, `up`/`down`/`logs`/`migrate`) wrap it. Previously this workflow lived only in the
  Makefile and `CLAUDE.md`, not the user-facing docs.
- **Scope.** Docs only — two sections plus a prerequisite line in `Docs/backend-docker.md`. No new doc
  file (so no root `README.md` table entry), and no code, Makefile, or compose changes.
