---
name: stash-cli
description: Drive the `stash` command-line client for the
self-hosted Stash bookmark manager. Use when the user wants to save, search,
list, get, delete, or archive bookmarks; list, rename, or delete tags; browse
Smart Views and the bookmarks they match; import or export their bookmark
collection; or (as an admin) manage users and view stats from the shell. Also
use for intelligent tag suggestion when saving a bookmark.
Covers exact command syntax, flags, default/JSON output shapes, and error
messages.
---

# Using the `stash` CLI

Read this before running any `stash` command so you call it correctly on the
first attempt. Everything here is derived from the CLI source, not the product
spec — where the two differ, this document follows the source.

## 1. Overview

Stash is a self-hosted, multi-user bookmark manager. The `stash` CLI is its
command-line client: it talks to a Stash backend over the public REST API
(`/api/v1/`) and can list, search, add, get, delete, and archive bookmarks;
list, rename, and delete tags; browse Smart Views and run their saved queries;
import and export bookmark collections; and — for admin accounts — manage users
and view stats. Use it whenever the user wants to save, find, organize, back up,
or migrate their bookmarks, or administer their Stash instance, from the shell.

---

## 2. Prerequisites

Three things must be true before any authenticated command works. Verify them in
order.

**1. The `stash` binary is installed and on `$PATH`.**

```bash
stash --help
```

If this prints the command list, the binary is available. If the shell reports
`command not found: stash`, it is not installed — build it (`cd CLI && swift
build -c release`, then copy `.build/release/stash` onto `$PATH`).

**2. A server URL is configured.**

```bash
stash config show
```

Look at the `Server URL:` line. If it reads `(not set)`, run `stash config
set-url <url>` (see §3). Commands that need the server but find no URL fail on
stderr with:

```
Error: No server URL configured. Run: stash config set-url <url>
```

**3. You are logged in (tokens present).**

`stash config show` also prints `Access token:` and `Refresh token:` lines
(masked to the first 8 characters). If either reads `(not set)`, run `stash
login` (see §3). Authenticated commands with no access token fail with:

```
Error: Not logged in. Run: stash login
```

`stash login` is interactive (it prompts for username, a hidden password, and a
2FA code if the account has 2FA enabled). You cannot complete a fresh login
non-interactively — ask the user to run `stash login` themselves if tokens are
missing or expired.

---

