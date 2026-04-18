# Stash — Decision Log

A running record of the **technical and design decisions** made while building Stash, complementing
the requirements in [`PRODUCT.md`](./PRODUCT.md). Where `PRODUCT.md` says *what* to build, this
document records *how* it was built and *why* — especially the choices that aren't obvious from the
code, the deviations from the PRD, and the trade-offs accepted.

### How to maintain this document

- Update it whenever a milestone or a meaningful chunk of work is completed.
- Add new entries under the relevant milestone heading (create a new heading for new milestones).
- Keep entries short: **what was decided**, **why**, and the **trade-off or alternative** when one
  mattered. Reference PRD sections as `§n`.
- Prefer appending over rewriting history — a decision that was later reversed should be marked
  *Superseded* rather than deleted, with a pointer to what replaced it.
- This is a decision log, not API docs. Endpoint/behaviour reference lives in `Backend/README.md`.

### Status legend

✅ In effect · ⚠️ Deviation from `PRODUCT.md` · 🔁 Superseded

---

## Cross-cutting conventions

- **✅ Error envelope via custom middleware.** A `StashErrorMiddleware` replaces Vapor's default
  error middleware so *every* API error — including routing 404s and validation failures —
  serialises to the standard `{ error, code, message }` envelope (§17.4). Strongly-typed `APIError`
  cases own the status/code/message mapping; the duplicate-URL case carries an extra `existingID`.
- **✅ Testing stack.** `VaporTesting` + swift-testing, running against an in-memory **SQLite**
  database (§17.7), not Postgres — fast and isolated. Production uses Postgres; the only schema
  concession is that array/JSON columns map differently per driver (see M2).
- **✅ Leaf templates are not unit-tested** (§17.7). Instead, each web chunk is verified with a
  throwaway end-to-end smoke test (login → action → assert) that is **run and then removed**, since
  Leaf errors only surface at render time and the existing suite can't catch them.
- **⚠️ `fluent-sqlite-driver` added** (not in the §17.2 dependency table) because §17.7 mandates an
  in-memory SQLite test database. Postgres remains the production driver.

---

## M1 — Auth foundation

- **⚠️ TOTP implemented natively, not via `vapor/auth`.** §17.2 lists `vapor/auth.git` `from 2.0.0`
  for "built-in RFC-compliant TOTP". That package is the **Vapor 3-era** auth package; it does not
  exist for / compile against Vapor 4 (where `Authenticatable` lives in Vapor core and there is no
  bundled TOTP). RFC 6238 TOTP + Base32 are therefore implemented directly on top of `swift-crypto`
  (already a transitive dependency) in `Sources/App/Auth/`. Keeps the backend dependency-light, in
  line with the project's data-ownership philosophy. Every other §17.2 dependency is used as listed.
- **✅ Token strategy.** Access token = HS256 JWT, 15 min, carries a `scope` claim (`access`).
  The 2FA step uses a separate 5-min JWT with `scope = "2fa"` so a temp token can never be replayed
  as an access token. Refresh token = opaque 256-bit hex, stored only as a SHA-256 hash, 90-day
  expiry, **rotated** on every use (§8.1).
