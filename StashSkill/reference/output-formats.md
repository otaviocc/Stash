# `stash` CLI output formats

Reference companion to the `stash-cli` skill; read on demand when you need the exact shape of a command's output.

## 5. Output formats

### Human-readable (default)

**`stash list`**: a table with columns ID (8), TITLE (40), URL (50), TAGS,
separated by two spaces. ID is the first 8 characters of the UUID. TITLE and URL
are truncated to their width (last character replaced with `…` when over). TAGS
is comma-separated and not truncated. Empty result prints `No bookmarks found.`

```
ID        TITLE                                     URL                                                 TAGS
a1b2c3d4  The Swift Programming Language             https://docs.swift.org/swift-book/                 swift, docs
9f8e7d6c  Vapor: Server-side Swift web framework     https://vapor.codes/                               swift, swift/vapor
```

**`stash get <id>`**: a labeled block:

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

**`stash tags`**: `name (count)` per line:

```
swift (42)
swift/vapor (12)
docs (7)
```

**`stash admin users`**: columns USERNAME (20), ROLE (6), ACTIVE (7), 2FA (4),
BOOKMARKS (10), ID (full UUID). ACTIVE is `yes`/`no`; 2FA is `on`/`off`.

**`stash admin stats`**: two summary lines then a table:

```
Total users:     3
Total bookmarks: 214

USERNAME              ACTIVE   BOOKMARKS
alice                 yes      120
bob                   no       94
```

### JSON (`--json`)

Keys are sorted alphabetically. Dates are ISO-8601 without fractional seconds.

**`stash list --json`**: the full paginated page (a `BookmarkDTO` list +
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

**`stash get <id> --json`**: a single bookmark object (the same shape as one
`items` element above).

**`stash add --json`**: the created bookmark object (same shape).

**`stash tags --json`**: an array of tag objects:

```json
[
  { "count" : 42, "name" : "swift" },
  { "count" : 12, "name" : "swift/vapor" }
]
```

**`stash admin users --json`**: an array of user objects:

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
