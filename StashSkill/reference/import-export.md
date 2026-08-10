# stash-cli: import and export

Reference companion to the `stash-cli` skill. Covers the `import` and
`export` commands, the accepted file formats, and their round-trip caveats.

---

## `import`

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
  `stash-json` file carries Smart Views, a second line follows: `Smart Views:
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
  Smart Views are restored too (matched by name; an existing name is updated, a
  new one is created), so re-import is idempotent for Smart Views as well.

Limitation: importing over the REST API cannot preserve original `createdAt` on
*new* records (they get a fresh timestamp); but re-importing a Stash export of
bookmarks that already exist takes the duplicate-update path, where the server
preserves `createdAt`, so re-import is idempotent. (The same `createdAt`
limitation applies to newly created Smart Views.)

## `export`

```bash
stash export [--format stash-json] [--output <path>]
```

- `--format` defaults to (and only accepts) `stash-json`.
- `--output` is the destination path; if omitted, writes to
  `stash-export-YYYY-MM-DD.json` in the current directory.
- Fetches **all** bookmarks, paginating through every page of both active *and*
  archived (100 per page), then assembles the native `{ version, exportedAt,
  bookmarks[], smartViews[] }` envelope (bookmarks sorted by `createdAt`
  ascending, Smart Views by name), and writes it. The user's Smart Views ride
  along in the same file, at parity with the web frontend's export.
- Output: `Exported <n> bookmarks and <m> Smart Views to <path>.`