- **✅ bcrypt cost 12** (Vapor's default) for passwords and recovery codes (§8.5). Recovery codes
  are 8 × `XXXX-XXXX`, normalised (dash-free, uppercased) before hashing/verifying.
- **✅ Constant-time-ish login.** Unknown usernames still run a throwaway bcrypt verify so response
  timing doesn't leak account existence.
- **✅ `withTestApp`, not `withApp`.** The test boot helper is named distinctly on purpose:
  VaporTesting exports a generic `withApp`, and a single-expression test closure (e.g. just a
  `.test(...)` call) would infer a non-`Void` return and silently resolve to VaporTesting's overload,
  skipping our explicit `asyncBoot()` and leaving the responder unbooted — every route then 404s.
  Cost ~an hour to diagnose; the rename prevents recurrence.

---

## M2 — Bookmarks

- **✅ Tags stored twice for portable querying.** The canonical `tags` is a `[String]` field
  (`.array` → a `JSON` column, which works on both SQLite and Postgres). Hierarchical **prefix
  matching** (`tag=swift` matches `swift` and `swift/*`, §7.5) can't be done portably against an
  array/JSON column, so a derived `tags_search` text column holds a pipe-wrapped form
  (`|swift|swift/vapor|`) and the filter is two portable `LIKE` (`~~`) clauses. Single source of
  truth (`tags`); `tags_search` is kept in sync via `applyTags`.
- **⚠️ Tags normalised on write** — trimmed, lowercased, surrounding slashes stripped, `|` removed,
  de-duplicated. Lowercasing isn't explicit in the PRD, but every example is lowercase and it
  prevents a fragmented tag tree (`Swift` vs `swift`).
- **✅ Duplicate URL → 409 with `existingID`.** Enforced by a pre-check *and* a unique
  `(user_id, url)` index as a race backstop; the error envelope includes the existing bookmark's id
  (§9.3/§17.4).
- **✅ Metadata fetching is dependency-free and non-blocking.** `MetadataFetcher` uses Vapor's
  built-in HTTP client (5 s timeout, no retry, §10) and a small regex HTML parser — no scraping
  library. Fetching runs inline server-side (no internal HTTP round-trip). On any failure the save
  proceeds with whatever the client supplied; client-supplied title/description always win over
  fetched values. Title falls back to the URL when otherwise blank.
- **✅ Full-text `q` uses `LIKE` (`~~`).** Behaviour is **case-insensitive on SQLite,
  case-sensitive on Postgres** — the PRD doesn't specify, and this is left as a documented nuance
  rather than adding a normalised search column.
- **✅ `bookmarkCount` is a denormalised counter** on `User`, maintained on create/delete (§7.1);
  the `makeBookmark` test helper maintains it too so it reflects reality in tests.
- **✅ Pagination** uses Vapor's `Page<T>` (§17.5); `per` is clamped to 1–100.

---

## M3 — Admin API

- **✅ Admin role enforced by middleware.** `AdminMiddleware` is layered after the access-token
  authenticator + guard; authenticated non-admins get `403 forbidden` in the standard envelope.
- **⚠️ `username_taken` (409).** §17.4's code table has no username-conflict code, so one was added
  (mirrors the `duplicate_url` pattern).
- **✅ Accounts are always created as `user`.** Any `role` field in the create body is ignored;
  admin accounts exist only via first-boot seeding (§4). (Tightened from an earlier version that
  accepted `role` — see M3 correction.)
- **✅ Self-deletion blocked** with `400 cannot_delete_self`.
- **✅ Suspension *and* password reset both revoke refresh tokens** (§8.6) — any change to an
  account's security state forces re-authentication.
- **✅ Hard delete cascades explicitly** (bookmarks → refresh tokens → recovery codes → user) rather
  than relying on FK `ON DELETE CASCADE`, so it behaves identically on SQLite (tests) and Postgres
  regardless of FK enforcement.
- **✅ Per-user counts use the denormalised `bookmarkCount`** (same source as `/me`), keeping stats
  cheap and consistent.

---

## M4 — Docker & deployment

- **✅ Multi-stage image, jammy-matched.** Build stage `swift:*-jammy` → runtime `ubuntu:22.04`, so
  the build glibc/ABI matches the runtime. Static Swift stdlib + jemalloc; runtime carries only the
  binary and required libs. Arch-agnostic, so `buildx` produces `linux/amd64` + `linux/arm64`.
  (Build base started at `swift:5.10-jammy`; later bumped to `swift:6.1-jammy`.)
- **✅ First-boot admin seeding in `configure.swift`** (`AdminSeeder`, after migrations): seeds the
  admin from `ADMIN_USERNAME`/`ADMIN_PASSWORD` only when the DB has no users; **throws and exits** on
  missing/invalid credentials (don't start a login-less instance); no-op once any user exists; never
  runs against the test DB.
- **✅ Migrations auto-run on boot** (all environments) so the canonical `docker compose up -d`
  works with zero manual steps; Fluent records applied migrations, so it's idempotent.
- **✅ `.env.example` is Docker-oriented** — the four §16 variables (`DB_PASSWORD`, `JWT_SECRET`,
  `ADMIN_USERNAME`, `ADMIN_PASSWORD`); compose interpolates `DATABASE_URL` from `DB_PASSWORD`. Local
  non-Docker runs export `DATABASE_URL` directly.

---

## M5 — Web admin dashboard

- **✅ Session-cookie auth, separate from the JWT API** (§11). Cookie `stash_admin_session`, backed
  by an **in-memory** session store (fine for a single self-hosted instance — sessions just don't
  survive a restart). Entirely independent of `/api/v1/*`.
- **✅ Custom session payload over `ModelSessionAuthenticatable`.** The admin's user id is stored as
  a string in the session and reloaded by `AdminSessionMiddleware`, avoiding uncertainty around
  `UUID: LosslessStringConvertible`. The middleware redirects to `/admin/login` on any failure
  (missing/expired/suspended/demoted) instead of returning a JSON error, and `req.auth.login`s the
  user so handlers use `req.auth.require`.
- **✅ POST-only actions + PRG.** HTML forms can't issue PUT/DELETE, so suspend/reset/delete are
  `POST` sub-routes; success uses Post/Redirect/Get with `?ok=` confirmation banners. Web handlers
  render error states or redirect rather than throwing (which would emit the JSON envelope).
- **✅ Render-with-status helper.** Responses with a non-200 status are built from `view.data`
  directly; the async `View.encodeResponse` overload didn't resolve cleanly, and `req.view.render`
  needs an explicit `let view: View = …` annotation to pick the async overload.

---

## M11 — User-facing web frontend

- **✅ Second session cookie, shared store.** The frontend uses its own `stash_session` cookie
  (path `/app`) via a dedicated `SessionsMiddleware`/`SessionsConfiguration`, distinct from the
  admin dashboard's cookie but sharing the same in-memory driver. `UserSessionMiddleware` admits any
  **active** account regardless of role; suspended accounts are rejected.
- **✅ Shared `layout.leaf`.** Both web sections reuse one base template + inline CSS. The `<title>`
  prefix is conditional (`Stash Admin` vs `Stash`); a side effect is the admin *login* tab title
  changed cosmetically — accepted as trivial.
- **✅ Two-button add flow, no JS.** "Fetch metadata" previews title/description via an inline
  server-side fetch; "Save" persists (auto-fetching any blank fields). Duplicate URL shows an inline
  error linking to the existing bookmark. The edit form intentionally **doesn't allow URL changes**,
  sidestepping duplicate-handling there.
- **⚠️ 2FA setup shows the otpauth URI + setup key, not a scannable QR image.** Server-side QR
  rendering would need a QR-encoding dependency (no CoreImage on Linux), which conflicts with the
  minimal-deps goal. Manual key entry is fully functional; a QR image can be added later if desired.
- **✅ Leaf gotchas codified.** `#if(count(x))` does **not** coerce an `Int` to `Bool` (count 0 read
  as truthy) — always write `#if(count(x) > 0)`. Inline conditionals require the colon:
  `#if(cond): … #endif`.

---

## Frontend improvements (post-M11)

- **✅ Self-service 2FA disable requires a current TOTP code**, not just a password — this proves
  the user still controls their authenticator before 2FA is turned off (`POST
  /app/settings/totp/disable`). On success it clears the secret/flag and deletes recovery codes.
- **✅ Admin 2FA reset also revokes refresh tokens.** `POST /admin/users/:id/reset-totp` clears the
  secret/flag and recovery codes *and* deletes the user's refresh tokens, since their session
  security level changed — forcing re-login. Self-reset is allowed (no confirmation code; admin
  action suffices).
- **✅ Tag autocomplete with zero new requests.** The user's existing tags are embedded as a JSON
  array in a `data-known-tags` attribute on the create/edit forms; a ~50-line dependency-free
  vanilla JS block in `layout.leaf` filters the comma-segment under the cursor and offers
  prefix matches (full hierarchical strings like `swift/vapor` included). The attribute is
  **single-quoted** so Leaf's HTML-escaping of the JSON quotes survives — the browser entity-decodes
  the attribute value before `JSON.parse`, avoiding the need for an unescaped-output Leaf tag.

---

## Import / Export

- **✅ Pluggable registry architecture.** `BookmarkImporter`/`BookmarkExporter` protocols expose
  static metadata (`identifier`, `displayName`, `fileExtension`, exporter `mimeType`) plus one
  instance method each. A singleton `ImportExportRegistry` holds the registered instances; the
  settings UI's selectors and the import/export routes are driven entirely off the registry, so a
  new format is added by conforming a type and adding one `register(...)` line in the registry's
  `init` — **no controller, route, or template changes**. The registry is `@unchecked Sendable`:
  registration happens once in `init` and it's immutable thereafter, so concurrent request reads are
  safe.
- **✅ Importer owns data consistency.** The importer takes only `(data, userID, db)` and is
  responsible for everything: per-record validation, duplicate handling, and bumping the
  denormalised `User.bookmarkCount` by the number of rows it created. Keeps the controller a thin
  orchestrator and the behaviour identical regardless of caller.
- **✅ Parse-failure vs bad-record split.** A file that can't be parsed at all throws
  `ImportError.invalidFormat` (controller re-renders settings with an inline error, no redirect).
  Individual bad records (missing/invalid URL, etc.) are **counted and described** in
  `ImportResult.skipped`/`.errors`, never thrown — surfaced in a collapsible `<details>` block.
- **✅ Preserving `createdAt` on import.** Fluent's `_create` calls `touchTimestamps(.create, .update)`
  unconditionally, so a pre-set `createdAt` is overwritten on insert. Anybox's `date_added` is
  therefore restored with a **follow-up `save`** (an update only touches `updatedAt`, leaving the
  re-set `createdAt` intact). Duplicate-URL updates never touch `createdAt` for the same reason.
- **⚠️ Anybox's real export shape differs from the PRD example**, discovered against an actual
  file. Corrected mapping:
  - **`tags` is `[[String]]`** — arrays of `[namespace, value]` pairs (e.g.
    `[["topic","music-gear"],["status","wishlist"]]`), not a flat `[String]`. Each pair is joined
    with `/` into a hierarchical Stash tag (`topic/music-gear`), then normalised — a natural fit for
    Stash's slash-hierarchy. A plain `[String]` is still accepted as a fallback. (The original
    decoder assumed `[String]` and threw `typeMismatch` → "doesn't look like an Anybox export".)
  - **`dateAdded`** (camelCase, **ISO-8601 string**) → `createdAt`, not `date_added` (Unix int) as
    documented. A numeric `date_added`/`dateAdded` is accepted as a fallback; missing → current
    time. Decoding is done with a custom `init(from:)` so any single bad field degrades gracefully
    rather than failing the whole file.
  - `folder` is ignored (flat import), as are `comment`/`article`/`keyword`/`isStarred`. Missing
    `title` → empty string. Duplicate URL → overwrite title/description/tags in place. Verified
    against a real 211-bookmark export (all imported, re-import idempotent).
- **✅ Export is the native format and complete.** `stash-json` emits `{ version, exportedAt,
  bookmarks[] }` with ISO-8601 timestamps, **all** bookmarks (archived included), sorted by
  `createdAt` ascending. `withoutEscapingSlashes` keeps URLs readable. Versioned (`"1"`) so future
  schema changes are detectable by importers.
- **✅ Post/Redirect/Get with a session flash.** A successful import redirects to
  `/app/settings?imported=1`; the full `ImportResult` (including the skipped-record descriptions,
  which are too large/numerous for the query string) is flashed via a one-shot JSON value in the
  session and cleared on read.
- **✅ Upload body limit raised.** The import route uses `.on(.POST, … body: .collect(maxSize:
  "16mb"))` because Vapor's default collected-body cap (16KB) would reject any real export file.
- **✅ Multipart upload** via Vapor's `File` in a `Content` form struct; the export download sets
  `Content-Disposition: attachment; filename="stash-export-YYYY-MM-DD.json"`.
- **✅ Stash JSON importer (`stash-json`) — backup restore / round-trip.** Decodes the native
  export (`{ bookmarks: [...] }`), mapping `url` (required), `title`, `description`, `tags`
  (normalised), `isArchived`, `faviconURL`, and `createdAt` (ISO-8601; current time if
  missing/unparseable — accepts fractional seconds as a fallback). `id`/`updatedAt`/`version`/
  `exportedAt` are ignored. Duplicate URL updates in place (createdAt preserved), same contract as
  Anybox. Registering it was a one-line change in the registry — the settings selector picked it up
  with no template edits, validating the pluggable design.

---

## Tag sidebar (bookmark list)

- **✅ Flattened pre-ordered tree, not recursion.** Leaf has no clean recursion, so the tag tree is
  built server-side into a flat `[SidebarTag]` carrying `depth`, and the template indents each row
  by `calc(depth * 0.9rem)`. The list is produced by sorting all tag slugs by their `/`-split path
  components (prefix-first) — which *is* a pre-order DFS: a parent always precedes its subtree and
  siblings are alphabetical at every level.
- **✅ Synthetic parents.** If only `swift/vapor` exists, `swift` is still emitted as a parent node
  (so children nest under something) with `count = 0`; the template hides the count when 0.
  Synthetic parents remain clickable — `?tag=swift` prefix-matches `swift/*`, so the link is useful
  even without a bare `swift` tag.
- **✅ Counts are exact**, matching `/app/tags` (count of bookmarks with that literal tag), not the
  prefix aggregate — consistent with the rest of the app.
- **✅ Reuses the existing tag query.** The sidebar loads the user's bookmarks and tallies tag
  counts (same source as `/app/tags` and the autocomplete) — one extra `.all()` per list view,
  accepted for simplicity over a separate aggregate query.
- **✅ Encoded hrefs built server-side.** `?tag=swift%2Fvapor` is percent-encoded in Swift
  (`tagHref`) since Leaf/URLComponents leave `/` unencoded; the brief wants `%2F`.
- **✅ Layout & dark mode.** Two-column flex (`.app-main` flex:1 + `.tag-sidebar` fixed 220px,
  sticky/scrollable); hidden under 768px (the on-list filter pills cover mobile). All colours use
  existing variables — active tag is `--accent`, counts are `--text-muted`. `/app/tags` is
  unchanged.
- **⚠️ Leaf gotcha (extends the earlier ones).** `#if(cond):#else: X #endif` with an **empty
  then-branch** mis-parses (the else content is dropped). Use a positive single-branch test instead
  — the "All" active state uses `#if(tag == ""): class="active"#endif`.
- **✅ Sidebar positioning: just two flex columns (final).** Both `sticky` and `fixed` were tried
  and rejected — `sticky` scrolled away once past the parent's height, and `fixed` (viewport-
  anchored with magic `top`/`right` offsets) was brittle and detached from the content. The desired
  behaviour is the simplest: a normal two-column document where both columns scroll together as one
  unit. So `.tag-sidebar` has **no** `position`/`overflow`/`max-height`/scrollbar rules and
  `.app-main` has **no** reserve margin — just `.app-layout { display:flex; gap:1.5rem;
  align-items:flex-start }`, `.app-main { flex:1; min-width:0 }`, `.tag-sidebar { flex:0 0 220px;
  width:220px }`. The sidebar starts at the top of the layout and ends where its content ends.
  Mobile (<768px) hides it. (Supersedes both the sticky and fixed attempts.)
