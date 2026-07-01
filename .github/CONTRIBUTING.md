# Contributing

Thanks for considering a contribution to Stash.

## Repository layout

Stash is a self-hosted, multi-user bookmark manager. The repo is a monorepo of four Swift
components plus a browser extension, all speaking to one backend contract:

- **`Backend/`** — Vapor 4 REST API (`/api/v1/`) **plus** server-rendered Leaf web UIs (admin
  dashboard at `/admin`, user frontend at `/app`). Postgres in production, in-memory SQLite in
  tests. swift-tools 5.9. `Sources/App/` is organized **by surface**: `API/` (the JSON `/api/v1`
  contract the clients depend on — controllers + wire DTOs, mirrored by `Public/openapi.yaml`),
  `Web/` (the Leaf `/admin` + `/app` + landing UIs), and `Core/` (the shared domain — `Models/`,
  `Migrations/`, `Services/`, `Auth/`, `ImportExport/`, `Extensions/`, `Middleware/`, `Errors/`, plus
  `Support/` for stateless helpers). It's a single Swift module, so the split is organizational only.
  Inside `Web/`, controllers are **one `RouteCollection` per domain** mirroring the API side
  (`BookmarkWebController`, `SmartViewWebController`, `TagWebController`, `SettingsWebController`,
  `AppAuthWebController` for `/app`; `AdminWebController` for `/admin`), wired in `routes.swift`. Pure
  Leaf-context shaping lives in `Web/Presenters/` (`BookmarkPresenter`, `SmartViewPresenter`,
  `TagPresenter` — `enum` namespaces of `static` funcs, no request/DB) and cross-controller glue in
  `Web/Support/` (`Request+RenderHTML`, `FlashMessage`, `AppSidebarLoader`, `KnownTags`). See
  `DECISIONS.md`.
