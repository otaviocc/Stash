# API and routes reference

The backend exposes three independent surfaces:

- a versioned JSON **REST API** under `/api/v1/` (JWT auth), consumed by the CLI
  and the apps,
- a server-rendered **admin dashboard** under `/admin` (its own session cookie),
  and
- a server-rendered **user web frontend** under `/app` (its own session cookie).

The JWT API and the two web UIs are independent: the web UIs use in-memory
session cookies (`stash_admin_session`, `stash_session`), not the JWT flow.

## REST API (`/api/v1/`)

All paths are under `/api/v1/` except `/health`, which is unversioned.

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| `POST` | `/auth/login` | — | Returns a token pair, or `{requires2FA, tempToken}` |
| `POST` | `/auth/totp` | temp token | Submit TOTP code |
| `POST` | `/auth/recovery` | temp token | Redeem a single-use recovery code |
| `POST` | `/auth/refresh` | — | Rotates the refresh token |
| `POST` | `/auth/logout` | — | Deletes the refresh token (204) |
| `GET`  | `/health` | — | Unversioned health check |
| `GET`  | `/me` | access token | Current user profile |
| `PUT`  | `/me/password` | access token | `{currentPassword, newPassword}` |
| `GET`  | `/auth/totp/setup` | access token | Begin 2FA enrolment |
| `POST` | `/auth/totp/verify-setup` | access token | Confirm; returns 8 recovery codes once |
| `GET`  | `/bookmarks` | access token | List; `?q=&tag=&archived=&page=&per=` |
| `POST` | `/bookmarks` | access token | Create; 409 `duplicate_url` (+`existingID`) on dupe |
| `GET`  | `/bookmarks/:id` | access token | Single bookmark (404 if not yours) |
| `PUT`  | `/bookmarks/:id` | access token | Update (all fields optional) |
| `DELETE` | `/bookmarks/:id` | access token | Delete (204) |
| `GET`  | `/tags` | access token | Distinct tags with counts |
| `POST` | `/tags/rename` | access token | Rename a tag (and its children); 422 if `from`/`to` empty |
| `DELETE` | `/tags/:tag` | access token | Delete a tag (and its children); 422 if empty; idempotent |
| `GET`  | `/smart-views` | access token | List the user's Smart Views |
| `POST` | `/smart-views` | access token | Create a Smart View; 422 on invalid name/conditions |
| `GET`  | `/smart-views/:id` | access token | Single Smart View (404 if not yours) |
| `PUT`  | `/smart-views/:id` | access token | Update a Smart View |
| `DELETE` | `/smart-views/:id` | access token | Delete a Smart View (204) |
| `GET`  | `/smart-views/:id/bookmarks` | access token | Run the query; `Page<Bookmark>` (`?page=&per=`) |
| `POST` | `/metadata` | access token | Fetch title/description/favicon for a URL |
| `GET`  | `/favicons/:domain` | none | Serve the domain's cached favicon image; 404 if uncached/failed/pending; `Cache-Control: public, max-age=2592000, immutable` |
| `POST` | `/favicons/:domain/refresh` | access token | Delete the cached row and re-fetch the favicon detached (202) |
| `GET`  | `/admin/users` | admin | List all users with stats |
| `POST` | `/admin/users` | admin | Create account; 409 `username_taken` on dupe |
| `GET`  | `/admin/users/:id` | admin | Single user (404 if unknown) |
| `PUT`  | `/admin/users/:id` | admin | Suspend/unsuspend (`isActive`) and/or reset `password` |
| `DELETE` | `/admin/users/:id` | admin | Hard delete + cascade all owned data (204) |
| `GET`  | `/admin/stats` | admin | Totals + per-user bookmark counts |

Errors use a standard `{ error, code, message, existingID? }` envelope across
every route, including routing 404s and validation failures.

## Web admin dashboard (`/admin`)

Server-rendered, unversioned, with its own `stash_admin_session` cookie,
separate from the API.

| Method | Path | Description |
|--------|------|-------------|
| `GET`/`POST` | `/admin/login` | Login form (username + password + optional TOTP) |
| `POST` | `/admin/logout` | Clear the session |
| `GET`  | `/admin` | Dashboard: total users, total bookmarks, per-user counts |
| `GET`  | `/admin/users` | User list |
| `GET`/`POST` | `/admin/users/new` | Create user (always `user` role) |
| `GET`  | `/admin/users/:id` | User detail |
| `POST` | `/admin/users/:id/suspend` · `/unsuspend` · `/reset-password` · `/reset-totp` · `/delete` | Actions |

## Web frontend (`/app`)

Server-rendered, unversioned, with its own `stash_session` cookie, separate from
the API and the admin dashboard.

| Method | Path | Description |
|--------|------|-------------|
| `GET`/`POST` | `/app/login` | Login (username + password + optional TOTP); any active role |
| `POST` | `/app/logout` | Clear the session |
| `GET`  | `/app` | Bookmark list; `?q=`, `?tag=` (prefix), `?archived=true`, `?page=` |
| `GET`  | `/app/bookmarks/new` | Add bookmark form |
| `POST` | `/app/bookmarks` | Create (`action=preview` fetches metadata; `action=save` persists) |
| `GET`  | `/app/bookmarks/:id` | Detail |
| `GET`  | `/app/bookmarks/:id/edit` | Edit form |
| `POST` | `/app/bookmarks/:id` | Update (title, description, tags, archived) |
| `POST` | `/app/bookmarks/:id/delete` · `/archive` · `/unarchive` | Actions |
| `POST` | `/app/bookmarks/:id/refresh-favicon` | Re-fetch the domain's cached favicon (PRG → `?ok=favicon_refreshing`) |
| `GET`  | `/app/tags` | Tag browser table (counts, links to `/app?tag=…`, inline rename, confirm-dialog delete) |
| `POST` | `/app/tags/rename` | Rename a tag (PRG → `?ok=renamed` banner) |
| `POST` | `/app/tags/delete` | Delete a tag and its children (PRG → `?ok=deleted` banner) |
| `GET`  | `/app/smart-views` | Smart Views management table (Edit / confirm-dialog delete) |
| `GET`/`POST` | `/app/smart-views/new` | Create Smart View (condition builder; PRG → `?ok=saved`) |
| `GET`  | `/app/smart-views/:id` | Smart View results (reuses the bookmark-list view) |
| `GET`/`POST` | `/app/smart-views/:id/edit` | Edit Smart View (PRG → `?ok=saved`) |
| `POST` | `/app/smart-views/:id/delete` | Delete a Smart View (PRG → `?ok=deleted` banner) |
| `GET`  | `/app/settings` | Settings |
| `POST` | `/app/settings/password` | Change own password |
| `GET`  | `/app/settings/totp` · `POST /verify` · `POST /disable` | 2FA enrolment / disable (requires a current code) |
| `POST` | `/app/import` | Import bookmarks from an uploaded file (multipart; format selector) |
| `GET`  | `/app/export?format=…` | Download all bookmarks as a file (attachment) |
| `POST` | `/app/settings/delete-all-bookmarks` | Danger zone: delete all of the user's bookmarks (typed-phrase confirmation) |

Import/export is pluggable; it ships with Anybox JSON and Stash JSON importers
and a Stash JSON exporter. Theme (light/dark/auto) is a `stash_theme` cookie
shared by both web UIs.

## Talking to the API from Swift

The [`StashKit`](stashkit.md) package provides typed DTOs and request factories
for the REST API, used by both the CLI and the apps.
