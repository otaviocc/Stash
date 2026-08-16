---
name: stash-cli
description: Drive the `stash` command-line client for the self-hosted Stash bookmark manager. Use when the user wants to save, search, list, get, delete, or archive bookmarks; list, rename, or delete tags; browse Smart Views and the bookmarks they match; import or export their bookmark collection; or (as an admin) manage users and view stats from the shell. Also use for intelligent tag suggestion when saving a bookmark.
---

# Using the `stash` CLI

Read this before running any `stash` command so you call it correctly on the
first attempt. Everything here is derived from the CLI source, not the product
spec; where the two differ, this document follows the source.

## Overview

Stash is a self-hosted, multi-user bookmark manager. The `stash` CLI is its
command-line client: it talks to a Stash backend over the public REST API
(`/api/v1/`) and can list, search, add, get, delete, and archive bookmarks;
list, rename, and delete tags; browse Smart Views and run their saved queries;
import and export bookmark collections; and, for admin accounts, manage users
and view stats. Use it whenever the user wants to save, find, organize, back up,
or migrate their bookmarks, or administer their Stash instance, from the shell.

---

## Prerequisites

Three things must be true before any authenticated command works. Verify them in
order.

**1. The `stash` binary is installed and on `$PATH`.**

```bash
stash --help
```

If this prints the command list, the binary is available. If the shell reports
the command as not found, it is not installed; build it (`cd CLI && swift
build -c release`, then copy `.build/release/stash` onto `$PATH`).

**2. A server URL is configured.**

```bash
stash config show
```

