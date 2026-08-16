# Stash Decisions: Deployment, CI/CD, HTTPS & Licensing

_Part of the Stash Decision Log. See [`DECISIONS.md`](../DECISIONS.md) for the index and the full list of topical files. Entries are in original chronological order within this file._

---

## M4: Docker & deployment

The Docker image is multi-stage and jammy-matched: it builds on
`swift:*-jammy` and runs on `ubuntu:22.04`, so the build glibc/ABI actually
matches the runtime. The static Swift stdlib plus jemalloc ship in the
runtime image; nothing else does, just the binary and the libraries it
needs. It's arch-agnostic, so `buildx` produces both `linux/amd64` and
`linux/arm64` from the same Dockerfile. (The build base started on
`swift:5.10-jammy` and was later bumped to `swift:6.1-jammy`.)

First-boot admin seeding lives in `configure.swift` (`AdminSeeder`, running
after migrations): it seeds the admin from `ADMIN_USERNAME`/`ADMIN_PASSWORD`
only when the database has no users yet, throws and exits if those
credentials are missing or invalid (I didn't want a login-less instance to
ever start), and is a silent no-op on every boot after that. It never runs
against the test database.

Migrations auto-run on boot in every environment, so the canonical
`docker compose up -d` needs zero manual steps: Fluent tracks which
migrations have already applied, so re-running on every boot is safe and
idempotent.

