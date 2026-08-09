# Building and using the CLI

The `stash` command-line client. It talks to the backend over the public REST
API (`/api/v1/`) via the shared [StashKit](stashkit.md) package, and covers
bookmarks, tags, Smart Views, import/export, and admin operations.

## Prerequisites

- Swift 6.2 or later (ships with Xcode 26)
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

Tokens are stored in that file and refreshed automatically before each
authenticated command.

## Commands

```bash
stash list                          # List recent bookmarks
stash list --tag swift              # Filter by tag (prefix-matches swift/*)
stash list --search "vapor"         # Full-text search
stash list --archived               # Show archived bookmarks
stash list --read-later             # Show only the "To Read" view
stash list --page 2 --per 50        # Pagination
stash add https://example.com       # Save a bookmark
stash add https://example.com --tag swift --tag ios
stash add https://example.com --title "..." --description "..." --no-fetch
stash add https://example.com --read-later
stash get <id>                      # Get a bookmark
stash delete <id>                   # Delete a bookmark (--force skips the prompt)
stash archive <id>                  # Archive a bookmark
stash read-later <id>               # Mark a bookmark to read later
stash mark-read <id>                # Clear the read-later flag
stash tags                          # List all tags with counts
stash tags rename --from foo --to bar
stash tags delete foo               # (--force skips the prompt)
stash smart-views                   # List Smart Views (consumption only)
stash smart-views bookmarks <id>    # List the bookmarks a Smart View matches
stash export                        # Export all bookmarks (native JSON)
stash export --output backup.json   # Choose the output path
stash import file.json              # Import a Stash JSON file
stash import file.json --format anybox  # Import an Anybox JSON export
stash login                         # Sign in (prompts for credentials + TOTP)
stash logout                        # Clear the stored session
stash config set-url http://host:8080
stash config set-token <token>      # Set the access token directly
stash config show                   # Print the current configuration
stash admin users                   # Admin: list users
stash admin create-user --username bob
stash admin suspend-user bob
stash admin unsuspend-user bob
stash admin reset-password bob
stash admin reset-totp bob
stash admin delete-user bob         # (--force skips the prompt)
stash admin stats                   # Admin: show stats
```

`stash import` defaults to the native Stash JSON format; pass `--format anybox`
for an Anybox export. `stash export` defaults to (and currently only supports)
Stash JSON.

Bookmark subcommands are also exposed as top-level aliases, so `stash list` and
`stash bookmarks list` are equivalent; `stash add`, `get`, `delete`, `archive`,
`read-later`, and `mark-read` work the same way. Tag and Smart View
subcommands are grouped only (`stash tags list`, `stash smart-views list`).
Run `stash --help` (or `stash <command> --help`) for the full list.

## JSON output

`--json` is available on the list-style and stats commands (`bookmarks
list/add/get`, `tags list`, `smart-views list/bookmarks`, `admin
users/create-user/stats`) for machine-readable output (pretty-printed,
ISO-8601 dates). Mutating commands without a meaningful "result object" (delete,
archive, rename, import, login) print plain confirmation text instead. Results
go to stdout; prompts, confirmations, and errors go to stderr, with a non-zero
exit on failure.
