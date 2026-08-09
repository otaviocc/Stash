# Stash: Decision Log

This is my running log of the technical and design decisions I made while
building Stash, the companion to [`PRODUCT.md`](./PRODUCT.md). `PRODUCT.md`
says what I set out to build; this records how I actually built it and why,
especially the choices that aren't obvious from the code, the places I
deviated from the plan, and the trade-offs I accepted along the way.

### How this is organized

This file is now an **index**. The entries themselves are split into topical
files under [`Docs/`](Docs/) so each stays small enough for an LLM to load only
the relevant subsystem. Entries keep their original chronological order *within*
each file (so milestone history and later "superseded" reversals still read in
sequence). If you need decisions about one area, open that area's file; if
you're not sure which file, scan the entry lists below.

### Conventions used in the entries

- PRD sections are referenced as `§n` (see [`PRODUCT.md`](./PRODUCT.md)).
- A decision later reversed is marked *Superseded* in prose with a pointer to
  what replaced it, rather than being deleted, so a topical file may contain
  both the original decision and its later reversal.
- This is a decision log, not API docs; endpoint/behavior reference lives in
  [`Docs/api.md`](Docs/api.md).

---

## Topical files

### [`Docs/decisions-conventions.md`](Docs/decisions-conventions.md)
Cross-cutting conventions, code style, and project structure.
- Cross-cutting conventions (`StashErrorMiddleware`, VaporTesting + SQLite)
- Linting & formatting (SwiftLint + SwiftFormat)
- Code style: comments and documentation
- Code style: blank lines
- Code style: commit messages
- iOS/macOS project: committed, off XcodeGen
- Merged the iOS and macOS targets into multiplatform targets
- StashApp: fixed miscategorized files within `Stash/`
- Documentation (one `Docs/` folder, no per-component READMEs)
- Markdown style: hard line breaks
- SwiftUI view decomposition convention (`make…() -> some View`)
- Per-machine signing & bundle identifier (xcconfig)

### [`Docs/decisions-backend.md`](Docs/decisions-backend.md)
Vapor backend: API, migrations, admin tools, and instance features.
- M1: Auth foundation · M2: Bookmarks · M3: Admin API · M5: Web admin dashboard
- Backend: reorganized `Sources/App/` by surface (API / Web / Core)
- Backend: decomposed `AppWebController` into per-domain controllers + presenters
- Site Settings & Admin Customization
- Favicon Caching
- OpenAPI specification
- Release images: build natively per-arch instead of via QEMU
- Admin health page (kept separate from public `/health`)
- Admin database maintenance: a manual VACUUM button
- Feature: Favicon Cache Management (admin tool)
- Feature #6: Audit log · Feature #7: Active Sessions · Feature #8: System Logs
- Feature: Internet Archive (Wayback Machine) submission
- Feature: Instance management: update checker + backup/restore
- `Script/bump-version.sh`: one script, three version numbers
- Editable footer links
- Appearance audit log: record actual changes
- Feature: "Read Later" flag (`isReadLater`)

### [`Docs/decisions-web.md`](Docs/decisions-web.md)
Server-rendered web frontend (`/app`) and admin dashboard (`/admin`).
- M11: User-facing web frontend · Frontend improvements (post-M11)
- Import / Export
- Tag sidebar (bookmark list)
- Dark mode (web frontend + admin dashboard)
- Danger zone: delete all bookmarks
- Tag renaming · Tag deletion
- Editable server URL on the login screen
- Cross-links between the `/app` and `/admin` web navs
- Appearance theme swatches respect dark mode
- Tags & Smart Views web UI: table layout and delete confirmation
- Public landing page at `/`
- Web CSS and JS extracted to static assets
- Landing page copy updates (offline sync, instance management)
- Visual polish: bookmark list mirrors the native row (web frontend)
- WebUI favicon placeholder
- Accent-aware button text contrast
- Bookmark detail: preserve list return context (`returnTo`)
- "Read Later" in the web frontend

### [`Docs/decisions-native-apps.md`](Docs/decisions-native-apps.md)
iOS/macOS SwiftUI apps and the Share Extension (excluding offline sync).
- M8: iOS app (core) · M9: iOS Share Extension · M10: macOS app (+ target bump to 26)
- Token refresh: concurrent-refresh race (macOS spurious logout)
- macOS Share Extension: three platform-specific fixes
- Bookmark detail: consistent macOS Form action buttons
- iOS account settings: password change + 2FA at macOS parity
- Native apps: hierarchical tag sidebar · Flat-indented (web-parity) tag tree
- App icon: the bookmark-ribbon mark
- Accent palette: added Terracotta · replaced Terracotta with Indigo
- Tag picker · Tag pills mirror web hierarchy · Tag count badge
- Drag-and-drop tagging · Native share (row menu + detail)
- Visual polish passes (bookmark list/detail/empty states, add/edit, settings, share ext)
- Sidebar selection occasionally stops refreshing the detail list
- Tag sidebar refreshes after a sync
- Bookmark row tags: accent capsules
- Unreachable backend: fail-fast timeout & recoverable 2FA setup state
- iOS background refresh logged the user out (Keychain protection class)
- Account & Smart View screens moved onto native grouped Forms
- Native clients fetch metadata on-device (out-of-radius add)
- Share Extension picks tags offline (out-of-radius add)
- In-app browser preference (iOS/iPadOS)
- Refresh Favicon and Save to Wayback Machine (native apps)
- macOS browser picker: open links in a chosen browser
- "Read Later" in the iOS/macOS apps and Share Extension

### [`Docs/decisions-offline-sync.md`](Docs/decisions-offline-sync.md)
The native-app offline-sync feature, built in phases with many correctness fixes.
- Phase 1 (backend endpoints + StashKit) · Phase 2 (SwiftData store) · Phase 3
  (SyncEngine, connectivity, background refresh) · Phase 4 (status UI)
- Code review fixes · Optimistic writes (supersedes write-through)
- Live list refresh after an external sync · "Last synced" ticks live
- Cross-user data integrity fixes · Sync correctness fixes (#3, #4+#8, #5)
- Cleanup sweep · Refresh button triggers a sync · macOS foreground sync trigger

### [`Docs/decisions-smart-views.md`](Docs/decisions-smart-views.md)
Smart Views across all surfaces.
- Smart Views (match modes, JSON conditions, the Postgres `jsonb` gotcha)
- Smart View import / export
- Smart Views on the CLI and native apps (consumption-only)
- Smart View create / edit / delete in the native apps
- Smart View relative date conditions (`olderThan` / `newerThan`)
- Smart View form: condition row buttons follow-up
- Smart View condition: `isReadLater`
- `GET /smart-views/{id}/bookmarks` silently drops query, tag, and archived

### [`Docs/decisions-clients.md`](Docs/decisions-clients.md)
Shared package and non-Apple clients.
- M6: StashKit (shared Swift package)
- M7: CLI (`stash`)
- Browser Extension
- 2FA disable / reset land on the JSON API
- "Read Later" on the CLI and browser extension

### [`Docs/decisions-deployment.md`](Docs/decisions-deployment.md)
Docker, CI/CD, HTTPS, and licensing.
- M4: Docker & deployment · M4.1: CI/CD pipeline & Docker image publishing
- HTTPS / Caddy
- Documentation: Podman runtime & local-dev compose override
- Open-sourcing prep (footer link, scrubbed identifiers, OSS scaffolding)
- License: split MIT into AGPLv3 (Backend) and MIT (everything else)
