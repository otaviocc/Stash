# Running via Docker Compose (published image)

For end users deploying Stash on a home server, NAS, or VPS. This is the recommended
way to run Stash.

## Prerequisites

- Docker Desktop (Mac/Windows), or Docker Engine + the Docker Compose plugin (Linux).

## Quick start

1. Download `docker-compose.yml` from the [latest release](https://github.com/otaviocc/stash/releases/latest).
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

## Data persistence

All data is stored in a named Docker volume (`stash_db`). It persists across container
restarts and updates. To back it up:

```bash
docker compose exec db pg_dump -U stash stash > backup.sql
```

## Environment variables reference

| Variable | Required | Description |
|----------|----------|-------------|
| `DB_PASSWORD` | Yes | PostgreSQL password |
| `JWT_SECRET` | Yes | JWT signing secret (minimum 32 characters, random) |
| `ADMIN_USERNAME` | Yes (first boot) | Admin account username |
| `ADMIN_PASSWORD` | Yes (first boot) | Admin account password (minimum 12 characters) |

`ADMIN_USERNAME` and `ADMIN_PASSWORD` are only used on first boot to create the admin
account. They are ignored on subsequent starts once the account exists.

## Adding HTTPS

Stash serves plain HTTP by default. To put it behind HTTPS, see
[Adding HTTPS with Caddy](backend-docker-caddy.md).
