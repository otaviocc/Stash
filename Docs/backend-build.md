# Building the backend from source

For developers who want to build and run the backend without Docker.

## Prerequisites

- Swift 6.2 or later (`swift --version`) — ships with Xcode 26. The backend package
  itself declares `swift-tools-version:5.9` and targets macOS 13+, but the repo's
  toolchain is Swift 6.2.
- PostgreSQL 16 (`brew install postgresql@16` on macOS) — only needed to *run* the
  server, not to build or test it.
- Xcode 26 or later (macOS only) — provides the Swift toolchain.

## Clone and build

```bash
git clone https://github.com/otaviocc/stash.git
cd stash/Backend
swift build -c release
```

## Run tests

```bash
swift test
```

Tests use an in-memory SQLite database — no PostgreSQL instance required for testing.
Run a single test or suite with:

```bash
swift test --filter <TestName>
```

## SwiftLint and SwiftFormat

```bash
swiftlint lint
swiftformat --lint .
```

## Running the server

To run the backend against a real database, see:

- [Running locally](backend-local.md) — Swift + a local PostgreSQL instance, no Docker.
- [Running with Docker](backend-docker.md) — the published image via Docker Compose.
