# Stash PRD: CLI, StashKit, iOS/macOS Apps & Browser Extension (§14\u201317B)

_Part of the Stash Product Requirements Document. See [`PRODUCT.md`](../PRODUCT.md) for the index._

---

## 14. CLI: `stash` ✅ Complete (M7)

Swift CLI, `ArgumentParser` + `MicroClient` (direct, for 2FA login branch),
`StashKit`. Config: `~/.config/stash/config.json`.

```
stash login / logout

stash add <url> [--title] [--description] [--tag] [--no-fetch] [--json]
stash list [--tag] [--search] [--archived] [--page] [--json]
stash get <id> [--json]
stash delete <id>
stash archive <id>
stash tags [--json]
stash tags rename --from <tag> --to <tag>
stash tags delete <tag>
stash smart-views [list] [--json]
stash smart-views bookmarks <id> [--page] [--per] [--json]
stash import <file> [--format anybox|stash-json]
stash export [--format stash-json] [--output <path>]

stash admin users [--json]
stash admin create-user --username <u> --password <p>
stash admin suspend-user / unsuspend-user <username>
stash admin reset-password <username> --password <p>
stash admin reset-totp <username>
stash admin delete-user <username>
stash admin stats [--json]
```

`stash export` of a Stash JSON file includes the user's Smart Views, and `stash import` of a
Stash JSON file restores them (matched by name, via the Smart View REST API), at parity with the
web frontend. The CLI cannot preserve a Smart View's `createdAt` (no direct DB access), the same
limitation already noted for bookmarks.

**Smart Views are consumption-only on the CLI.** `stash smart-views` lists the user's Smart Views
(name, match mode, a condition summary, and the full UUID); `stash smart-views bookmarks <id>` runs
the saved query server-side and prints the matching bookmarks in the same table / `--json` shape as
`stash list`. Creating and editing Smart Views is done in the web frontend (or round-tripped via
import/export); a richer condition-builder CLI is a possible later step.

---

## 15. StashKit: Shared Swift Package ✅ Complete (M6)

Built on `MicroClient` (`from: "0.0.27"`). Swift tools 6.0, iOS 26.0 / macOS
26.0.

I split it into three layers: **DTOs** (Codable/Sendable structs matching API
wire shapes), **request factories** (one `enum` per domain, `public static`
methods returning typed `NetworkRequest<…>`), and a **thin `StashClient`**
(wraps `NetworkClient`, adds `BearerAuthorizationInterceptor` +
`ContentTypeInterceptor` + `AcceptHeaderInterceptor`, maps errors to
`StashAPIError`).

No storage, no refresh logic, no business logic. `tokenProvider: @escaping
@Sendable () async -> String?` keeps the package storage-agnostic. Tag cache and
silent refresh are the app's repository layer responsibility.

Domains covered by request factories: auth, user, bookmarks, tags, metadata,
admin, instance (the public accent-theme endpoint, §9.9), and
`SmartViewRequestFactory` (list/create/get/update/delete plus the
`:id/bookmarks` query), with matching `SmartViewDTO` / `SmartViewConditionDTO`
DTOs and a `SmartViewRequest` body.

---

## 16. iOS App ✅ Complete (M8 + M9)

### Project

- `StashApp/Stash.xcodeproj` is committed and uses synchronized folder groups
  (I retired XcodeGen, see `DECISIONS.md`)
- Single multiplatform SwiftUI app target `Stash` (iOS 26.0 + macOS 26.0) and
  one multiplatform Share Extension target
- Bundle ID: `com.example.otavio.stash`
- App Group: `group.com.example.otavio.stash`
- `NSAllowsArbitraryLoads: true`
- Direct dependency on `MicroClient` (for 2FA login branch, same as CLI)

### Architecture

**Layers:** `StashKit` (DTOs + factories) → `Repository` (DTO→domain mapping,
session state, tag cache) → `ViewModel/View`

**`AppEnvironment`**: `@MainActor @Observable` DI container built once at
launch. Exposes `makeBookmarkRepository()` (per-view instances) rather than a
shared instance; `AuthRepository` and `TagRepository` remain shared singletons.