Look at the `Server URL:` line. If it reads `(not set)`, run `stash config
set-url <url>` (see [Configuration](#configuration)). Commands that need the
server but find no URL fail on stderr with:

```
Error: No server URL configured. Run: stash config set-url <url>
```

**3. You are logged in (tokens present).**

`stash config show` also prints `Access token:` and `Refresh token:` lines
(masked to the first 8 characters). If either reads `(not set)`, run `stash
login` (see [Configuration](#configuration)). Authenticated commands with no
access token fail with:

```
Error: Not logged in. Run: stash login
```

`stash login` is interactive (it prompts for username, a hidden password, and a
2FA code if the account has 2FA enabled). You cannot complete a fresh login
non-interactively; ask the user to run `stash login` themselves if tokens are
missing or expired.

---

## Configuration

Config and tokens live in a single JSON file at `~/.config/stash/config.json`.
It holds three optional fields: `baseURL`, `accessToken`, and `refreshToken`. A
missing file is treated as an empty config (commands then fail with a clear "not
configured / not logged in" message rather than crashing).

Set it up:

```bash
stash config set-url http://192.168.1.x:8080   # save the server base URL
stash login                                     # authenticate (prompts; persists tokens)
stash config show                               # verify
```

`stash config show` output (tokens are masked):

```
Server URL:    http://192.168.1.x:8080
Access token:  eyJhbGci…
Refresh token: 9f3c0b2a…
```

Tokens refresh automatically: before every authenticated command, if the access
token is within 60 seconds of expiry and a refresh token exists, the CLI
silently rotates the pair and re-saves the file. If the refresh fails (refresh
token expired/revoked) it clears both tokens and surfaces `Error: Session
expired, please run stash login`.

There is also `stash config set-token <token>`, which writes an access token
directly into the config (for scripting against a token minted elsewhere). It
prints `Access token saved.`

---

## Command reference

Global conventions, true for every command:

- **Results go to stdout; prompts, confirmations, and `Error:` lines go to
  stderr.** This lets you pipe a table or `--json` payload cleanly. Any failure
  exits non-zero (exit code 1).
- **`--json`** (where supported) prints pretty-printed JSON with
  **alphabetically sorted keys**, unescaped slashes, and ISO-8601 dates (no
  fractional seconds).
- **Bookmark/tag subcommands have top-level aliases.** `stash list` ≡ `stash
  bookmarks list`, and likewise for `add`, `get`, `delete`, `archive`,
  `read-later`, `mark-read`. Use the short forms.

### `config`

| Subcommand | Syntax | Output (stdout) |
|---|---|---|
| set URL | `stash config set-url <url>` | `Server URL set to <url>.` |
| set token | `stash config set-token <token>` | `Access token saved.` |
| show | `stash config show` | three lines (URL + masked tokens), see [Configuration](#configuration) |

`set-url` validates the URL must have a scheme and host, else `Error: Invalid
URL: <url>`.

### `login` / `logout`

```bash
stash login      # prompts: Server URL (if unset) → Username → Password (hidden) → 2FA code (if enabled)
stash logout     # invalidates the refresh token server-side and clears local tokens
```

`login` prints `Logged in as <username>.`; `logout` prints `Logged out.` Both
are interactive for `login` only; never assume you can script a login.

### `add` (`bookmarks add`)

```bash
stash add <url> [--title <t>] [--description <d>] [--tag <name> ...] [--no-fetch] [--read-later] [--json]
```

- `<url>` is a required positional argument.
- `--tag` is **repeatable**: `--tag swift --tag ios` attaches two tags.
- `--no-fetch` skips server-side metadata (title/description/favicon) fetching.
- By default the server auto-fetches metadata; `--title`/`--description`
  override fetched values.
- `--read-later` marks the bookmark to read later at creation time.

Default output: `Saved <full-uuid>: <title>`. With `--json`: the created
bookmark object (see [Output formats](#output-formats)). Saving a URL that already exists for this user fails
with `Error: This URL is already saved (existing bookmark <uuid>).`

### `list` (`bookmarks list`)

```bash
stash list [--tag <name>] [--search <query>] [--archived] [--read-later] [--page <n>] [--per <n>] [--json]
```

- `--tag` is a **prefix** filter: `--tag swift` matches `swift` and `swift/*`
  but not `swiftui`. Pass the sentinel `--tag __untagged__` to return only
  bookmarks with no tags.
- `--search` is full-text (matches URL, title, description, and tags;
  case-insensitive).
- `--archived` is a boolean flag (default off); when set, returns archived
  bookmarks instead.
- `--read-later` is a boolean flag (default off); when set, returns only
  bookmarks marked to read later (the "To Read" view). It is mutually
  exclusive with `--tag`.
- `--page` defaults to `1`, `--per` defaults to `20` (server clamps `per` to
  1–100).
- Default output: an aligned text table (see [Output formats](#output-formats)). With `--json`: the full
  paginated page object (`items` + `metadata`).

Note: `--tag` and `--archived` are independent filters; there is no single
command that returns both active and archived in one call (export handles that
internally, see below).

### `get` (`bookmarks get`)

```bash
stash get <id> [--json]
```

`<id>` must be a full UUID (the CLI validates it locally; a bad value fails with
`Error: Invalid bookmark ID: <value>` before any network call). Default output:
a labeled detail block (see [Output formats](#output-formats)). With `--json`: the bookmark object.

### `delete` (`bookmarks delete`)

```bash
stash delete <id> [--force]
```

Prompts `Delete bookmark <uuid>? [y/N] ` on stderr unless `--force` is given.
Answering anything other than `y`/`yes` prints `Canceled.` and exits 0 without
deleting. On success: `Deleted <uuid>.` Use `--force` in automated workflows.

### `archive` (`bookmarks archive`)

```bash
stash archive <id>
```

Sets the bookmark's archived flag. Prints `Archived <uuid>.` There is no
unarchive command in the CLI; unarchiving must be done via the app/web UI (the
CLI only sets `isArchived: true`).

### `read-later` (`bookmarks read-later`)

```bash
stash read-later <id>
```

Sets `isReadLater: true`. Prints `Marked <uuid> to read later.`

### `mark-read` (`bookmarks mark-read`)

```bash
stash mark-read <id>
```

Clears the read-later flag (`isReadLater: false`). Prints `Marked <uuid> as
read.`

### `tags` (`tags list`)

```bash
stash tags [--json]
```

`stash tags` with no subcommand lists tags (the default subcommand). Default
output: one `name (count)` line per tag, or `No tags found.` if empty. With
`--json`: an array of `{ count, name }` objects.

### `tags rename`

```bash
stash tags rename --from <tag> --to <tag>
```

Renames the exact tag **and all its children** (`foo/x` follows `foo` → `bar`).
If the target already exists the tags merge. Output: `Renamed <from> to <to>
(<n> bookmarks updated).` Idempotent: an unused or unchanged `from` reports `0
bookmarks updated`.

### `tags delete`

```bash
stash tags delete <tag> [--force]
```

Removes the tag **and all its children** from every bookmark (bookmarks
themselves are never deleted). Prompts `Delete tag <tag> and all its children?
[y/N] ` unless `--force`. On success: `Deleted tag <tag> (<n> bookmarks
updated).`

> Caveat: the underlying API deletes a tag subtree by passing the tag as a single path segment,
> so a parent tag (`swift`) deletes `swift` and `swift/*`, but targeting a specific child like
> `swift/vapor` is not supported over this client. Delete works reliably for flat tags and
> whole subtrees.

### `smart-views` (`smart-views list`)

```bash
stash smart-views [--json]                       # list all Smart Views
stash smart-views list [--json]                  # same (default subcommand)
stash smart-views bookmarks <id> [--page <n>] [--per <n>] [--json]
```

Smart Views are saved queries (a set of AND/OR conditions). The CLI is
**consumption-only**: it lists Smart Views and runs them, but does not create or
edit them; do that in the web frontend, or round-trip them through `stash
export` / `stash import` (a `stash-json` file carries Smart Views, matched by
name). `smart-views` with no subcommand lists (the default subcommand).

- **`smart-views list`** default output: a table with columns NAME (30), MATCH
  (`all`/`any`), CONDITIONS (a `type=value` summary), and the **full** Smart View
  UUID in the last column (unlike the bookmark table, which truncates the ID).
  Empty result prints `No Smart Views found.` With `--json`: an array of Smart
  View objects (`{ id, name, matchMode, conditions: [{type, value}], createdAt,
  updatedAt }`).
- **`smart-views bookmarks <id>`** runs the Smart View's query server-side and
  prints the matching bookmarks in the same table / `--json` page shape as `stash
  list`. `<id>` must be a full UUID (copy it from `smart-views list`); a bad value
  fails with `Error: Invalid Smart View ID: <value>` before any network call. A
  missing/foreign Smart View surfaces `Error: Not found.` Results are non-archived
  unless the Smart View carries an `isArchived` condition.

### `import` / `export`

```bash
stash import <file> [--format anybox|stash-json]
stash export [--format stash-json] [--output <path>]
```

`export` writes every bookmark (active *and* archived) plus the user's Smart
Views into a `stash-json` envelope. `import` reads that format back (or an
`anybox` export), creating records and updating any whose URL already exists,
which makes a `stash-json` re-import idempotent.

Read `reference/import-export.md` (relative to this skill's directory) for the
full flag list, the two file-format shapes, output strings, and the `createdAt`
caveat.

### `admin` (admin accounts only)

`stash admin` provides admin-only user management (`users`, `create-user`,
`suspend-user`, `unsuspend-user`, `reset-password`, `reset-totp`,
`delete-user`) and instance `stats`.

Read `reference/admin.md` (relative to this skill's directory) for the full
admin command syntax, output formats, and caveats.

---

## Output formats

Default output is a human-readable, aligned text table (or a labeled detail
block for `stash get`). With `--json`, keys are sorted alphabetically and dates
are ISO-8601 without fractional seconds.

Read `reference/output-formats.md` (relative to this skill's directory) for the
exact table columns, truncation rules, and full JSON examples for every command.

---

## Workflow examples

**Save a bookmark with tags:**

```bash
stash add https://swift.org/blog/swift-6 --tag swift --tag release
```

**Search and retrieve:**

```bash
stash list --search "vapor" --json     # parse items[].id from the JSON
stash get <id-from-above> --json       # full detail for one bookmark
```

**Bulk tag rename:**

```bash
stash tags                              # inspect current tags
stash tags rename --from ios --to apple/ios
stash tags                              # verify
```

**Export and re-import (backup / migrate):**

```bash
stash export --output ~/stash-backup.json
stash import ~/stash-backup.json --format stash-json
```

---

## Error handling

Every failure prints a single `Error: <message>` line to **stderr** and exits
non-zero. The most common ones: a session error (`Session expired, please run
stash login`) means the user must run `stash login`; `This URL is already saved
(existing bookmark <uuid>).` means `add` hit a duplicate URL.

Read `reference/errors.md` (relative to this skill's directory) for the full
table of error messages and their remedies.

---

## Tips

- **Always use `--json` when you need to parse output programmatically.** The
  text tables truncate titles/URLs and show only the first 8 characters of the
  ID; never parse them for IDs or full values.
- **UUIDs in JSON are full; the text table shows only the first 8 characters.**
  To act on a bookmark you found in a table, re-fetch with `--json` to get its
  full `id`.
- **Tags are normalized server-side** (trimmed, lowercased, surrounding slashes
  stripped, de-duplicated). `Swift` and `swift` are the same tag; don't rely on
  case.
- **`stash list` returns 20 results per page by default.** Use `--page`/`--per`
  to paginate, or `--json` and read `metadata.total` to know when you've seen
  everything.
- **`--force` skips `[y/N]` confirmations** on `delete`, `tags delete`, and
  `admin delete-user`; use it in automated workflows; otherwise the prompt
  blocks on stdin.
- **`stash import --format stash-json` is idempotent**: re-importing the same
  file updates existing bookmarks (matched by URL) instead of creating
  duplicates.
- **`stash login` is interactive and cannot be scripted.** If tokens are missing
  or a command reports a session error, ask the user to run `stash login`
  themselves.
- **There is no `unarchive` command.** The CLI only archives; unarchiving needs
  the app/web UI.
- **Smart Views are consumption-only on the CLI.** You can list them and run
  them (`smart-views bookmarks <id>`) but not create or edit them; use the web
  frontend, or round-trip them via `stash export`/`import`. Unlike the bookmark
  table, `smart-views list` prints the full UUID, so you can feed it straight to
  `smart-views bookmarks`.

---

## Intelligent tag suggestion

One of the most useful things you can do is suggest good tags when saving a
bookmark, drawn from the user's *existing* taxonomy rather than inventing new
ones.

**Workflow:**

1. Fetch the existing tags first:
   ```bash
   stash tags --json
   ```
2. Analyze the URL, page title, and any description against that tag list.
3. Suggest the most relevant **existing** tags. Only propose a brand-new tag
   when the content clearly warrants one that doesn't exist yet.
4. Briefly explain the suggestion and confirm before saving, e.g.: > "Based on
   your existing tags, I'd suggest `swift`, `swift/vapor`, and `backend`. Want
   me to > save it with those, or adjust?"
5. Save with the agreed tags:
   ```bash
   stash add https://example.com --tag swift --tag swift/vapor --tag backend
   ```

**Rules:**

- **Prefer existing tags over new ones.** If `apple/ios` exists, don't create a
  flat `ios`; use the hierarchical tag already in the taxonomy.
- **Respect the hierarchy.** If the user has `swift/concurrency` and
  `swift/vapor`, a Swift networking article likely belongs under `swift/`;
  suggest `swift/networking`, not a flat `networking`.
- **Suggest 2–4 tags maximum.** Quality over quantity; don't over-tag.
- **When in doubt, ask.** For ambiguous content, present the top options and let
  the user choose.
- **Batch saves.** When saving several bookmarks at once, call `stash tags
  --json` **once** and reuse that list across every save; don't re-fetch per
  bookmark.

**Example:**

```
User: Save https://pointfree.co/episodes/ep-42-the-many-faces-of-map to Stash.

Assistant:
1. stash tags --json          → existing tags include: swift, swift/fp, video, pointfree
2. Analyzes the URL: a Point-Free episode on functional programming in Swift
3. Suggests: swift, swift/fp, pointfree, video
4. Confirms with the user
5. stash add https://pointfree.co/... --tag swift --tag swift/fp --tag pointfree --tag video
```
