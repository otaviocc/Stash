# Releasing a new backend version

Publishing a new Docker image is driven entirely by **pushing a version tag**.
The `.github/workflows/release.yml` workflow does the rest: it tests the
backend, builds a multi-arch image, pushes it to `ghcr.io/otaviocc/stash`, and
cuts a GitHub Release with `docker-compose.yml` attached.

## One-time setup (first release only)

The image package on GitHub Container Registry starts **private**, and there is
no API to flip it from CI (GitHub only exposes visibility as a manual setting).
So, exactly once:

1. Merge the workflows to `main` and push your first tag (see below) so the
   image is created.
2. Go to **GitHub → your profile → Packages → `stash` → Package settings →
   Danger Zone → Change visibility → Public.**

This sticks permanently; every later push to the same package stays public, so
you never repeat this step.

## Cutting a release

First, bump the version numbers and commit them — `Backend/VERSION` is what
ends up baked into the Docker image (`AppVersion.read`), so it has to match
the tag you're about to push:

```sh
git checkout main
git pull

Script/bump-version.sh --backend 1.1.0 --app 1.1
git add Backend/VERSION Extension/manifest.json StashApp/Stash.xcodeproj/project.pbxproj
git commit -m "Bump version to 1.1.0"
git push
```

This also bumps the iOS/macOS `MARKETING_VERSION` (all four build configs)
and the browser extension's `manifest.json`, so the three components stay in
lockstep. It does **not** touch the Xcode build number
(`CURRENT_PROJECT_VERSION`) — bump that separately if needed.

Then tag and push:

```sh
# Tag must match v*.*.*: three dot-separated parts, leading "v".
git tag -a v1.1.0 -m "Stash 1.1.0"
git push origin v1.1.0
```

Pushing the tag triggers `release.yml`:

1. **`test`**: runs the backend suite serially (`swift test --no-parallel`,
   in-memory SQLite, no database needed; parallel runs starve the SQLite
   connection pool on a CI runner). Publishing is gated on this passing.
2. **`publish`** (only if `test` passes): builds the image for `linux/amd64` +
   `linux/arm64`, pushes `ghcr.io/otaviocc/stash:latest` and
   `ghcr.io/otaviocc/stash:<version>` (e.g. `1.0.0`), and creates a GitHub Release
   named `Stash v1.0.0` with `Backend/docker-compose.yml` attached.

No secrets to configure: the workflow's built-in `GITHUB_TOKEN` covers GHCR
login, the push, and the release.

## Rules and gotchas

- **The tag is the only trigger.** Pushing commits/branches to `main` runs CI
  (build + test) but never builds or publishes an image.
- **Tag format matters.** `v1.0.0` ✅. `v1.2` ❌ (doesn't match `v*.*.*`, won't
  trigger). `1.0.0` ❌ (no `v`). Pre-release suffixes like `v1.0.0-beta` do
  trigger and yield the version `1.0.0-beta`.
- **A pre-release tag never shows up as an available update.** The admin
  dashboard's update checker (`/admin/health`, see `Docs/backend-docker.md`)
  requires a clean `major.minor.patch` on both sides of the comparison and
  treats anything else, including a `-beta`/`-rc` qualified tag, as
  unparseable — deliberately, so a qualified tag can't be silently truncated
  and misread as equal to a real release. This is intentional: a pre-release
  is meant for the people who already know to go looking for it, not to be
  pushed as a notification to every self-hosted instance.
- **`latest` follows the newest tag**: every release re-tags `latest` at the
  new version.
- **The first release is slow.** The `linux/arm64` leg builds under QEMU
  emulation with a cold layer cache; expect it to take a while. Later releases
  reuse the cached Swift dependency layers (`type=gha`) and are faster, though
  they still recompile changed backend source under emulation.
- **Watch the first run**: it's also the first time the backend test suite runs
  on Linux. Fix any surprises there before relying on the pipeline.

## Verifying a release

```sh
docker pull ghcr.io/otaviocc/stash:1.0.0
```

Then check the GitHub Releases page for the new release and its attached
`docker-compose.yml`. To deploy the published image, see [Running with
Docker](backend-docker.md).
