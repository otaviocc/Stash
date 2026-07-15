# Stash PRD: Deployment (§18)

_Part of the Stash Product Requirements Document. See [`PRODUCT.md`](../PRODUCT.md) for the index._

---

## 18. Deployment

### Distribution

Docker image at `ghcr.io/otaviocc/stash`. Single `docker-compose.yml`, no build
step required.

### Image

- **Build:** `swift:6.1-jammy` → `ubuntu:22.04` runtime
- **Platforms:** `linux/amd64`, `linux/arm64`
- **Tags:** `latest`, semver

### Canonical `docker-compose.yml`

```yaml
services:
  app:
    image: ghcr.io/otaviocc/stash:latest
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=postgres://stash:${DB_PASSWORD}@db:5432/stash
      - JWT_SECRET=${JWT_SECRET}
      - ADMIN_USERNAME=${ADMIN_USERNAME}
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
    depends_on:
      - db
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    volumes:
      - stash_db:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=stash
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=stash
    restart: unless-stopped

volumes:
  stash_db:
```

### First Boot

Reads `ADMIN_USERNAME` / `ADMIN_PASSWORD` from env, creates admin if no users
exist. Missing/invalid → logs critical error, exits. Subsequent boots: silent
no-op. Migrations auto-run on boot (idempotent).

### Local Network

Primary use case: `http://192.168.1.x:8080`. No domain or TLS required.
In-memory sessions don't survive a container restart.

### External Access (optional)

```
stash.yourdomain.com {
    reverse_proxy localhost:8080
}
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `DB_PASSWORD` | PostgreSQL password |
| `JWT_SECRET` | JWT signing secret (min 32 chars) |
| `ADMIN_USERNAME` | Admin username (first boot only) |
| `ADMIN_PASSWORD` | Admin password (first boot only, min 12 chars) |

### CI/CD ✅ Complete (M4.1)

Two GitHub Actions workflows. `ci.yml` runs on every push to `main` and every
pull request, builds and tests all components, no image. `release.yml` runs on
a `v*.*.*` tag: re-runs the backend tests, then builds `linux/amd64` and
`linux/arm64` natively on separate GitHub-hosted runners. I originally
cross-compiled the arm64 build under QEMU, but the emulation crashed the Swift
compiler partway through, so both architectures now build natively instead (see
`DECISIONS.md`). Each arch is pushed by digest, then stitched into one
multi-arch manifest via `docker buildx imagetools create` → tags
`ghcr.io/otaviocc/stash` (`latest` + semver) → creates a GitHub Release with
`docker-compose.yml` attached. `GITHUB_TOKEN` only, no extra secrets. The repo
stays private; the image is made public via a one-time manual setting in the
package settings (there's no API to do it from CI).

---
