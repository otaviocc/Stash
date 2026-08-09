# Stash: Product Requirements Document

**Document revision:** 1.9 (tracks edits to this spec, not the shipped product
version in `Backend/VERSION`)
**Status:** Living Document
**Author:** Otávio

Stash is my self-hosted bookmark manager: fully private, multi-user. A
Swift/Vapor REST API backed by Postgres, deployed via Docker, with native
iOS/macOS/CLI clients sharing a `StashKit` Swift package, a server-rendered web
UI, and a browser extension. Built around one non-negotiable: full data
ownership.

This file is an **index**. The PRD itself is split into topical files under
[`Docs/`](Docs/) so each part stays small and an LLM can load only what it
needs. Section numbers (§n) are preserved. The companion [`DECISIONS.md`](DECISIONS.md)
records *why* things were built the way they are; endpoint/behavior reference
lives in [`Docs/api.md`](Docs/api.md).

## Where to find each part

| File | Sections | Contents |
|------|----------|----------|
| [`Docs/product-overview.md`](Docs/product-overview.md) | §1–6 | Overview, goals, non-goals, user roles (admin/user), platforms table, architecture diagram |
| [`Docs/product-data-model.md`](Docs/product-data-model.md) | §7 | Every model: User, Bookmark (incl. Internet Archive/Wayback fields), Refresh Token, Recovery Code, Tags (normalization + `tagsSearch`), Site Settings (accent themes, footer links), Smart View (conditions, match modes), Favicon Cache, Audit Log |
| [`Docs/product-auth.md`](Docs/product-auth.md) | §8 | Token strategy (JWT access + opaque refresh), login/2FA/recovery flows, 2FA enroll/disable/reset, password rules, token invalidation |
| [`Docs/product-api.md`](Docs/product-api.md) | §9–11 | Full `/api/v1/` endpoint tables (auth, user, bookmarks incl. offline-sync `changes`/`deleted`, tags, smart-views, metadata, admin, favicons), metadata fetching, import/export (Anybox + Stash JSON, pluggable registry) |
| [`Docs/product-web.md`](Docs/product-web.md) | §12–13 | Web admin dashboard (`/admin`: pages, business rules, dashboard hub, all admin tools) and web frontend (`/app`: bookmark list/detail, tag sidebar, Smart Views, settings, dark mode) |
| [`Docs/product-clients.md`](Docs/product-clients.md) | §14–17B | CLI (`stash` commands), StashKit (three-layer package), iOS app (offline sync, navigation, views, in-app browser), macOS app, browser extension |
| [`Docs/product-deployment.md`](Docs/product-deployment.md) | §18 | Docker distribution, image build, canonical `docker-compose.yml`, first-boot seeding, env vars, CI/CD |
| [`Docs/product-technical.md`](Docs/product-technical.md) | §19–22 | Repository structure, package dependencies, error format, pagination, testing policy, code style, milestones table, Leaf gotchas, out-of-scope |

## Quick pointers (things agents look for)

- **Tag semantics** (`swift` matches `swift` and `swift/*`, not `swiftui`; the
  `tagsSearch` pipe-wrapped column): [`product-data-model.md`](Docs/product-data-model.md) §7.5.
- **Error envelope + error codes** (`{ error, code, message }`, `duplicate_url`
  carries `existingID`): [`product-technical.md`](Docs/product-technical.md) §19.4.
- **Testing policy** (in-memory SQLite; no app unit tests by design; Given/When/Then):
  [`product-technical.md`](Docs/product-technical.md) §19.6.
- **The two web session cookies** (`stash_admin_session` vs `stash_session`):
  [`product-web.md`](Docs/product-web.md) §12–13.
- **Internet Archive / Wayback** submission model and gating:
  [`product-data-model.md`](Docs/product-data-model.md) §7.2, [`product-web.md`](Docs/product-web.md) §12.
- **Offline-sync endpoints** (`/bookmarks/changes`, `/bookmarks/deleted`):
  [`product-api.md`](Docs/product-api.md) §9.3.