**Repository pattern:** `AuthRepository`, `BookmarkRepository`, `TagRepository`
are `@MainActor @Observable`. Silent refresh centralized in
`AuthRepository.refreshIfNeeded()` behind a `SessionRefreshing` protocol to
avoid reference cycles.

**Offline sync (complete):** the apps keep a full SwiftData copy of the user's
bookmarks (`LocalStore` + `LocalBookmark`, owned by `AppEnvironment`).
`BookmarkRepository` reads entirely from this store: search, tag, recency, and
Smart View filters run in memory, mirroring the backend's SQL semantics, so
browsing works without the network. `TagRepository` derives the tag list from the
store.

`SyncEngine` runs a pull-then-push cycle with last-write-wins: it pulls
`GET /bookmarks/changes?since=` and `GET /bookmarks/deleted?since=` (the `since`
cursor is persisted; the first, cursor-less pull seeds the whole library), then
pushes every queued local change. Writes are optimistic: a create, edit, or delete
applies to the local store and returns immediately (`pendingSyncAt`/`isLocalOnly`/
`locallyDeletedAt`), so the UI updates instantly whether online or off, then a
background sync pushes the change and reconciles the list with the server's
authoritative result. A `ConnectivityMonitor` (`NWPathMonitor`) triggers a sync when
connectivity returns; sync also runs on launch/login, after each write, and on
returning from the background, which on macOS includes the app being reactivated
(foregrounded), since macOS `scenePhase` does not track focus changes, and iOS
schedules a background-refresh sync (`BGAppRefreshTask`).

Sync state is surfaced in the UI: a slim offline banner across the top of the app
shell while disconnected, a muted pending indicator on rows and the detail header
for bookmarks with unpushed changes, and a Settings "Sync" section showing the last
sync time and pending count with a "Sync Now" button and a dismissible failure
notice. The Share Extension saves online-only, but its **tag picker works offline**: the
app caches its derived tag list into the App Group so the extension can offer the same
hierarchical tag tree even when the backend is unreachable (see `DECISIONS.md` → Share
Extension picks tags offline). macOS background-task scheduling is a known follow-up (the
entitlement is in place, the scheduler is not yet wired). See `DECISIONS.md` → Offline Sync.

**`StashClientProvider`**: rebuilds `StashClient` only when the server URL
changes. `tokenProvider` closure reads from `TokenManager` at request time.

### Keychain

`KeychainStore` vendored from Triton, extended with optional `accessGroup:
String?` parameter for Share Extension token sharing. Both tokens (access +
refresh) stored in Keychain, enables cold-start session restoration and Share
Extension reuse (deviation from original memory-only access token spec).

`TokenManager` decodes JWT `exp` by hand (base64url, no library) for
`isAccessTokenExpiringSoon()`.

### Navigation

- **iPad:** `NavigationSplitView`, a sidebar with a **Views** section (All,
  Untagged, Today, This Week), an optional **Smart Views** section (one entry per
  Smart View, shown only when the user has any), and an **always-expanded, indented
  hierarchical tag tree** (a flattened `ForEach`, mirroring the web sidebar), all
  driving the filtered `BookmarkListView` in the detail column. **Drag a bookmark row onto a tag** in the
  sidebar to add that tag to the bookmark (iPad and macOS only, where the sidebar
  and list share the screen; disabled on iPhone)
- **iPhone:** `TabContainerView`, Bookmarks / Tags / Settings tabs, each in its
  own `NavigationStack`. The Tags tab shows the same Views, the optional Smart
  Views section, and the always-expanded indented tag tree, drilling into a filtered list. Tab
  bar uses iOS 26 floating Liquid Glass style; collapses on scroll via
  `tabBarMinimizeBehavior`
- Bookmark rows use closure-based `NavigationLink` (not
  `navigationDestination(for:)`) to avoid multi-depth registration conflicts
- Login uses typed `LoginRoute` enum for 2FA navigation

### Views (core)

`RootView` → `SetupView` / `LoginView` / `TOTPView` / `RecoveryCodeView` /
`MainView` → `BookmarkListView` / `BookmarkDetailView` (stub) /
`AddBookmarkSheet` / `TagBrowserView` (Views + always-expanded indented hierarchical
tag tree, rows shared with the iPad/macOS sidebars as `TagTreeLabel`) /
`SettingsView` (server URL, account settings, Sign Out) → `AccountSettingsView`

