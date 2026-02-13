# Stash App (iOS & macOS)

The native SwiftUI client for Stash, a self-hosted multi-user bookmark manager. `Stash.xcodeproj`
contains two multiplatform targets that build for **both iOS and macOS**:

- **`Stash`** — the SwiftUI app (bookmark list, add/edit/detail, tags, search, settings, 2FA).
- **`StashShareExtension`** — a share extension for saving URLs from Safari and other apps.

The app talks to the [Stash backend](../Backend) over the REST API (`/api/v1/`) through the shared
[`StashKit`](../StashKit) package. The design rationale lives in [`DECISIONS.md`](../DECISIONS.md)
(M8–M10); this document is the operational reference.

## Dependencies

Fetched automatically by Xcode (Swift 6.2, iOS 26 / macOS 26):

| Package | Purpose |
|---------|---------|
| [`StashKit`](../StashKit) (local) | DTOs, request factories, thin HTTP client |
| [`otaviocc/MicroClient`](https://github.com/otaviocc/MicroClient) | Used directly for the 2FA-challenge login branch |

## Project layout

`Stash.xcodeproj` is committed and uses synchronized folder groups, so files on disk are picked up
automatically (no per-file project edits). Target membership is folder-level:

| Folder | Compiled into | Contents |
|--------|---------------|----------|
| `Common/` | app **and** extension | Keychain, token manager, client provider, domain models, shared `AddBookmarkView` |
| `Stash/` | app only | Repositories, views, `AppEnvironment`/`AppSettings`, the `@main` entry point |
| `StashShareExtension/` | extension only | The share extension and its iOS/macOS principal controllers |
| `Config/` | (not synced) | Per-platform `Info.plist`/entitlements, selected by SDK-conditional build settings |

The app and the share extension share tokens via a Keychain access group and the server URL via the
App Group's `UserDefaults` suite (`group.cc.otavio.stash`).

## Build and run

Open the project and pick the `Stash` scheme — a single multiplatform target selected by run
destination (an iOS Simulator or "My Mac"):

```sh
open Stash.xcodeproj
```

Or build from the command line:

```sh
# iOS
xcodebuild -scheme Stash -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO
# macOS
xcodebuild -scheme Stash -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

Add, move, or rename source files in Xcode; the synchronized folder groups pick them up with no
project edits. `xcuserdata/` is gitignored; the shared `Stash` scheme is committed.

On first launch, point the app at your backend URL on the setup screen, then sign in with an account
created by the admin.

## Lint

```sh
swiftformat . --lint     # must be idempotent
swiftlint lint           # must report 0 violations
```