- **✅ "Tags" top-aligned with the search field.** The sidebar gets `margin-top: 3.25rem` so its
  heading lines up with the search box rather than the `Bookmarks` h1. The offset is derived from
  pinned values (`.app-main h1 { margin: 0 0 1rem }` → 2.25rem line + 1rem margin), so it's exact,
  not a guessed magic number; the h1 pin is scoped to `.app-main` so other pages are untouched.
  (Aligning with the *first bookmark cell* was rejected — the conditional "Filtered by tag" line
  moves that cell between filtered/unfiltered views, so a fixed offset couldn't track it.)
- **✅ "Untagged" filter via an internal sentinel.** `?tag=__untagged__` is special-cased in the
  list handler *before* the normal prefix path — it filters `tagsSearch == ""` (the value for a
  tagless bookmark). The untagged count is tallied from the same bookmark fetch that builds the
  sidebar (no extra query). The sentinel never reaches the UI as a label: the sidebar shows
  "Untagged" (sentinel only in the `href`), and the filter banner's `tagDisplay` is overridden to
  "Untagged".

---

## Dark mode (web frontend + admin dashboard)

- **✅ Cookie-only, no DB.** The theme preference (`light`/`dark`/`auto`, default `auto`) lives in a
  1-year `stash_theme` cookie at path `/` so it applies to both `/app` and `/admin`. No model field
  or migration — it's a pure presentation concern. The cookie is **`HTTPOnly=false`** on purpose so
  the inline flash-prevention script can read it; `SameSite=Lax`.
- **✅ Flash-of-wrong-theme prevention.** A tiny inline script at the top of `<head>` (before any
  CSS) reads the cookie and sets `data-theme` on `<html>` synchronously, before first paint. For
  `auto`/missing it sets nothing and lets the media query decide.
- **✅ CSS custom properties, three-way resolution.** All colours became variables on `:root`
  (light). Dark values are defined twice — under `[data-theme="dark"]` (explicit) and under
  `@media (prefers-color-scheme: dark) :root:not([data-theme="light"]):not([data-theme="dark"])`
  (auto). The duplication is intentional (matches the spec) so an explicit choice always wins over
  the OS preference. `color-scheme` is set per-mode so native controls/scrollbars match.
- **✅ Shared layout = free admin theming.** Because `/app` and `/admin` share `layout.leaf`, the
  variables + flash script apply to both with no admin-specific work. Theme is only *settable* from
  `/app/settings` (a plain HTML radio form → `POST /app/settings/theme` sets the cookie and
  redirects); the site-wide cookie path means it still themes `/admin`.
- **✅ Palette.** iOS-style dark (not pure black): bg `#1c1c1e`, surface `#2c2c2e`, border
  `#3a3a3c`, text `#f2f2f7`/`#aeaeb2`, accent `#0a84ff`, danger `#ff453a`, success `#30d158`. Pill
  and banner colours fold into the shared `--ok-*`/`--err-*` variables so they adapt automatically.

---

## Danger zone — delete all bookmarks

- **✅ Phrase confirmation, enforced on both ends.** `POST /app/settings/delete-all-bookmarks`
  re-checks the typed phrase (`delete all`, case-insensitive, trimmed) **server-side** — the
  client-side `oninput` enable/disable of the submit button is only a convenience, never the gate.
- **✅ Reveal-then-confirm, minimal vanilla JS.** A "Delete all bookmarks" button reveals a hidden
  form; a ~10-line inline script enables the submit button only when the input matches. No
  framework, consistent with the rest of `/app`.
- **✅ Scope is bookmarks only.** Deletes the user's bookmarks and resets `bookmarkCount` to 0;
  account, password, 2FA, and tag metadata (derived from bookmarks) are untouched. PRG redirect to
  `/app?notice=all_bookmarks_deleted` with a one-shot banner driven by a `notice(for:)` mapping
  (parallel to the existing `?ok=`/`message(for:)` convention).

---

## Linting & formatting (SwiftLint + SwiftFormat)

- **✅ Enabled the opt-in organization rules.** `organizeDeclarations` and `markTypes` are *disabled
  by default* in SwiftFormat; the `.swiftformat` supplied all their options but never turned the
  rules on, so no MARK organization was happening. Added `--enable organizeDeclarations` and
  `--enable markTypes`. Applied across all source + test files: MIT header, a `// MARK: - <Type>`
  before each type/extension, and in-type sections in **type mode** — `Nested Types → Static
  Properties → Properties → Computed Properties → Lifecycle → Functions` — with public-before-private
  *ordering within* each section.
- **✅ Type mode over visibility mode (user decision).** SwiftFormat emits either type marks *or*
  visibility marks, not both. Chose type mode (matching the config's `--organization-mode type` and
  the requested Nested Types/Properties/Lifecycle order); visibility mode was rejected because the
  codebase is overwhelmingly `internal`-access, so it would mostly produce `Internal`/`Private`
  headings rather than `Public`/`Private`.
- **✅ `Package.swift` is safe.** SwiftFormat keeps `// swift-tools-version:` as line 1 and skips the
  license header there.
- **✅ Disabled three SwiftLint rules that false-positive on Fluent.** `first_where`,
  `contains_over_first_not_nil`, and `empty_string` flag the query DSL (`.filter(\.$x == y).first()`,
  `first(where:) != nil`, `\.$field == ""`) — these are database builders, not `Sequence` ops, and
  rewriting them would break compilation.
- **✅ `identifier_name` exclusions** for idiomatic short names (`db`, `q`, `i`, `a`, `b`, `c`, `s`,
  `v`, `ok`, `ts`, `me`). The Anybox snake_case JSON key is handled with a proper Swift identifier
  instead of a lint exception: `case dateAddedUnix = "date_added"` in the `CodingKeys` enum.
- **⚠️ Disabled `file_length` / `type_body_length` / `function_body_length`** for consistency with
  the complexity family already disabled in the config (`line_length`, `nesting`,
  `cyclomatic_complexity`, `function_parameter_count`, `large_tuple`) — the web controllers and test
  suites legitimately run long. Easy to switch to soft thresholds instead if a size nudge is wanted.
- **✅ One inline `for_where` disable** in `AuthController` — the loop's predicate is `try await`,
  which a `where` clause can't hold.
- Result: `swiftlint lint` clean (0 violations), `swiftformat --lint` idempotent, build clean, 65
  tests pass.
