# Stash PRD: Overview, Goals, Platforms & Architecture (§1\u20136)

_Part of the Stash Product Requirements Document. See [`PRODUCT.md`](../PRODUCT.md) for the index._

---

## 1. Overview

Stash is my self-hosted bookmark manager. Fully private, and multi-user.
Under the hood it's a Swift/Vapor REST API backed by Postgres, deployed via
Docker, with native clients for iOS, macOS, and the command line, all sharing a
Swift package (`StashKit`) for models and networking.

I built it around one non-negotiable: full data ownership. Self-hosted, no
third-party cloud, nothing about my bookmarks living on someone else's server.

---

## 2. Goals

What I wanted out of it:

- Save bookmarks quickly from any Apple platform via Share Extensions or the CLI
- Retrieve bookmarks reliably via keyword search, tag browsing, or recency
- Organize bookmarks with both flat and hierarchical tags
- Rename and delete tags across all bookmarks in bulk
- Save named queries as Smart Views that filter bookmarks by a set of AND conditions
- Auto-fetch page metadata (title, description, favicon) at save time, with
  manual override
- Support multiple users, each with a fully isolated bookmark collection
- Manage accounts myself as admin: create, suspend, and hard-delete, reset
  passwords and 2FA, via web dashboard and CLI
- Authenticate with username + password + TOTP-based 2FA, with recovery codes
- Let users enable, disable, and manage their own 2FA
- Let users change their own password
- Block duplicate URLs per user at save time
- Import bookmarks from Anybox JSON, Stash JSON, Netscape Bookmark File (HTML —
  every browser, plus Raindrop.io's and Pinboard's HTML exports), Raindrop.io
  CSV, or Pinboard JSON
- Export bookmarks in Stash native JSON, Anybox JSON, Netscape Bookmark File
  (HTML), Raindrop.io CSV, or Pinboard JSON format
- Export and import Smart Views as part of the Stash native JSON format
- Dark mode support (Light / Dark / Auto)
- Keep all data on infrastructure I control
- Stay fully private: no public sharing, no public registration

---

## 3. Non-Goals (v1)

Things I deliberately left out, at least for now:

- Public or open registration
- Cross-user bookmark visibility or sharing
- Page content archiving (saving article text/HTML for offline reading), distinct
  from the native apps' offline access to their own bookmark data, which is supported
- Public or shared collections
- Read-later / queue functionality
- SSO or OAuth
- Menu bar app (macOS)

---

## 4. User Roles

| Role | Description |
|------|-------------|
| **Admin** | The primary user. Can manage all accounts, reset any user's 2FA. Has their own bookmark collection like any other user. |
| **User** | A regular account created by the admin. Can manage their own bookmarks, change their own password, and manage their own 2FA. Cannot see other users' data. |

There's exactly one admin, in practice. The account is seeded at first
boot from environment variables; there's no public sign-up flow.

---

## 5. Platforms

What's actually built, versus what's still on the list:

| Platform | Type | Status |
|----------|------|--------|
| Backend | Vapor 4 REST API | ✅ Complete |
| Web admin dashboard | Server-rendered (Leaf) | ✅ Complete |
| Web frontend (user-facing) | Server-rendered (Leaf) | ✅ Complete |
| CLI (`stash`) | Swift CLI tool | ✅ Complete |
| iOS | Native SwiftUI app + Share Extension | ✅ Complete (M8 + M9) |
| macOS | Native SwiftUI app + Share Extension | ✅ Complete (M10) |
| Browser extension | WebExtension (Firefox + Chrome/Zen) | ✅ Complete |

---

## 6. Architecture

Here's how the pieces fit together:

```
┌───────────────────────────────────────────────────────┐
│                       Clients                         │
│  iOS App   macOS App   CLI   Web Dashboard   Web App  │
└──────────────────────────┬────────────────────────────┘
                           │ HTTPS / REST
                           ▼
┌───────────────────────────────────────────────────────┐
│              Stash Backend (Vapor 4)                  │
│                                                       │
│  Auth Middleware (JWT access token)                   │
│  Role Middleware (admin / user)                       │
│  Routes → Controllers → Fluent ORM                   │
│  Metadata Fetcher (async, non-blocking)               │
│  ImportExportRegistry (pluggable importers/exporters) │
│  TagRenamer / TagDeleter (shared business logic)      │
└──────────────────────────┬────────────────────────────┘
                           │
                           ▼
┌───────────────────────────────────────────────────────┐
│                  PostgreSQL 16                        │
└───────────────────────────────────────────────────────┘

StashKit (Swift Package) — ✅ Complete (M6)
  └── Shared by: iOS app, macOS app, CLI
  └── DTOs, request factories, thin StashClient
```

---
