# Building the iOS and macOS apps

The native SwiftUI client for Stash. `Stash.xcodeproj` contains two
multiplatform targets that build for **both iOS and macOS**:

- **`Stash`** — the SwiftUI app (bookmark list, add/edit/detail, tags, Smart
  Views, search, settings, 2FA).
- **`StashShareExtension`** — a share extension for saving URLs from Safari and
  other apps.

The app talks to the backend over the REST API (`/api/v1/`) through the shared
[StashKit](stashkit.md) package.

## Prerequisites

- Xcode 26 or later (includes the iOS 26 SDK and the Swift 6.2 toolchain)
- macOS 26 or later (to build and run the macOS app)

No project-generation step is required — the Xcode project is committed to the
repo.

## Dependencies

Fetched automatically by Xcode (Swift 6.2, iOS 26 / macOS 26):

| Package | Purpose |
|---------|---------|
| [StashKit](stashkit.md) (local, `../StashKit`) | DTOs, request factories, thin HTTP client |
| [`otaviocc/MicroClient`](https://github.com/otaviocc/MicroClient) | Used directly for the 2FA-challenge login branch |

Both are resolved automatically when you open the project — no separate build
step.

## Open and build

```bash
cd stash/StashApp
open Stash.xcodeproj
```

`Stash.xcodeproj` is committed and uses synchronized folder groups, so files
added, moved, or renamed on disk are picked up automatically — there is no
`xcodegen` or `project.yml` step. Just open it directly.

The `Stash` app target is **multiplatform**: the same `Stash` scheme builds both
iOS and macOS, selected by the run destination. Select the `Stash` scheme and an
iOS Simulator or "My Mac", then build (`⌘B`).

You can also build from the command line:

```bash
# iOS
xcodebuild -scheme Stash -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build CODE_SIGNING_ALLOWED=NO

# macOS
xcodebuild -scheme Stash -destination 'platform=macOS' \
  build CODE_SIGNING_ALLOWED=NO
```

`xcuserdata/` is gitignored; the shared `Stash` scheme is committed.

## Targets

There are two targets, each multiplatform (one target builds for both iOS and
macOS, selected by destination):

| Target | Platforms | Bundle ID |
|--------|-----------|-----------|
| `Stash` | iOS 26+ / macOS 26+ | `cc.otavio.stash` |
| `StashShareExtension` | iOS 26+ / macOS 26+ | `cc.otavio.stash.ShareExtension` |

## Project layout

The project uses synchronized folder groups, so target membership is
folder-level:

| Folder | Compiled into | Contents |
|--------|---------------|----------|
| `Common/` | app **and** extension | Keychain, token manager, client provider, domain models, shared `AddBookmarkView` |
| `Stash/` | app only | Repositories, views, `AppEnvironment`/`AppSettings`, the `@main` entry point |
| `StashShareExtension/` | extension only | The share extension and its iOS/macOS principal controllers (`ShareViewController` / `MacShareViewController`, `#if`-guarded in one folder) |
| `Config/` | (not synced) | Per-platform `Info.plist`/entitlements, selected by SDK-conditional build settings |

## App Group

The main app and the Share Extension share the access/refresh tokens (via a
Keychain access group) and the configured server URL (via the App Group's
`UserDefaults` suite) through the App Group `group.cc.otavio.stash`. This is
configured in the per-platform entitlements files under `StashApp/Config/` and
requires a matching entitlement in your provisioning profile for physical-device
builds.

## Connecting to a backend

On first launch, the app shows a setup screen. Enter your Stash server URL (e.g.
`http://192.168.1.x:8080` for a local server) and sign in with an account
created by the admin. For plain HTTP connections on a local network,
`NSAllowsArbitraryLoads` is already set to `true` in the app's `Info.plist`.

## Lint

```sh
swiftformat . --lint     # must be idempotent
swiftlint lint           # must report 0 violations
```

## Related packages

- **StashKit** — the shared package (`../StashKit`); see
  [StashKit](stashkit.md).
- **CLI** — the `stash` command-line tool (`../CLI`) is a separate Swift
  package, not part of the Xcode project. Build it as described in [Building and
  using the CLI](cli-build.md).
