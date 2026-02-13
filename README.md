# Stash

A self-hosted, fully private, multi-user bookmark manager. Accounts are created by an admin; each
user keeps their own private collection. Everything runs on infrastructure you control — no
third-party cloud.

## What's in this repo

| Directory | Component | Stack |
|-----------|-----------|-------|
| `Backend/` | REST API (`/api/v1/`) + server-rendered admin dashboard (`/admin`) and user web frontend (`/app`) | Vapor 4, PostgreSQL |
| `StashKit/` | Shared Swift package (DTOs, request factories, thin HTTP client) used by the CLI and the apps | Swift package, [MicroClient](https://github.com/otaviocc/MicroClient) |
| `CLI/` | `stash` command-line client | Swift, ArgumentParser |
| `StashApp/` | Native SwiftUI app for **iOS and macOS**, each with a Share Extension | SwiftUI |

See `PRODUCT.md` for the product spec and `DECISIONS.md` for the design decisions behind it.

## Prerequisites

- **macOS with Xcode 26** (Swift 6.2) — required for `StashApp` and the Swift 6.2 packages (`StashKit`, `CLI`).
- **Docker + Docker Compose** — the supported way to run the backend.
- **SwiftFormat + SwiftLint** (only if you'll be linting): `brew install swiftformat swiftlint`

Swift package dependencies (Vapor, MicroClient, ArgumentParser, …) are fetched automatically by SwiftPM
and Xcode — nothing to install by hand.

## Run the backend

The backend is the server the CLI and apps talk to. Run it with Docker:

```sh
cd Backend
cp .env.example .env     # fill in real secrets (DB_PASSWORD, JWT_SECRET, ADMIN_USERNAME, ADMIN_PASSWORD)
make up                  # docker compose up -d  →  http://<host>:8080
make logs                # tail the app logs
make down                # stop the stack
```

On first boot the admin account is created from `ADMIN_USERNAME` / `ADMIN_PASSWORD`; migrations run
automatically. To run it directly against a local Postgres instead of Docker, see `Backend/README.md`.

```sh
# Build / test the backend without a database (in-memory SQLite):
swift build
swift test
```

## Build and run the CLI

```sh
cd CLI
swift build -c release
cp .build/release/stash /usr/local/bin/stash    # optional: install on PATH

stash config set-url http://localhost:8080
stash login
stash add https://example.com --tag swift
stash list
```

All commands accept `--json`. See `CLI/README.md` for the full command list.

## Build and run the apps (iOS / macOS)

Open the committed Xcode project and pick the `Stash` scheme — it's a single multiplatform target, so
choose an iOS Simulator or "My Mac" as the run destination:

```sh
cd StashApp
open Stash.xcodeproj
```

Or build from the command line (same scheme, different destination):

```sh
# iOS
xcodebuild -scheme Stash -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO
# macOS
xcodebuild -scheme Stash -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

On first launch, point the app at your backend URL on the setup screen, then sign in with an account
created by the admin. The Share Extension lets you save URLs from Safari and other apps. See
`StashApp/README.md` for the project layout.