`.env.example` is Docker-oriented: it documents the four variables from §16
(`DB_PASSWORD`, `JWT_SECRET`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`), and Compose
interpolates the full `DATABASE_URL` from `DB_PASSWORD`. A local, non-Docker
run exports `DATABASE_URL` directly instead.

---

## M4.1: CI/CD pipeline & Docker image publishing

Two workflows, split by trigger and cost. `ci.yml` runs on every push to
`main` and every pull request, building and testing every component but
publishing nothing, so it stays a cheap regression gate. `release.yml` runs
only on a `v*.*.*` tag push: it re-runs the backend tests and, only if
those pass, builds and publishes the Docker image. Keeping image publishing
tag-only means routine pushes never pay for the multi-arch build.

Getting the backend test job right in CI took a couple of iterations. I
first built and tested it with `-c release`, to validate the shipping
configuration in one pass, but that crashed the Swift 6.2.1 compiler in
CI: its SIL optimizer, which only runs under release optimization, hit a
fatal error compiling the Vapor dependency tree. A regression gate doesn't
actually need release optimization (the Docker image build validates that
separately, on Swift 6.1), so the backend now just runs `swift test` in
plain debug, which sidesteps the crashing optimizer entirely. Then I found
the tests needed to run serially: swift-testing parallelizes by default, and
each test boots its own `Application` and hashes passwords at bcrypt cost
12 on purpose (slow), which starved the SQLite connection pool on a CI
runner: six of seventy-six tests failed with connection timeouts, no logic
failures, just contention. Running with `--no-parallel` removes that
contention entirely; the trade-off is a slower CI run, which is fine for a
gate. This never showed up locally on a fast multi-core Mac, which is why
it only surfaced in CI.

Docker builds use GitHub's layer cache in `mode=max`, so the expensive Swift
package-resolution and compilation layers are reused between runs, which
makes subsequent tagged releases substantially faster.

Making the published image public turned into a small research detour. The
original plan was to `curl PATCH` the image to public visibility from CI,
but that doesn't actually work: there's no REST endpoint for container
package visibility at all (the Packages API only exposes
get/delete/restore; visibility is a web-UI-only setting), and even if there
were, `GITHUB_TOKEN` is a bot installation token that can't call the
user-scoped API anyway. Worse, a bare `curl` without `--fail` would have
swallowed the 404 silently and left the job green, a no-op nobody would
notice. I removed the step and replaced it with a one-time manual
instruction instead: flip the package to public by hand once, after the
first push, and it stays public for every push after that. The source
repository itself stays private; only the image is public. Everything that
*is* automated (the GHCR login, the multi-arch push, the release
creation) authenticates with the workflow's own `GITHUB_TOKEN`, no personal
access token needed.

The release itself attaches the canonical `docker-compose.yml` to a GitHub
Release, so someone can grab just that file and run `docker compose up -d`
against the published image with no clone and no build.

`ci.yml` is split into a Linux `backend` job, a Linux `linux-cli` job, and a
macOS `apple` job. StashKit and the CLI depend on `MicroClient`, which through
0.0.27 used Apple Foundation's networking types with no shim for Linux, so
they didn't compile there; MicroClient 0.0.28 added the
`#if canImport(FoundationNetworking)` shim, and StashKit picked up the same
shim in `StashClient.swift` and its test double, so both now build and test
natively on `ubuntu-latest`. The `apple` job still has to run on macOS,
covering the app plus Share Extension for both iOS and macOS on one runner
(macOS runner minutes bill at roughly 10× on a private repo, so I didn't want
to fan this out further); it also rebuilds StashKit and the CLI there as an
Apple-platform regression check alongside the Linux build. The app itself has
no test target by design, so CI build-verifies it on both platforms rather
than unit-testing it: enough to catch compile-level regressions across the
cross-platform `#if` shells, which is the actual risk for a target with no
tests. The CLI is still not shipped as a Linux binary — only compiled and
tested — since `release.yml` doesn't publish a CLI artifact for any platform.

---

## HTTPS / Caddy

HTTPS is an optional Caddy sidecar, not something built into the image
itself: Stash serves plain HTTP internally, and TLS termination is a
deployment concern, the same pattern other self-hosted tools like Navidrome
use. That keeps the app simple and doesn't force HTTPS complexity on anyone
who doesn't need it. Caddy is documented as an opt-in addition to the
compose file, covering both a local-network case (self-signed, with
root-CA trust instructions per platform) and an internet-exposed case
(automatic Let's Encrypt); no changes needed to the Stash image or the
Vapor backend itself.

---

## Documentation: Podman runtime & local-dev compose override

Two documentation-only additions. First, Podman is now documented as a
supported alternative to Docker for running Stash, since it's API-compatible
enough that the published image and the committed compose file work
completely unchanged: the only difference is at the operator's own
machine, pointing tooling at Podman's socket instead of Docker's, so nothing
in the repo itself needed to change to support it. Second, the local-dev
workflow for building from source (rather than the published image), which
previously only lived in the Makefile and in my own dev-environment
notes, finally got written up properly in the user-facing docs, so a
contributor doesn't have to reverse-engineer it from the Makefile alone.

## Open-sourcing prep: footer GitHub link, scrubbed identifiers, OSS scaffolding

A few small things done specifically in preparation for eventually making
this repository public. The footer gained a GitHub link alongside the
existing Mastodon and Ko-fi ones. My real Apple Developer Team ID and my
personal legacy bundle prefix, both of which had been hardcoded throughout
committed config, docs, and source, were replaced everywhere with
placeholder values, matching the same placeholder pattern already used for
the machine-local xcconfig override, deliberately leaving the historical
prose in this very document describing what was actually built under the
old identifiers untouched, since it's an accurate record of what happened
at the time, not something that needs to match today's placeholders. And
the repository picked up the standard scaffolding an open-source project is
expected to have: a license, a contributing guide, a code of conduct, a
security policy, and issue/PR templates, even though the repository itself
stays private for now. This is preparation, not a visibility change yet.

## License: split MIT into AGPLv3 (Backend) and MIT (everything else)

The MIT license added just one commit earlier covered the whole monorepo,
but MIT does nothing to stop someone from taking the server, running it as
a hosted service with modifications, and never sharing those changes back,
the same "SaaS loophole" that Immich, Nextcloud, Mastodon, and Grafana all
close by licensing their server under AGPLv3 instead. I'm the sole
copyright holder, so relicensing needed no one else's sign-off, and I split
the license along the same server/client boundary that already exists in
the repo: `Backend` moved to AGPL-3.0-only, while `StashKit`, `CLI`,
`StashApp`, `Extension`, and `StashSkill` stayed MIT. `StashApp` staying
MIT specifically rules out an App Store conflict: Apple's terms are
incompatible with (A)GPL, and I want the door open to the App Store later.
`StashKit` staying MIT rather than following `Backend` into AGPL was the
one non-obvious call: `Backend` links it, and combining permissive code
into an AGPL work is allowed, so the combined Backend distribution is still
governed by AGPL while `StashKit`'s own source, and every client that
links it, stays copyleft-free.

The per-file header changed shape at the same time, from the full MIT text
pasted into every source file to a two-line SPDX identifier
(`SPDX-License-Identifier: AGPL-3.0-only` or `MIT`, per component). That
header lives in one place per component: the `--header` line in each
`.swiftformat`, so the four config edits regenerated all ~230 file headers
in one SwiftFormat pass rather than needing a hand edit per file. `Backend`
also gained its own `LICENSE` file with the full AGPLv3 text alongside the
root MIT `LICENSE`, and `StashSkill` got a copy of the MIT `LICENSE` too,
since it's meant to be copied standalone into someone's `.claude/skills`
directory and shouldn't rely on the rest of the repo being present to stay
license-compliant.

---

## Docker compose: explicit project name and container names

Added `name: stash` at the top level of `docker-compose.yml` and explicit
`container_name` fields on both services (`stash_server`, `stash_db`).
Without these, Docker derives the project name from the directory the compose
file is run from, which means the container names vary per host: a NAS panel
or `docker ps` might show `stash_app_1`, `compose_app_1`, or something else
entirely depending on where the operator placed the file. Pinning the names
makes every deployment look the same — `stash_server` and `stash_db` — so
they're instantly identifiable in any container panel without guessing. The
pattern follows what Immich does with its `immich_server`, `immich_redis`,
`immich_postgres` names. The database hostname in `DATABASE_URL` was updated
from `db` to `stash_db` to match, since Docker uses the service name (not
the container name) for DNS inside the compose network, and the service was
renamed from `db` to `stash_db`.