The tag tree is built client-side from the flat `GET /api/v1/tags` list by
`[Tag].hierarchy()` → `[TagNode]`, a Swift port of the web's `buildSidebar`:
every `/`-delimited ancestor becomes a node (synthetic parents carry no count),
nested and alphabetical at each level.

Liquid Glass design adopted automatically: tab bar floats over content,
toolbars and navigation bars gain glass background. No explicit `.liquidGlass`
calls needed; compiling against iOS 26 SDK is sufficient.

`FaviconView` (`AsyncImage`, fallback `"link"` SF Symbol, `RoundFaviconModifier`
a 16×16 icon with 4pt corners on an 18×18 always-light background so icons designed
for white backdrops stay legible in dark mode) loads favicons from the configured Stash instance's cached
endpoint (`GET /api/v1/favicons/:domain`, §9.8) keyed by the bookmark's domain,
no longer Google directly. A 404 (uncached domain) falls back to the placeholder.

`BookmarkRowView` shows first three tags + `+N` overflow (not a scrolling row,
avoids gesture conflict in lists). Tags render as `TagPill`s that display a
hierarchical tag as `swift › server` (middot `›`, U+2023), mirroring the web,
presentation only; the stored tag and `tag=` filter keep the raw `swift/server`
slug.

`AddBookmarkSheet`: paste button (`PasteButton`, no `UIKit`), metadata fetch,
and tag editing via `TagPickerSheet`. The form shows a read-only tag summary
(capsule `TagPill`s, or a muted "No tags") plus an "Add Tags" button that
presents `TagPickerSheet`, a sheet over the always-expanded, indented
hierarchical tag tree with single-tap toggle and search-as-create (the search
field doubles as new-tag input: when the normalized query matches no existing
tag a `+ Create "…"` row adds it without closing the sheet). `TagSuggestionView`
autocomplete chips are retained only for `SmartViewFormView`'s single-tag
condition field.

Each bookmark row carries a context menu (and the detail view an actions
section) with a native **Share…** (`ShareLink(item: bookmark.url)`, sharing the
URL) placed after the Copy actions, followed by **Refresh Favicon** (conditional
on `faviconDomain` being non-nil, triggers a server-side background re-fetch via
`POST /api/v1/favicons/:domain/refresh`) and **Save to Wayback Machine** (always
shown, submits or re-submits to the Internet Archive via
`POST /api/v1/bookmarks/:id/wayback`; a `409` when the admin has disabled
submissions instance-wide surfaces as an error message). A **View on Wayback
Machine** action appears after that, shown only when the bookmark has a
captured Internet Archive snapshot (`waybackURL` non-nil). All Wayback and
favicon actions open via the same `openURL` environment action as "Open in
Browser" (§7.2, §12), so they automatically pick up the in-app-browser/Reader-mode
routing described below with no extra plumbing.

Context-aware empty states: `ContentUnavailableView.search` for active query,
tag-specific, archived-specific, first-run.

### Account settings (iOS)

`SettingsView` reaches the shared `AccountSettingsView` (change password, enroll /
disable 2FA, the same screen the macOS Settings window uses) via a navigation link
on iPhone and a sidebar toolbar button on iPad. `AccountSettingsView` and
`QRCodeView` are cross-platform; only window-chrome sizing is `#if os(macOS)`-guarded.

