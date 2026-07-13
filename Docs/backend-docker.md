# Running via Docker Compose (published image)

For end users deploying Stash on a home server, NAS, or VPS. This is the
recommended way to run Stash.

## Prerequisites

- Docker Desktop (Mac/Windows), or Docker Engine + the Docker Compose plugin
  (Linux), or [Podman](https://podman.io) 4+ (see [Running with
  Podman](#running-with-podman) below).

## Quick start

1. Download `docker-compose.yml` from the [latest
   release](https://github.com/otaviocc/stash/releases/latest).
2. Create a `.env` file next to it:

   ```bash
   # .env
   DB_PASSWORD=choose-a-strong-password
   JWT_SECRET=choose-a-random-32-character-string
   ADMIN_USERNAME=admin
   ADMIN_PASSWORD=choose-a-strong-password
   ```

3. Start:

   ```bash
   docker compose up -d
   ```

4. Open `http://localhost:8080/app` in your browser and sign in.

## Accessing from other devices on your network

Replace `localhost` with your server's local IP address or hostname, e.g.
`http://192.168.1.x:8080/app`.

## Useful commands

```bash
docker compose ps                            # Check status
docker compose logs -f app                   # Tail logs
docker compose down                          # Stop
docker compose pull && docker compose up -d  # Update to latest image
```

## Running with Podman

[Podman](https://podman.io) is a daemonless, rootless-capable drop-in for Docker
and runs Stash unchanged, using the same `docker-compose.yml` and the same published image. Pick
either approach:

- **Use `podman compose`**: Podman delegates to an installed Compose provider
  (the `docker-compose` plugin or `podman-compose`). Replace `docker` with
  `podman` in the commands above, e.g. `podman compose up -d`.
- **Keep the `docker` commands**: install the standalone Docker CLI + Compose
  plugin (no Docker Desktop needed) and point them at Podman's socket with
  `DOCKER_HOST`. Every `docker compose …` command above, including the
  [Caddy HTTPS](backend-docker-caddy.md) variants, then works verbatim.

On **Linux**, Podman runs containers natively; there is nothing else to set up.
On **macOS and Windows**, Podman runs them inside a managed VM that you start
once and again after each reboot (there is no always-on background app like
Docker Desktop):

```bash
podman machine init    # one time
podman machine start   # and after each reboot
```

Rootless Podman can publish the default `8080` port with no extra privileges.

## Local development (build from source)

For working on the backend itself, the repository's `Backend/` directory ships a
`docker-compose.override.yml` that Compose merges automatically when you run
commands from that directory. It switches the `app` service from the published
image to a build of your local working tree:

```yaml
services:
  app:
    image: stash-local
    build: .
```

So from `Backend/`, `docker compose up -d --build` builds the image from your
checkout (the `Dockerfile` plus current sources) instead of pulling
`ghcr.io/otaviocc/stash:latest`, while still starting the same PostgreSQL
service. Re-run with `--build` to pick up source changes. The `Backend/Makefile`
wraps this: `make build-up` rebuilds and restarts the stack, and `make up`,
`make down`, `make logs`, and `make migrate` cover day-to-day use. This works the
same under Podman.

## Checking for updates

The admin dashboard (`/admin`) and its Health page (`/admin/health`) check
GitHub Releases once a day for a newer Stash version than the one currently
running, and show a banner plus an "Updates" card with the release notes link
when one is available. Stash can't update itself from inside the container —
upgrading is still the same command as above:

```bash
docker compose pull && docker compose up -d
```

Update checking is on by default and can be turned off from the Health page
(useful for an air-gapped or fully offline instance) — see PRODUCT.md §12.

## Data persistence

All data is stored in a named Docker volume (`stash_db`). It persists across
container restarts and updates. To back it up:

```bash
docker compose exec db pg_dump -U stash stash > backup.sql
```

Stash also has its own **application-level** instance backup, independent of
`pg_dump`: `/admin/backup` downloads a single JSON file with every account
(including password hashes and 2FA secrets, so restoring keeps everyone's
logins working), their bookmarks and Smart Views, and the site's appearance
settings. Restoring merges by username into the running instance — an
existing account's bookmarks/Smart Views are merged in, a new username is
created with its backed-up password and 2FA intact, and nothing is ever
deleted. This is the easiest way to migrate an instance to a new server
without touching Postgres directly. Because the file carries password hashes
and TOTP secrets, treat it like a database dump — store it somewhere private.

## Environment variables reference

| Variable | Required | Description |
|----------|----------|-------------|
| `DB_PASSWORD` | Yes | PostgreSQL password |
| `JWT_SECRET` | Yes | JWT signing secret (minimum 32 characters, random) |
| `ADMIN_USERNAME` | Yes (first boot) | Admin account username |
| `ADMIN_PASSWORD` | Yes (first boot) | Admin account password (minimum 12 characters) |

`ADMIN_USERNAME` and `ADMIN_PASSWORD` are only used on first boot to create the
admin account. They are ignored on subsequent starts once the account exists.

## Adding HTTPS

Stash serves plain HTTP by default. To put it behind HTTPS, see [Adding HTTPS
with Caddy](backend-docker-caddy.md).