## 3. Configuration

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
expired — please run stash login`.

There is also `stash config set-token <token>`, which writes an access token
directly into the config (for scripting against a token minted elsewhere). It
prints `Access token saved.`

---

## 4. Command reference

Global conventions, true for every command:

- **Results go to stdout; prompts, confirmations, and `Error:` lines go to
  stderr.** This lets you pipe a table or `--json` payload cleanly. Any failure
  exits non-zero (exit code 1).
- **`--json`** (where supported) prints pretty-printed JSON with
  **alphabetically sorted keys**, unescaped slashes, and ISO-8601 dates (no
  fractional seconds).
- **Bookmark/tag subcommands have top-level aliases.** `stash list` ≡ `stash
  bookmarks list`, and likewise for `add`, `get`, `delete`, `archive`. Use the
  short forms.

### `config`

| Subcommand | Syntax | Output (stdout) |
|---|---|---|
| set URL | `stash config set-url <url>` | `Server URL set to <url>.` |
| set token | `stash config set-token <token>` | `Access token saved.` |
| show | `stash config show` | three lines (URL + masked tokens), see §3 |

`set-url` validates the URL must have a scheme and host, else `Error: Invalid
URL: <url>`.

### `login` / `logout`

```bash
stash login      # prompts: Server URL (if unset) → Username → Password (hidden) → 2FA code (if enabled)
stash logout     # invalidates the refresh token server-side and clears local tokens
```

`login` prints `Logged in as <username>.`; `logout` prints `Logged out.` Both
are interactive for `login` only — never assume you can script a login.

### `add` (`bookmarks add`)

```bash
stash add <url> [--title <t>] [--description <d>] [--tag <name> ...] [--no-fetch] [--json]
```

- `<url>` is a required positional argument.
- `--tag` is **repeatable**: `--tag swift --tag ios` attaches two tags.
- `--no-fetch` skips server-side metadata (title/description/favicon) fetching.
- By default the server auto-fetches metadata; `--title`/`--description`
  override fetched values.

Default output: `Saved <full-uuid> — <title>`. With `--json`: the created
bookmark object (see §5). Saving a URL that already exists for this user fails
with `Error: This URL is already saved (existing bookmark <uuid>).`

### `list` (`bookmarks list`)

```bash
stash list [--tag <name>] [--search <query>] [--archived] [--page <n>] [--per <n>] [--json]
```

- `--tag` is a **prefix** filter: `--tag swift` matches `swift` and `swift/*`
  but not `swiftui`. Pass the sentinel `--tag __untagged__` to return only
  bookmarks with no tags.
- `--search` is full-text (matches URL, title, description, and tags;
  case-insensitive).
- `--archived` is a boolean flag (default off); when set, returns archived
  bookmarks instead.
- `--page` defaults to `1`, `--per` defaults to `20` (server clamps `per` to
  1–100).
- Default output: an aligned text table (see §5). With `--json`: the full
  paginated page object (`items` + `metadata`).

Note: `--tag` and `--archived` are independent filters; there is no single
command that returns both active and archived in one call (export handles that
internally — see below).

### `get` (`bookmarks get`)

```bash
stash get <id> [--json]
```

`<id>` must be a full UUID (the CLI validates it locally; a bad value fails with
`Error: Invalid bookmark ID: <value>` before any network call). Default output:
a labeled detail block (see §5). With `--json`: the bookmark object.

### `delete` (`bookmarks delete`)

```bash
stash delete <id> [--force]
```

Prompts `Delete bookmark <uuid>? [y/N] ` on stderr unless `--force` is given.
Answering anything other than `y`/`yes` prints `Cancelled.` and exits 0 without
deleting. On success: `Deleted <uuid>.` Use `--force` in automated workflows.

### `archive` (`bookmarks archive`)

```bash
stash archive <id>
```

Sets the bookmark's archived flag. Prints `Archived <uuid>.` There is no
unarchive command in the CLI — unarchiving must be done via the app/web UI (the
CLI only sets `isArchived: true`).

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
edit them — do that in the web frontend, or round-trip them through `stash
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

### `import`

```bash
stash import <file> [--format anybox|stash-json]
```

- `<file>` is a path to the import file.
- `--format` defaults to **`stash-json`**. The other accepted value is `anybox`.
- The import is performed client-side over the public API (there is no server
  import endpoint for the CLI): each record is created, and on a duplicate-URL
  response it is updated in place.
- Output: `Imported: <i>, Updated: <u>, Skipped: <s>`. Records with a
  missing/invalid URL, or that error on submit, are counted as skipped. When a
  `stash-json` file carries Smart Views, a second line follows — `Smart Views —
  Imported: <i>, Updated: <u>, Skipped: <s>` (a Smart View missing a name or
  valid conditions is skipped).

Format differences:
- **`anybox`** expects a top-level JSON **array** of bookmark objects. Anybox
  stores `tags` as arrays of `[namespace, value]` pairs, which are joined with
  `/` into hierarchical tags (`[["topic","swift"]]` → `topic/swift`); plain
  `[String]` tags are also accepted. All Anybox records import as **not
  archived**. Wrong shape → `Error: This doesn't look like an Anybox JSON export
  (expected a JSON array of bookmarks).`
- **`stash-json`** expects an **object** with a `bookmarks` array (the shape
  `stash export` produces); it honors each record's `isArchived`. Wrong shape →
  `Error: This doesn't look like a Stash JSON export (expected an object with a
  "bookmarks" array).` If the file carries an optional `smartViews` array, those
  Smart Views are restored too (matched by name — an existing name is updated, a
  new one is created), so re-import is idempotent for Smart Views as well.

Limitation: importing over the REST API cannot preserve original `createdAt` on
*new* records (they get a fresh timestamp) — but re-importing a Stash export of
bookmarks that already exist takes the duplicate-update path, where the server
preserves `createdAt`, so re-import is idempotent. (The same `createdAt`
limitation applies to newly created Smart Views.)

### `export`

```bash
stash export [--format stash-json] [--output <path>]
```

- `--format` defaults to (and only accepts) `stash-json`.
- `--output` is the destination path; if omitted, writes to
  `stash-export-YYYY-MM-DD.json` in the current directory.
- Fetches **all** bookmarks — paginating through every page of both active *and*
  archived (100 per page) — assembles the native `{ version, exportedAt,
  bookmarks[], smartViews[] }` envelope (bookmarks sorted by `createdAt`
  ascending, Smart Views by name), and writes it. The user's Smart Views ride
  along in the same file, at parity with the web frontend's export.
- Output: `Exported <n> bookmarks and <m> Smart Views to <path>.`

### `admin` (admin accounts only)

All admin commands require the logged-in account to be an admin; a non-admin
gets `Error: You don't have permission to perform that action.` The admin API is
keyed by UUID, but every CLI admin command that targets a user takes a
**username** and resolves it to a UUID internally by listing users and matching
case-insensitively. An unknown name fails with `Error: No user named
'<username>'.`

```bash
stash admin users [--json]                              # list all users
stash admin create-user --username <u> [--password <p>] [--json]
stash admin suspend-user <username>                     # set isActive=false
stash admin unsuspend-user <username>                   # set isActive=true
stash admin reset-password <username> [--password <p>]
stash admin reset-totp <username>                       # clear the user's 2FA
stash admin delete-user <username> [--force]            # hard-delete (irreversible)
stash admin stats [--json]                              # aggregate + per-user stats
```

- `create-user` and `reset-password` prompt for a hidden password if
  `--password` is omitted. `create-user` prints `Created user <username>.`;
  accounts are always created with the `user` role.
- `suspend-user`/`unsuspend-user` print `Suspended <username>.` / `Unsuspended
  <username>.`
- `reset-password` prints `Reset password for <username>.`; `reset-totp` prints
  `Reset 2FA for <username>.`
- `delete-user` prompts `Delete user <username>? [y/N] ` unless `--force`; on
  success `Deleted <username>.` Admins cannot delete their own account.
- `users` and `stats` default to text tables (see §5); add `--json` for
  structured output.

> Known gap: `stash admin reset-totp` calls a JSON-API route that may not yet be exposed by the
> backend; if so it surfaces `Error: Not found.` The command is otherwise correct.

---

## 5. Output formats

### Human-readable (default)

**`stash list`** — a table with columns ID (8), TITLE (40), URL (50), TAGS,
separated by two spaces. ID is the first 8 characters of the UUID. TITLE and URL
are truncated to their width (last character replaced with `…` when over). TAGS
is comma-separated and not truncated. Empty result prints `No bookmarks found.`

```
ID        TITLE                                     URL                                                 TAGS
a1b2c3d4  The Swift Programming Language             https://docs.swift.org/swift-book/                 swift, docs
9f8e7d6c  Vapor — Server-side Swift web framework    https://vapor.codes/                               swift, swift/vapor
```

**`stash get <id>`** — a labeled block:

```
ID:          a1b2c3d4-5e6f-7890-abcd-ef0123456789
URL:         https://docs.swift.org/swift-book/
Title:       The Swift Programming Language
Description: The official Swift book.
Tags:        swift, docs
Archived:    no
Created:     2026-01-15T09:30:00Z
```

(The `Description:` line is omitted when there is no description; `Tags:` shows
`—` when empty.)

**`stash tags`** — `name (count)` per line:

```
swift (42)
swift/vapor (12)
docs (7)
```

**`stash admin users`** — columns USERNAME (20), ROLE (6), ACTIVE (7), 2FA (4),
BOOKMARKS (10), ID (full UUID). ACTIVE is `yes`/`no`; 2FA is `on`/`off`.

**`stash admin stats`** — two summary lines then a table:

```
Total users:     3
Total bookmarks: 214

USERNAME              ACTIVE   BOOKMARKS
alice                 yes      120
bob                   no       94
```

### JSON (`--json`)

Keys are sorted alphabetically. Dates are ISO-8601 without fractional seconds.

**`stash list --json`** — the full paginated page (a `BookmarkDTO` list +
metadata):

```json
{
  "items" : [
    {
      "createdAt" : "2026-01-15T09:30:00Z",
      "description" : "The official Swift book.",
      "faviconURL" : "https://docs.swift.org/favicon.ico",
      "id" : "A1B2C3D4-5E6F-7890-ABCD-EF0123456789",
      "isArchived" : false,
      "tags" : [ "swift", "docs" ],
      "title" : "The Swift Programming Language",
      "updatedAt" : "2026-01-15T09:30:00Z",
      "url" : "https://docs.swift.org/swift-book/"
    }
  ],
  "metadata" : {
    "page" : 1,
    "per" : 20,
    "total" : 1
  }
}
```

`description` and `faviconURL` may be absent/`null`. `id` is a full UUID.

**`stash get <id> --json`** — a single bookmark object (the same shape as one
`items` element above).

**`stash add --json`** — the created bookmark object (same shape).

**`stash tags --json`** — an array of tag objects:

```json
[
  { "count" : 42, "name" : "swift" },
  { "count" : 12, "name" : "swift/vapor" }
]
```

**`stash admin users --json`** — an array of user objects:

```json
[
  {
    "bookmarkCount" : 120,
    "createdAt" : "2026-01-01T00:00:00Z",
    "id" : "11111111-2222-3333-4444-555555555555",
    "isActive" : true,
    "isTOTPEnabled" : false,
    "role" : "user",
    "username" : "alice"
  }
]
```

**`stash admin stats --json`**:

```json
{
  "totalBookmarks" : 214,
  "totalUsers" : 3,
  "users" : [
    {
      "bookmarkCount" : 120,
      "id" : "11111111-2222-3333-4444-555555555555",
      "isActive" : true,
      "username" : "alice"
    }
  ]
}
```

---

## 6. Workflow examples

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
stash export --output ~/Desktop/stash-backup.json
stash import ~/Desktop/stash-backup.json --format stash-json
```

**Admin: create and manage a user:**

```bash
stash admin create-user --username alice --password "securepassword123"
stash admin users --json
stash admin suspend-user alice
stash admin unsuspend-user alice
stash admin reset-password alice --password "newpassword123"
stash admin delete-user alice --force
```

---

## 7. Error handling

Every failure prints a single `Error: <message>` line to **stderr** and exits
non-zero. These are the **actual** messages emitted by the CLI (note they are
human-readable sentences, not the API's snake_case codes). When you see one,
take the matching action.

| stderr message | Meaning | Remedy |
|---|---|---|
| `No server URL configured. Run: stash config set-url <url>` | No `baseURL` in config | Run `stash config set-url <url>` |
| `Not logged in. Run: stash login` | No access token in config | Run `stash login` |
| `Session expired — please run stash login` | Refresh token expired/revoked (local refresh failed); tokens cleared | Run `stash login` again |
| `Session expired — please run stash login.` | Server rejected the access token as expired (note the trailing period — this is the API-mapped variant) | Run `stash login` again |
| `Session invalid — please run stash login.` | Server rejected the access token as malformed/invalid (not merely expired) | Run `stash login` again |
| `Two-factor authentication is required.` | A 2FA-gated action hit the API without a completed 2FA login | Complete `stash login` (it prompts for the 2FA code) |
| `Could not reach the server. <detail> (Check the URL and scheme — a plain HTTP server needs http://, not https://.)` | Network/TLS/URL issue (e.g. `https://` against a plain-HTTP server); `<detail>` is the underlying transport error | Check the URL scheme and that the server is up |
| `The server URL is invalid. Set it with: stash config set-url <url>` | Malformed base URL | Re-set with `stash config set-url <url>` |
| `This URL is already saved (existing bookmark <uuid>).` | Duplicate URL on `add` | Use `stash list --search` to find the existing one; or `get`/update it |
| `Not found.` | ID/resource doesn't exist (also `admin reset-totp` if route is unexposed) | Verify the UUID with `stash list --json` |
| `You don't have permission to perform that action.` | Not an admin | The command requires an admin account |
| `Invalid username or password.` | Bad credentials at login | Re-check credentials |
| `This account is suspended.` | Account inactive | Have an admin unsuspend it |
| `Invalid two-factor code.` | Wrong TOTP/recovery code | Re-enter the current code |
| `That username is already taken.` | `admin create-user` conflict | Choose a different username |
| `The request was invalid.` | Validation failed (e.g. password too short) | Fix the input (passwords need ≥12 chars) |
| `The server returned HTTP <code>.` / `The server encountered an error.` | Unexpected server status / 5xx | Retry; check server logs |
| `Could not decode the server's response.` / `Could not encode the request.` / `Request preparation failed. <detail>` / `Response handling failed. <detail>` | Rare client-side encode/decode or interceptor failure (usually a version/contract mismatch) | Verify the CLI and backend are on compatible versions; report if it persists |
| `Invalid bookmark ID: <value>` / `Invalid Smart View ID: <value>` | A non-UUID was passed to `get`/`delete`/`archive` or `smart-views bookmarks` | Pass a full UUID from `stash list --json` / `smart-views list --json` |

---

## 8. Tips for Claude

- **Always use `--json` when you need to parse output programmatically.** The
  text tables truncate titles/URLs and show only the first 8 characters of the
  ID — never parse them for IDs or full values.
- **UUIDs in JSON are full; the text table shows only the first 8 characters.**
  To act on a bookmark you found in a table, re-fetch with `--json` to get its
  full `id`.
- **Tags are normalized server-side** (trimmed, lowercased, surrounding slashes
  stripped, de-duplicated). `Swift` and `swift` are the same tag — don't rely on
  case.
- **`stash list` returns 20 results per page by default.** Use `--page`/`--per`
  to paginate, or `--json` and read `metadata.total` to know when you've seen
  everything.
- **`--force` skips `[y/N]` confirmations** on `delete`, `tags delete`, and
  `admin delete-user` — use it in automated workflows; otherwise the prompt
  blocks on stdin.
- **`stash import --format stash-json` is idempotent** — re-importing the same
  file updates existing bookmarks (matched by URL) instead of creating
  duplicates.
- **`stash login` is interactive and cannot be scripted.** If tokens are missing
  or a command reports a session error, ask the user to run `stash login`
  themselves.
- **There is no `unarchive` command.** The CLI only archives; unarchiving needs
  the app/web UI.
- **Smart Views are consumption-only on the CLI.** You can list them and run
  them (`smart-views bookmarks <id>`) but not create or edit them — use the web
  frontend, or round-trip them via `stash export`/`import`. Unlike the bookmark
  table, `smart-views list` prints the full UUID, so you can feed it straight to
  `smart-views bookmarks`.

---

## 9. Intelligent tag suggestion

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
  flat `ios` — use the hierarchical tag already in the taxonomy.
- **Respect the hierarchy.** If the user has `swift/concurrency` and
  `swift/vapor`, a Swift networking article likely belongs under `swift/` —
  suggest `swift/networking`, not a flat `networking`.
- **Suggest 2–4 tags maximum.** Quality over quantity; don't over-tag.
- **When in doubt, ask.** For ambiguous content, present the top options and let
  the user choose.
- **Batch saves.** When saving several bookmarks at once, call `stash tags
  --json` **once** and reuse that list across every save — don't re-fetch per
  bookmark.

**Example:**

```
User: Save https://pointfree.co/episodes/ep-42-the-many-faces-of-map to Stash.

Claude:
1. stash tags --json          → existing tags include: swift, swift/fp, video, pointfree
2. Analyzes the URL: a Point-Free episode on functional programming in Swift
3. Suggests: swift, swift/fp, pointfree, video
4. Confirms with the user
5. stash add https://pointfree.co/... --tag swift --tag swift/fp --tag pointfree --tag video
```