`SettingsView` also carries a **Reading** section with two controls. **Browser** (a
picker: **In-App** (the default) or **Default Browser**) decides where a tapped
bookmark link opens: In-App presents the page inside the app in an
`SFSafariViewController` (Apple's recommended in-app browser); Default Browser hands
off to the system browser (the prior behavior). **Reader** (a toggle, default off)
opens supported in-app pages directly in Safari's Reader mode
(`SFSafariViewController.Configuration.entersReaderIfAvailable`); it applies only to
in-app browsing and is disabled when Browser is set to Default Browser. Both
preferences are stored in the App Group `UserDefaults` suite, and the interception is
centralized: an `openURL` environment override (`.inAppBrowser()`, applied to the
bookmark `NavigationStack`s) routes `http`/`https` opens to an in-app Safari sheet, so
it covers every open site: the detail-page URL `Link`, the "Open in Browser" button,
and the row context menu, without editing those shared views. **iOS/iPadOS only**;
macOS has no `SFSafariViewController` and always uses the default browser.

### Smart View management (iOS + macOS)

`SettingsView` also links to a shared `SmartViewManagementView` (a macOS Settings
tab) that lists the user's Smart Views with create / edit / delete. Creating and
editing use a shared `SmartViewFormView` sheet: a name, an All / Any match-mode
picker, and a list of condition rows whose value editor adapts to the condition
type (text, a tag field with autocomplete chips, a date picker, or a Yes/No
picker). Date conditions are serialized as full ISO-8601 (`…T00:00:00Z`), since the
JSON API (unlike the web form) does no date normalization. Deletes confirm. The
sidebar Smart Views section stays browse-only; because the shared
`SmartViewRepository` cache updates on every write, sidebar entries reflect edits
and deletes live.

---

## 17. macOS App ✅ Complete (M10)

macOS 26.0 is a destination of the **single multiplatform `Stash` target** (not
a separate target); the one `@main App` branches per platform with `#if
os(macOS)`. Adopts the macOS 26 design language (Liquid Glass) automatically by
building against the SDK; no explicit modifiers.

- **Navigation:** `NavigationSplitView` with a sidebar that has a **Views**
  section (All Bookmarks, Untagged, Today, This Week), an optional **Smart Views**
  section (one entry per Smart View, shown only when the user has any), and a
  **always-expanded, indented hierarchical tag tree** (a flattened `ForEach`,
  mirroring the web sidebar) driving the shared `BookmarkListView` in the detail column; selecting a
  bookmark pushes the shared `BookmarkDetailView`. I didn't build an optional
  inspector panel; the shared list already gets you there with less code to
  maintain. **Drag a bookmark row onto a tag** in the sidebar to add that tag to
  the bookmark (shared with iPad).
- **Window:** standard `WindowGroup`, 800×500 minimum
  (`windowResizability(.contentMinSize)`).
- **Bookmarks:** shared list and rows; right-click context menu (Open in
  Browser, Copy URL, Copy Markdown URL, Share…, View on Wayback Machine,
  Archive/Unarchive, Delete); add and edit via shared sheets; delete with
  confirmation. The detail view's actions section carries the same Copy and
  Share… actions (Share… is a native `ShareLink` sharing the bookmark URL,
  placed after Copy and before Archive). **View on Wayback Machine** (shared
  with iPad/iPhone) appears in both the detail view and the row context menu,
  after Share… and before Archive, only when the bookmark has a captured
  Internet Archive snapshot (`waybackURL` non-nil, synced down from the
  backend's Wayback submission queue — §7.2); opens the real snapshot URL via
  the same `openURL` action as "Open in Browser". Read-only: the native apps
  don't yet expose the instance/user auto-submit toggles or a manual "submit
  now" action (web-only for now, §13).
  Tags render as `TagPill`s showing `swift › server` (middot `›`, U+2023),
  mirroring the web; the stored tag keeps the raw slash slug. Tag editing on the
  add/edit sheets uses the shared `TagPickerSheet` (read-only `TagPill` summary +
  "Add Tags" button → the always-expanded tag tree with single-tap toggle and
  search-as-create).
- **Settings scene (⌘,):** General (server URL, sign out, and a **Browser**
  picker), Account (change password, 2FA enroll / disable), Smart Views
  (create / edit / delete, the shared `SmartViewManagementView`), Appearance
  (Light / Dark / Auto, stored in `UserDefaults`, no theme cookie on native).
  Accent colour is the system default (`Color.accentColor`); the native apps
  don't yet follow the instance's admin-configured accent theme, unlike the
  web frontend (see `DECISIONS.md`).
  The Browser picker lists **System Default Browser** (the default) plus
  every installed app that declares `http`/`https` handling, discovered via
  `NSWorkspace.urlsForApplications(toOpen:)` (no hardcoded browser list, so
  Firefox, Chrome, Safari, Orion, Brave, and anything else installed all show
  up the same way). The choice is stored as the browser's bundle identifier
  in the App Group `UserDefaults` suite (app-only; the Share Extension does
  not open links). Opening a bookmark link routes through a macOS-only
  `openURL` environment override (`.macBrowserChooser()`, applied above the
  whole `NavigationSplitView`, not inside its `detail:` column — see the
  decision log for why) that launches the chosen browser via
  `NSWorkspace.open(_:withApplicationAt:configuration:)`; if no browser is
  chosen, or the previously chosen one is no longer installed, it falls back
  silently to `.systemAction` (the system default browser). Same centralized-
  interception shape as the iOS in-app-browser preference, just a different
  destination. iOS/iPadOS keep their separate in-app-browser/Reader-mode
  preference; macOS has no in-app browser.
- **Keyboard shortcuts:** ⌘N new, ⌘E edit, ⌘R sync (triggers an offline-sync
  cycle), ⌘⌫ delete (with confirmation), and **Esc** to leave the bookmark
  detail and return to the list (the same binding ships on iOS/iPadOS, where it
  fires only when a hardware keyboard is attached, there is no on-screen Esc).
- **Share Extension:** the single multiplatform `StashShareExtension` target
  serves both platforms (same three states and confirmation-with-undo); only the
  principal controller differs: `MacShareViewController` (`NSViewController`)
  on macOS vs `ShareViewController` (`UIViewController`) on iOS, both
  `#if`-guarded.

---

## 17B. Browser Extension ✅ Complete

A WebExtension that saves the current page to a Stash instance from Firefox or
Chrome (including Zen), living in the top-level `Extension/` folder. It talks
directly to the REST API (`/api/v1/`), no backend, StashKit, or native-app
changes. Plain HTML + CSS + vanilla JS, no build step (the same philosophy as
the web frontend).

### Structure

```
Extension/
├── manifest.json     # WebExtension manifest v3 (Firefox + Chrome)
├── background.js     # Service worker — token storage, refresh, API calls
├── popup.html/.js/.css   # Toolbar button popup (add-bookmark form)
├── options.html/.js/.css # Settings page (server URL, sign in, 2FA)
├── icons/            # 16/32/48/128 PNGs + icon.svg master + generator
└── Makefile          # lint / icons / package / clean
```

Documented in [`Docs/browser-extension.md`](Docs/browser-extension.md).

The extension shares the Stash bookmark-ribbon identity: the 16/32 toolbar-action
icons stay a deep-indigo ribbon on a transparent background (legible on light and
dark toolbars), while the 48/128 add-ons-manager / store icons wear the full
app-icon look, a white ribbon on an indigo `#231468` rounded square, matching the
native apps and the web favicon.

### Supported browsers

Manifest v3, with the background declared as both `service_worker` (Chrome) and
`scripts` (Firefox/Zen) so one manifest serves both engines. Sideloaded via
developer mode
(`about:debugging` on Firefox, `chrome://extensions` → Load unpacked on Chrome);
distributable to the Firefox Add-ons store or Chrome Web Store.

### Behavior

Clicking the toolbar button opens a popup with the full add-bookmark form,
pre-filled with the active tab's URL (read-only) and title. A "Fetch metadata"
button pulls the server-side title/description (`POST /api/v1/metadata`, filling
only empty fields); tag input offers autocomplete chips from `GET /api/v1/tags`
using the web UI's per-segment prefix rule; "Save" creates the bookmark
(`fetchMetadata: false`). A duplicate URL surfaces inline as "Already saved" with
a link to the existing bookmark; a save confirmation offers a View bookmark link
and auto-closes. No undo (the popup lifecycle is too short), and no "save
another", the extension saves the page you are on, so there is nothing more to
add for the same tab.

### Authentication

Username + password against `POST /api/v1/auth/login`, with the access/refresh
pair stored in `chrome.storage.local`. The background service worker owns all
token storage and API calls (the popup/options pages communicate with it via
`chrome.runtime.sendMessage`); it decodes the JWT `exp` claim by hand and
silently refreshes within 60 s of expiry and once on any `401`, mirroring the CLI
and iOS app. The 2FA branch (`/api/v1/auth/totp`, `/api/v1/auth/recovery`) is
handled inline on the settings page. `host_permissions: ["<all_urls>"]` is
required because the self-hosted server URL is user-supplied and unknown at build
time.

---
