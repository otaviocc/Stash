# Running the backend locally (no Docker)

For developers who want to run the backend directly against a local PostgreSQL instance.

## Prerequisites

- Swift 6.2+ (ships with Xcode 26)
- PostgreSQL 16 running locally

To build the backend from source first, see [Building the backend](backend-build.md).

## Environment setup

```bash
cd stash/Backend
export DATABASE_URL=postgres://stash:yourpassword@localhost:5432/stash
export JWT_SECRET=your-random-32-char-secret
export ADMIN_USERNAME=admin
export ADMIN_PASSWORD=yourpassword
```

## Create the database

```bash
createdb stash
createuser stash
psql -c "ALTER USER stash WITH PASSWORD 'yourpassword';"
psql -c "GRANT ALL PRIVILEGES ON DATABASE stash TO stash;"
```

## Run

```bash
swift run App serve
```

The server starts at `http://localhost:8080`.

- Web frontend: `http://localhost:8080/app`
- Admin dashboard: `http://localhost:8080/admin`
- API: `http://localhost:8080/api/v1/`

On first boot, the admin account is created automatically from `ADMIN_USERNAME` and
`ADMIN_PASSWORD`, and database migrations run automatically. Once the admin account
exists, those two variables are ignored on subsequent starts.
