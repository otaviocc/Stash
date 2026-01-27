# stash CLI

A command-line interface for the Stash bookmark manager.

## Setup

Build and install:

```bash
cd CLI
swift build -c release
cp .build/release/stash /usr/local/bin/stash
```

## Configuration

Config file: `~/.config/stash/config.json`

```bash
stash config set-url http://localhost:8080
stash login
```

## Common commands

```bash
stash list                          # List recent bookmarks
stash list --tag swift              # Filter by tag
stash list --search "vapor"         # Search
stash add https://example.com       # Save a bookmark
stash add https://example.com --tag swift --tag ios
stash get <id>                      # Get a bookmark
stash delete <id>                   # Delete a bookmark
stash archive <id>                  # Archive a bookmark
stash tags                          # List all tags
stash tags rename --from foo --to bar
stash tags delete foo
stash export                        # Export all bookmarks
stash import file.json              # Import bookmarks
stash admin stats                   # Admin: show stats
stash admin users                   # Admin: list users
```

## JSON output

All commands support `--json` for machine-readable output.

## Authentication

Tokens are stored in `~/.config/stash/config.json`. Run `stash login` to authenticate. Tokens refresh automatically.
