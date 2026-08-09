# AGENTS.md

Self-hosted bookmark manager: a Swift/Vapor backend plus native Apple clients,
a CLI, and a browser extension. This is a multi-package monorepo, **not** one
build. See `PRODUCT.md` (what it is) and `DECISIONS.md` (why it's built this
way, and hard-won gotchas; read the relevant section before touching a
subsystem). Both are **indexes**: the actual content lives in topical
`Docs/product-*.md` and `Docs/decisions-*.md` files; open the one that matches
the subsystem you're working on.

## Repository layout (independent build units)

| Dir | Build | Toolchain |
|-----|-------|-----------|
| `Backend/` | Vapor 4 REST API + Leaf `/admin` & `/app` web UIs. SwiftPM. | Swift tools 5.9, ships on **Swift 6.1** (see CI note) |
| `StashKit/` | Shared Swift package: DTOs, request factories, thin `StashClient`. | Swift tools 6.2, iOS/macOS 26 |
| `CLI/` | `stash` command-line tool (separate package, not in the Xcode project). | Swift tools 6.2, macOS 26 |
| `StashApp/` | `Stash.xcodeproj`: iOS + macOS app + Share Extension. | Xcode 26 |
| `Extension/` | Firefox/Chrome WebExtension. Plain HTML/JS, **no build step**. | — |

## Commands (run from the listed directory)

```bash
# Backend
cd Backend && swift build -c release
cd Backend && swift test --no-parallel                     # in-memory SQLite; NO Postgres needed
cd Backend && swift test --no-parallel --filter <TestName> # single test/suite
cd Backend && swiftlint lint && swiftformat --lint .

# StashKit / CLI
cd StashKit && swift build && swift test
cd CLI && swift build -c release

# App (build == the regression check; there are no app unit tests)
cd StashApp && xcodebuild -scheme Stash -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
cd StashApp && xcodebuild -scheme Stash -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO

# Extension (validate, don't build)
cd Extension && make lint
```

`Backend/` and `Extension/` have a `Makefile` (`make help`). `Backend` also has
`make build`/`test` as shortcuts for the two commands above, and
`make up/down/logs/migrate`/`build-up` for the Docker stack.

## Critical gotchas

- **Backend tests must run serially in CI**: `swift test --no-parallel`.
  Parallel runs boot many apps hashing at bcrypt cost 12 and starve the SQLite
  connection pool → spurious connection timeouts. Local multi-core Macs mask
  this; CI does not.
- **Backend toolchain is Swift 6.1, not latest.** Swift 6.2.1's release
  optimizer crashes compiling Vapor under `-c release`. CI tests in plain debug.
- **SQLite (tests) vs Postgres (prod) diverge.** JSON/array columns, multi-column
  `ALTER TABLE` (SQLite allows only one `ADD COLUMN` per statement), and
  `VACUUM`-in-transaction all pass on SQLite but fail on Postgres. Verify
  schema/migration and raw-SQL changes against real Postgres, not just the suite.
- **App has no unit tests by design** (Docs/product-technical.md §19.6). CI build-verifies both
  platforms instead. StashKit uses mocked `URLSessionProtocol` tests; CLI is
  manual-integration only.
- **`openapi.yaml` is hand-written** (`Backend/Public/openapi.yaml`). Any change
  to the `/api/v1/` surface (endpoint, field, status, error code) MUST update it
  in the same change. `/admin` and `/app` are web-only and not in the spec.

## Conventions (differ from defaults)

- **SwiftLint + SwiftFormat, each component has its own configs.** `swiftlint
  lint` must report 0 violations; `swiftformat --lint` must be idempotent.
- **No comments inside function/method bodies** (backend tests' `// Given / //
  When / // Then` markers are the only exception). Doc comments only at
  declaration level. American English throughout.
- **Tests: Given/When/Then structure, `#expect` with "It should …" descriptions**
  (swift-testing + VaporTesting, not XCTest).
- **StashKit is deliberately logic-free**: DTOs + request factories + thin client
  only. No token storage, no refresh, no business logic; those live in each
  client's own layer (and are intentionally duplicated across app/CLI/extension).
- **Per-file license header is enforced via each `.swiftformat`'s `--header`**
  (`Backend` = AGPL-3.0-only, everything else = MIT). Don't hand-edit headers.
- **Never regenerate `Stash.xcodeproj`.** XcodeGen was retired; the project is
  committed and uses synchronized folder groups (folder = target membership:
  `Common/` → app + extension, `Stash/` → app only, `StashShareExtension/` →
  extension only). Editing `.pbxproj` via `plutil`/PlistBuddy breaks it.

## Commit messages

Follow the seven rules (cbea.ms/git-commit); nothing enforces this, it's
discipline:

- Subject: imperative mood ("Add", "Fix", not "Added"/"Adds"), capitalized,
  ≤50 chars, no trailing period. Verified by `git log`.
- Blank line between subject and body; wrap the body at 72 chars.
- Body explains what and why, not how. A single cohesive change gets prose;
  a commit grouping several distinct changes gets `-` bullets.

## Keep the product spec and decision log current

When a change alters product behavior or reflects a non-obvious design choice,
record it in the same change: these docs are living records, not
after-the-fact writeups:

- **Product behavior change** (a feature, an endpoint, a field, a rule, a
  UI/UX change): update the relevant `Docs/product-*.md` file, and its
  `PRODUCT.md` index entry if the summary no longer fits. A change to the
  `/api/v1/` surface must also update `Backend/Public/openapi.yaml` (see above).
- **A design decision, deviation, trade-off, or reversal**: append an entry to
  the matching `Docs/decisions-*.md` file (add a `## ` heading; keep entries in
  chronological order within the file), and add a one-line pointer in the
  `DECISIONS.md` index. Don't rewrite history: a reversed decision gets a new
  entry marked *Superseded* pointing to what replaced it, per the log's own
  conventions.
- Not every change needs an entry (a pure refactor, a typo fix, a lint tweak
  usually doesn't). Record what a future reader would otherwise have to
  reverse-engineer.

## StashApp signing / identifiers

Team ID and bundle prefix are **not** hardcoded; they come from
`StashApp/Config/Stash.xcconfig` (`STASH_BUNDLE_PREFIX`, `DEVELOPMENT_TEAM`).
`STASH_BUNDLE_PREFIX` drives every bundle-keyed identifier (bundle IDs, App
Group, Keychain access group, background-task id, drag UTType) in lockstep. To
build under a different account, create a gitignored
`StashApp/Config/Stash.local.xcconfig` override; do not edit `Stash.xcconfig`.

## Release

Driven by pushing a `v*.*.*` tag (must have leading `v` and three parts).
`Script/bump-version.sh --backend X.Y.Z --app X.Y` bumps `Backend/VERSION` (baked
into the image), the four `StashApp/Config/*-Info.plist`, and
`Extension/manifest.json` together. Commits/branches never publish; only the tag
does. See `Docs/releasing.md`.
