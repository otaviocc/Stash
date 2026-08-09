# Building the backend from source

For developers who want to build and run the backend without Docker.

## Prerequisites

- Swift **6.1** (`swift --version`). The backend package declares
  `swift-tools-version:5.9` and targets macOS 13+, but it needs to be built with
  6.1 specifically: Swift 6.2.1's release-mode optimizer crashes compiling
  Vapor under `-c release`. If your toolchain is newer, build in debug (drop
  `-c release`) or install 6.1 via [swiftly](https://www.swift.org/install/) or
  an Xcode with a matching command-line-tools toolchain.
- PostgreSQL 16 (`brew install postgresql@16` on macOS); only needed to *run* the
  server, not to build or test it.

## Clone and build

```bash
git clone https://github.com/otaviocc/Stash.git
cd Stash/Backend
swift build -c release
```

## Run tests

```bash
swift test --no-parallel
```

Tests use an in-memory SQLite database; no PostgreSQL instance required. The
`--no-parallel` flag matters: running suites concurrently boots many app
instances all hashing passwords at bcrypt cost 12, which starves the SQLite
connection pool and produces spurious timeouts. Run a single test or suite
with:

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

- [Running locally](backend-local.md): Swift + a local PostgreSQL instance, no Docker.
- [Running with Docker](backend-docker.md): the published image via Docker Compose.
