# Stash

A self-hosted bookmark manager with native iOS, macOS, and web clients.

![CI](https://github.com/otaviocc/stash/actions/workflows/ci.yml/badge.svg)

## Features

- Save bookmarks from iOS, macOS, Safari Share Extension, CLI, or web browser
- Hierarchical tags, full-text search, bulk tag rename and delete
- Import from Anybox JSON; export to Stash JSON
- Multi-user with per-user 2FA (TOTP) and recovery codes
- Admin dashboard for user management
- Dark mode (Light / Dark / Auto)
- Web Archive integration (Wayback Machine)
- Self-hosted, fully private — your data stays on your infrastructure

## Quick start

1. Download [`docker-compose.yml`](https://github.com/otaviocc/stash/releases/latest)
2. Create a `.env` file — see [Running with Docker](Docs/backend-docker.md) for the full guide
3. `docker compose up -d`
4. Open `http://localhost:8080/app`

## Documentation

| Guide | Description |
|-------|-------------|
| [Building the backend](Docs/backend-build.md) | Build from source, run tests |
| [Running locally](Docs/backend-local.md) | Swift + PostgreSQL, no Docker |
| [Running with Docker](Docs/backend-docker.md) | Published image, recommended for most users |
| [Adding HTTPS with Caddy](Docs/backend-docker-caddy.md) | Local network or internet-exposed |
| [Configuration reference](Docs/configuration.md) | Environment variables and per-component config |
| [API and routes reference](Docs/api.md) | REST API, admin dashboard, and web frontend |
| [Building and using the CLI](Docs/cli-build.md) | `stash` command-line tool |
| [Building the mobile apps](Docs/mobile-build.md) | iOS and macOS apps from source |
| [StashKit](Docs/stashkit.md) | Shared Swift package (DTOs, request factories, client) |

## Clients

- **Web** — built in, available at `/app` on your server
- **iOS** — native SwiftUI app (build from source)
- **macOS** — native SwiftUI app (build from source)
- **CLI** — `stash` command-line tool (build from source)
