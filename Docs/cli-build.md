# Building and using the CLI

The `stash` command-line client. It talks to the backend over the public REST API
(`/api/v1/`) via the shared [StashKit](stashkit.md) package, and covers bookmarks, tags,
import/export, and admin operations.

## Prerequisites

- Swift 6.2+ (ships with Xcode 26)
- macOS 26 or later

## Dependencies

All fetched automatically by SwiftPM (`swift-tools-version:6.2`, macOS 26+):

| Package | Purpose |
|---------|---------|
| [`apple/swift-argument-parser`](https://github.com/apple/swift-argument-parser) | Command/flag parsing |
| [StashKit](stashkit.md) (local) | DTOs, request factories, thin HTTP client |
| [`otaviocc/MicroClient`](https://github.com/otaviocc/MicroClient) | Re-declared so login can decode the 2FA-challenge response branch |

## Build and install

```bash
cd stash/CLI
swift build -c release
cp .build/release/stash /usr/local/bin/stash    # optional: install on PATH
```

Verify:

```bash
stash --help
```

## Configuration

Configuration and tokens live in `~/.config/stash/config.json`:

```bash
stash config set-url http://yourserver:8080
stash login                                     # prompts for credentials (and TOTP if enabled)
```

Tokens are stored in that file and refreshed automatically before each authenticated
command.

## Commands

```bash
stash list                          # List recent bookmarks
stash list --tag swift              # Filter by tag (prefix-matches swift/*)
stash list --search "vapor"         # Full-text search
stash add https://example.com       # Save a bookmark
stash add https://example.com --tag swift --tag ios
stash get <id>                      # Get a bookmark
stash delete <id>                   # Delete a bookmark
stash archive <id>                  # Archive a bookmark
stash tags                          # List all tags with counts
stash tags rename --from foo --to bar
stash tags delete foo
stash export                        # Export all bookmarks (native JSON)
stash import file.json              # Import bookmarks (Anybox or Stash JSON)
stash admin stats                   # Admin: show stats
stash admin users                   # Admin: list users
```

Top-level aliases mirror the grouped subcommands, so `stash list` and
`stash bookmarks list` are equivalent. Run `stash --help` (or `stash <command> --help`)
for the full list.

## JSON output

All commands accept `--json` for machine-readable output (pretty-printed, ISO-8601
dates). Results go to stdout; prompts, confirmations, and errors go to stderr, with a
non-zero exit on failure.
