# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Stash is a self-hosted, multi-user bookmark manager. The repo is a monorepo of four Swift
components that all speak to one backend contract:

- **`Backend/`** — Vapor 4 REST API (`/api/v1/`) **plus** server-rendered Leaf web UIs (admin
  dashboard at `/admin`, user frontend at `/app`). Postgres in production, in-memory SQLite in
  tests. swift-tools 5.9.
- **`StashKit/`** — shared Swift package: `Codable` DTOs, one request-factory `enum` per API domain,
  and a thin `StashClient` over [`MicroClient`](https://github.com/otaviocc/MicroClient). swift-tools 6.2, iOS 26 / macOS 26.
- **`CLI/`** — the `stash` command-line client (`ArgumentParser` + StashKit). swift-tools 6.2.
- **`StashApp/`** — **two** multiplatform targets: one SwiftUI app (`Stash`, iOS **and** macOS) and one
  Share Extension (`StashShareExtension`, iOS **and** macOS). `Stash.xcodeproj` is committed and uses
  synchronized folder groups.

**`PRODUCT.md` is the product spec; `DECISIONS.md` is the running decision log** (what was built,
why, and every deviation from the spec). Read both before non-trivial work, and **add an entry to
`DECISIONS.md` when completing a milestone or a meaningful chunk** — much of the non-obvious rationale
lives only there. `Backend/README.md` and `CLI/CLAUDE.md` document those components in depth.

## Build / test / lint

Each component is its own Swift package or Xcode project — `cd` into it first.

**Backend** (`cd Backend`):
```sh
swift build && swift test            # tests need no database (in-memory SQLite)
swift test --filter <TestName>       # run a single test / suite (swift-testing)
swift run App serve                  # needs DATABASE_URL, JWT_SECRET, ADMIN_USERNAME, ADMIN_PASSWORD
make up | down | logs | migrate      # docker compose workflow (see Backend/README.md)
```

**StashKit** (`cd StashKit`) / **CLI** (`cd CLI`):
```sh
swift build      # CLI release binary: swift build -c release → .build/release/stash
swift test --filter <TestName>   # StashKit only; CLI has no unit tests
```

**StashApp** (`cd StashApp`) — `Stash.xcodeproj` is **committed** (open it directly; no generation step).
The `Stash` app target is multiplatform — the **same scheme** builds iOS and macOS, selected by destination:
```sh
xcodebuild -scheme Stash -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO
xcodebuild -scheme Stash -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```
Add/move/rename source files in Xcode (the project uses synchronized folder groups, so files on disk are
picked up automatically — no per-file project edits). `xcuserdata/` is gitignored; the `Stash` shared
scheme is committed.

**Lint** (run inside each component dir; both `Backend/` and `StashApp/` carry their own configs):
```sh
swiftformat . --lint     # must be idempotent
swiftlint lint           # must report 0 violations
```

## Architecture notes that span multiple files

**StashKit is deliberately thin.** It decodes wire-shape DTOs and stops there — **no token storage,
no silent refresh, no DTO→domain mapping, no business logic.** A `tokenProvider: @Sendable () async -> String?`
closure keeps it storage-agnostic. `StashClient.run` maps non-2xx responses (the
`{ error, code, message, existingID? }` envelope) to a typed `StashAPIError`. Everything stateful is
the client's job.

**The client layering is: StashKit DTOs → Repository → View.** In both the app and CLI, a repository
layer owns DTO→domain mapping, session state, the tag cache, and silent refresh. In the app, silent
refresh is centralized in `AuthRepository.refreshIfNeeded()` behind a one-method `SessionRefreshing`
protocol (so other repositories get a fresh token without a reference cycle); every authenticated call
goes through it first.

**The 2FA login branch forces a direct `MicroClient` dependency** in both the app and CLI (on top of
StashKit). `POST /auth/login` returns *either* a token pair *or* `{ requires2FA, tempToken }`, both as
HTTP 200; StashKit's typed `makeLoginRequest` is `TokenPairDTO`-only, so those clients build that one
request directly to decode both shapes.

**StashApp source layout and cross-platform strategy** (folders map to synchronized-folder groups →
target membership is folder-level):
- `StashApp/Common/` — compiled into **both** targets, app + extension (KeychainStore, TokenManager,
  StashClientProvider, domain models, error mapping, and the shared `AddBookmarkView` /
  `TagInputSection`). (Previously named `Shared/`.)
- `StashApp/Stash/` — app-only code, including the single `@main StashApp` whose scene `body` branches
  with `#if os(macOS)` (macOS adds a `Settings` scene + window sizing). `RootView` routes to `MainView`
  (iOS: size-class split / tab bar) or `MacContentView` (macOS: `NavigationSplitView`). Its `Shared/`
  subfolder is app code shared between iOS and macOS.
- `StashApp/StashShareExtension/` — the (multiplatform) extension; the platform-specific principal
  controllers (`ShareViewController` iOS / `MacShareViewController` macOS) are `#if`-guarded in one folder.
- `StashApp/Config/` — **non-synced** per-platform `Info.plist`/entitlements, selected by SDK-conditional
  build settings (`INFOPLIST_FILE[sdk=macosx*]`, `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`). Kept out of the
  synced folders so the app/extension are each one multiplatform target with no membership exceptions.
- Keep platform divergence minimal: iOS-only field/keyboard/title modifiers are funneled through
  helpers in `Common/Support/PlatformModifiers.swift`; whole-view `#if` guards are reserved for genuine
  platform shells (e.g. `TabContainerView`, `MacContentView`, the principal view controllers).
- Bookmark navigation uses **closure-based** `NavigationLink { Detail }` (not `navigationDestination(for:)`),
  deliberately — the list view is reused at several stack depths and a declared destination misroutes taps.

**App ↔ Share Extension sharing** goes through the App Group `group.cc.otavio.stash`: the access/refresh
tokens via a **Keychain access group**, and the configured server URL via the group's **`UserDefaults`
suite** (a separate process can't see `UserDefaults.standard`). The `AppGroup` enum is the single source
for the group id and all keys. Extensions are process-isolated — they build their own lightweight
repositories rather than sharing the app's live `@Observable` instances.

**Backend conventions worth knowing before editing it:**
- Tests use a local **`withTestApp { app in … }`** helper, *not* VaporTesting's `withApp` (the latter
  silently skips `asyncBoot()` and every route 404s — see `Tests/AppTests/TestHelpers.swift`).
- Tags are normalized on write (trimmed, lowercased, de-duplicated) and stored twice: the canonical
  `tags` array plus a derived pipe-wrapped `tags_search` column (`|swift|swift/vapor|`) that makes the
  hierarchical prefix filter a portable `LIKE` across SQLite and Postgres. `__untagged__` is an internal
  filter sentinel.
- The JWT API (`/api/v1/`) and the two web UIs are independent: the web UIs use separate in-memory
  session cookies (`stash_admin_session`, `stash_session`), not the JWT flow.
- TOTP (RFC 6238) + Base32 are implemented on `swift-crypto` directly (the PRD's `vapor/auth` package is
  Vapor 3-era and doesn't exist for Vapor 4) — see `DECISIONS.md` / `Backend/README.md`.

## Code style (hand-applied conventions; see DECISIONS.md)

- American English; `///` doc comments on **types only** (not methods/properties); **no inline comments**
  inside method bodies.
- Blank line after the last `guard` in a group; blank line before `if`/`for`/`switch` and before a
  `return` in a multi-statement body.
- SwiftFormat type-mode organization (`Nested Types → Static → Properties → Computed → Lifecycle →
  Functions`, public before private). The app/CLI have **no unit tests** by design (manual/integration);
  the backend carries the test suite.
- **Commit messages follow the seven rules of [cbea.ms/git-commit](https://cbea.ms/git-commit/)**:
  imperative, capitalized, period-free subject ≤ 50 chars; blank line; body wrapped at 72 explaining
  *what/why*. Use prose for a single cohesive change, `-` bullets when grouping distinct changes.