- **`StashKit/`** — shared Swift package: `Codable` DTOs, one request-factory `enum` per API domain,
  and a thin `StashClient` over [`MicroClient`](https://github.com/otaviocc/MicroClient). swift-tools 6.2, iOS 26 / macOS 26.
- **`CLI/`** — the `stash` command-line client (`ArgumentParser` + StashKit). swift-tools 6.2.
- **`StashApp/`** — **two** multiplatform targets: one SwiftUI app (`Stash`, iOS **and** macOS) and one
  Share Extension (`StashShareExtension`, iOS **and** macOS). `Stash.xcodeproj` is committed and uses
  synchronized folder groups.
- **`Extension/`** — a Manifest v3 WebExtension (Firefox + Chrome/Zen) that saves the current page over
  the REST API. Plain HTML/CSS/vanilla JS, **no build step, no npm** — the same philosophy as the web UI.

`PRODUCT.md` is the product spec; `DECISIONS.md` is the running decision log (what was built, why,
and every deviation from the spec) — most of the non-obvious rationale lives there rather than in
code comments, so it's worth a read before non-trivial work. The `Docs/` folder holds the
user-facing documentation (build, run locally, deploy via Docker, HTTPS with Caddy, configuration,
the REST API, the CLI, the apps, StashKit, and the browser extension) — all user-facing docs live
there, one guide per concern, rather than a per-component `README.md`. A new component or feature
gets a `Docs/<topic>.md` linked from the root `README.md` table. `StashSkill/` is a separate case:
it's a committed AI coding assistant skill (`stash-cli`) that documents how to drive the `stash`
CLI, derived from the CLI source rather than the spec — see `StashSkill/README.md` for how it's
meant to be installed and used.

## Building and testing

Each component is its own package/project — see the matching guide under
[`Docs/`](https://github.com/otaviocc/Stash/tree/main/Docs) before you start:

- Backend — [`Docs/backend-build.md`](https://github.com/otaviocc/Stash/blob/main/Docs/backend-build.md)
- CLI / StashKit — [`Docs/cli-build.md`](https://github.com/otaviocc/Stash/blob/main/Docs/cli-build.md),
  [`Docs/stashkit.md`](https://github.com/otaviocc/Stash/blob/main/Docs/stashkit.md)
- iOS / macOS apps — [`Docs/mobile-build.md`](https://github.com/otaviocc/Stash/blob/main/Docs/mobile-build.md)
- Browser extension — [`Docs/browser-extension.md`](https://github.com/otaviocc/Stash/blob/main/Docs/browser-extension.md)

CI (`.github/workflows/ci.yml`) runs three jobs — `backend`, `apple`, `extension` — matching
those same components. Your change should pass whichever job(s) it touches.

## Architecture notes

A few cross-file conventions that aren't obvious from any single file:

- **StashKit is deliberately thin.** It decodes wire-shape DTOs and stops there — no token
  storage, no silent refresh, no DTO→domain mapping, no business logic. A
  `tokenProvider: @Sendable () async -> String?` closure keeps it storage-agnostic.
  `StashClient.run` maps non-2xx responses (the `{ error, code, message, existingID? }` envelope)
  to a typed `StashAPIError`. Everything stateful is the client's job.
- **The client layering is: StashKit DTOs → Repository → View.** In both the app and CLI, a
  repository layer owns DTO→domain mapping, session state, the tag cache, and silent refresh. In
  the app, silent refresh is centralized behind a one-method `SessionRefreshing` protocol —
  `AuthRepository.authorizedClient()` — so other repositories get a fresh token without a
  reference cycle; every authenticated call goes through it first. The returned `AuthorizedClient`
  refreshes proactively when the token is expiring soon and, on a definitive auth failure from the
  server, forces one refresh and retries once before giving up.
- **The 2FA login branch forces a direct `MicroClient` dependency** in both the app and CLI (on top
  of StashKit). `POST /auth/login` returns *either* a token pair *or* `{ requires2FA, tempToken }`,
  both as HTTP 200; StashKit's typed `makeLoginRequest` is `TokenPairDTO`-only, so those clients
  build that one request directly to decode both shapes.
- **StashApp source layout** (folders map to synchronized-folder groups → target membership is
  folder-level):
  - `StashApp/Common/` — compiled into both targets, app + extension (KeychainStore, TokenManager,
    StashClientProvider, domain models, error mapping, and the shared `AddBookmarkView`). Tag
    editing on the add/edit forms is `TagPickerSheet` (`Common/Views/`) — a read-only `TagPill`
    summary plus an "Add Tags" button presenting the always-expanded, indented hierarchical tag
    tree with single-tap toggle and search-as-create. `TagSuggestionView` (inline autocomplete
    chips) is retained only for `SmartViewFormView`'s single-tag condition field.
  - `StashApp/Stash/` — app-only code (`Persistence/` for the SwiftData layer, `Repositories/`,
    `Sync/`, `Support/`, `Views/`, plus the single `@main StashApp` whose scene `body` branches
    with `#if os(macOS)`). `RootView` routes to `MainView` (iOS: size-class split / tab bar) or
    `MacContentView` (macOS: `NavigationSplitView`).
  - `StashApp/StashShareExtension/` — the multiplatform extension; the platform-specific principal
    controllers (`ShareViewController` iOS / `MacShareViewController` macOS) are `#if`-guarded in
    one folder.
  - `StashApp/Config/` — non-synced per-platform `Info.plist`/entitlements, selected by
    SDK-conditional build settings, kept out of the synced folders so the app/extension are each
    one multiplatform target with no membership exceptions.
  - Bookmark navigation uses closure-based `NavigationLink { Detail }` (not
    `navigationDestination(for:)`), deliberately — the list view is reused at several stack depths
    and a declared destination misroutes taps.
- **App ↔ Share Extension sharing** goes through an App Group: the access/refresh tokens via a
  Keychain access group, and the configured server URL via the group's `UserDefaults` suite (a
  separate process can't see `UserDefaults.standard`). The `AppGroup` enum is the single source for
  the group id and all keys. Extensions are process-isolated — they build their own lightweight
  repositories rather than sharing the app's live `@Observable` instances.
- **Backend conventions worth knowing before editing it:**
  - Tests use a local `withTestApp { app in … }` helper, not VaporTesting's `withApp` (the latter
    silently skips `asyncBoot()` and every route 404s — see `Tests/AppTests/TestHelpers.swift`).
  - Tags are normalized on write (trimmed, lowercased, de-duplicated) and stored twice: the
    canonical `tags` array plus a derived pipe-wrapped `tags_search` column
    (`|swift|swift/vapor|`) that makes the hierarchical prefix filter a portable `LIKE` across
    SQLite and Postgres.
  - The JWT API (`/api/v1/`) and the two web UIs are independent: the web UIs use separate
    in-memory session cookies (`stash_admin_session`, `stash_session`), not the JWT flow.
  - **The OpenAPI spec is part of the API contract — keep it in lockstep.**
    `Backend/Public/openapi.yaml` is the machine-readable description of the `/api/v1/` +
    `/health` surface. Any change to that surface — a new/removed endpoint, a renamed or added
    field, a changed status code, a new error case, a new query param — must update
    `openapi.yaml` in the same commit. The spec mirrors the backend `Content` response structs
    and StashKit DTOs; keep all three in agreement. After editing, re-validate with
    `cd Backend && npx @apidevtools/swagger-cli validate Public/openapi.yaml`. See
    `Docs/api-openapi.md`.
  - TOTP (RFC 6238) + Base32 are implemented on `swift-crypto` directly, since a Vapor-4-compatible
    auth package with TOTP support doesn't exist — see `DECISIONS.md`.
  - Site-wide appearance (accent theme, about text, footer link) is a single-row `SiteSettings`
    table edited from the admin `/admin/appearance` page. `SiteSettingsService` keeps an
    app-level, lock-guarded cache so page renders never hit the DB.
- **Browser extension conventions** (`Extension/`): `background.js` is the single owner of token
  storage, silent refresh, and the 2FA login branch — `popup.js`/`options.js` never touch
  `chrome.storage` for tokens; they go through it via `chrome.runtime.sendMessage`. The manifest
  declares both `background.service_worker` (Chrome) and `background.scripts` (Firefox/Zen — it
  rejects a service-worker-only manifest); keep both keys when editing. Icons are generated from
  `icons/icon.svg` by `icons/generate-icons.py` (Pillow) — regenerate, don't hand-edit PNGs.

## Code style

Backend and app code is formatted with `swiftformat` and linted with `swiftlint`; both must
report clean (`swiftformat . --lint`, `swiftlint lint`, run from within `Backend/` or
`StashApp/`). The browser extension has no build step — `make lint` in `Extension/` is the
CI gate there. A few conventions the linters don't fully cover:

- American English; `///` doc comments are allowed on declarations — types, properties, and
  methods/functions — but no comments of any kind inside a method/function body, neither `//`
  nor `///`; all documentation lives at the declaration level. (The one exception is the backend
  tests' `// Given` / `// When` / `// Then` structure markers.)
- Blank line after the last `guard` in a group; blank line before `if`/`for`/`switch` and before
  a `return` in a multi-statement body.
- SwiftFormat type-mode organization (`Nested Types → Static → Properties → Computed → Lifecycle →
  Functions`, public before private).
- SwiftUI views decompose with `make…() -> some View` functions, never computed-`var` subviews.
  Keep `var body` a small composition of `make…()` calls; name each piece `make` + what it
  produces (`makeEmptyState()`, `makeRowContextMenu(for:)`); add `@ViewBuilder` only when the body
  branches (`if`/`switch`) or returns sibling views.
- Commit messages follow [the seven rules](https://cbea.ms/git-commit/): imperative, capitalized,
  period-free subject ≤ 50 chars; blank line; body wrapped at 72 explaining *why*.

## Docs

If your change affects the API surface, update `Backend/Public/openapi.yaml` in the same
commit. If it changes user-facing behavior, update the relevant guide under `Docs/`.

## Pull requests

Keep PRs focused on one change. Commit messages follow
[the seven rules](https://cbea.ms/git-commit/): imperative, capitalized, period-free subject
line ≤ 50 chars, with a body explaining *why*.
