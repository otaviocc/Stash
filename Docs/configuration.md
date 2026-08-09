# Configuration reference

A single reference for configuring every Stash component: the backend, the CLI,
and the apps.

## Backend

The backend reads all of its configuration from environment variables. There are
no config files.

### Docker Compose

The published `docker-compose.yml` reads variables from a `.env` file in the
same directory and injects them into the containers. The compose file
interpolates `DB_PASSWORD` into the database container and into the app's
`DATABASE_URL`.

```bash
# .env
DB_PASSWORD=choose-a-strong-password
JWT_SECRET=choose-a-random-32-character-string
ADMIN_USERNAME=admin
ADMIN_PASSWORD=choose-a-strong-password
```

| Variable | Required | Description |
|----------|----------|-------------|
| `DB_PASSWORD` | Yes | PostgreSQL password, used both to initialize the `db` container and (interpolated into `DATABASE_URL`) by the `app` container |
| `JWT_SECRET` | Yes | JWT signing secret; must be non-empty, use a random value of at least 32 characters (`openssl rand -base64 48`) |
| `ADMIN_USERNAME` | Yes (first boot) | Admin account username |
| `ADMIN_PASSWORD` | Yes (first boot) | Admin account password, minimum 12 characters |

### Running without Docker

When running the server directly (`swift run App serve`), set `DATABASE_URL`
itself rather than `DB_PASSWORD`:

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | Full PostgreSQL URL, e.g. `postgres://stash:password@localhost:5432/stash` |
| `JWT_SECRET` | Yes | JWT signing secret; must be non-empty, use a random value of at least 32 characters |
| `ADMIN_USERNAME` | Yes (first boot) | Admin account username |
| `ADMIN_PASSWORD` | Yes (first boot) | Admin account password, minimum 12 characters |

See [Running locally](backend-local.md) for the full local setup.

### First-boot behavior

On first boot, if the database has no users, the app creates the admin account
from `ADMIN_USERNAME` / `ADMIN_PASSWORD`. If those are missing it logs an error
and exits rather than starting a login-less instance. Once an admin exists, the
two admin variables are ignored on subsequent boots. Database migrations run
automatically on every boot.

## CLI

The CLI stores its configuration and tokens in `~/.config/stash/config.json`:

```bash
stash config set-url http://localhost:8080
stash login                # prompts for credentials (and TOTP if enabled)
```

Tokens are written to that file and refreshed automatically before each
authenticated command. See [Building and using the CLI](cli-build.md) for the
full command list.

## Apps (iOS / macOS)

The apps have no build-time configuration for the server. On first launch the
app shows a setup screen: enter your Stash server URL (e.g.
`http://192.168.1.x:8080`) and sign in with an account created by the admin.

The main app and the Share Extension share the server URL (via the App Group's
`UserDefaults` suite) and the access/refresh tokens (via a Keychain access
group), through the App Group `group.$(STASH_BUNDLE_PREFIX).stash` (the bundle
prefix comes from `StashApp/Config/Stash.xcconfig`, so the App Group id follows
whatever account you build under). For plain HTTP on a local network,
`NSAllowsArbitraryLoads` is already set to `true` in the app's `Info.plist`.
See [Building the mobile apps](mobile-build.md).
