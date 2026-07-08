# Stash

A self-hosted bookmark manager with native iOS, macOS, web, and browser-extension clients.

![CI](https://github.com/otaviocc/stash/actions/workflows/ci.yml/badge.svg)

<img width="1348" height="928" alt="Landing" src="https://github.com/user-attachments/assets/dc0e591f-2476-4f86-a3ff-288517eeeba1" />

<img width="1348" height="928" alt="Bookmarks" src="https://github.com/user-attachments/assets/f595a3aa-4a17-4575-a274-34e2a74bcf19" />

## Features

- Save bookmarks from iOS, macOS, Safari Share Extension, CLI, the web UI, or a
  Firefox/Chrome browser extension
- Hierarchical tags, full-text search, bulk tag rename and delete
- Import from Anybox JSON; export to Stash JSON
- Multi-user with per-user 2FA (TOTP) and recovery codes
- Admin dashboard for user management
- Dark mode (Light / Dark / Auto)
- Self-hosted, fully private: your data stays on your infrastructure

## Quick start

1. Download
   [`docker-compose.yml`](https://github.com/otaviocc/stash/releases/latest)
2. Create a `.env` file. See [Running with Docker](Docs/backend-docker.md) for
   the full guide
3. `docker compose up -d`
4. Open `http://localhost:8080/app`

## Documentation

| Guide | Description |
|-------|-------------|
| [Building the backend](Docs/backend-build.md) | Build from source, run tests |
| [Running locally](Docs/backend-local.md) | Swift + PostgreSQL, no Docker |
| [Running with Docker](Docs/backend-docker.md) | Published image, recommended for most users |
| [Adding HTTPS with Caddy](Docs/backend-docker-caddy.md) | Local network or internet-exposed |
| [Releasing a new version](Docs/releasing.md) | Tag, build, and publish the backend image |
| [Configuration reference](Docs/configuration.md) | Environment variables and per-component config |
| [API and routes reference](Docs/api.md) | REST API, admin dashboard, and web frontend |
| [OpenAPI specification](Docs/api-openapi.md) | Machine-readable API spec + Swagger UI (`/docs.html`) |
| [Building and using the CLI](Docs/cli-build.md) | `stash` command-line tool |
| [Building the mobile apps](Docs/mobile-build.md) | iOS and macOS apps from source |
| [StashKit](Docs/stashkit.md) | Shared Swift package (DTOs, request factories, client) |
| [Browser extension](Docs/browser-extension.md) | Firefox/Chrome extension: install, usage, packaging |

## Clients

- **Web**: built in, available at `/app` on your server
- **iOS**: native SwiftUI app (build from source)
- **macOS**: native SwiftUI app (build from source)
- **CLI**: `stash` command-line tool (build from source)
- **Browser extension**: Firefox & Chrome (including Zen); saves the current
  page (see [Browser extension](Docs/browser-extension.md))

## License

Stash uses a split license: the server (`Backend`) is [AGPL-3.0-only](Backend/LICENSE), so anyone
running a modified Stash server as a network service must share their changes. Everything else
(`StashKit`, `CLI`, `StashApp`, the browser `Extension`, and `StashSkill`) is available under the
[MIT license](LICENSE).
