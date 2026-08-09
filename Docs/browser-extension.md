# Browser extension

Save the current page to your Stash instance from Firefox (including Zen, a
Firefox fork) or Chrome with one click. It lives in the top-level `Extension/`
folder and talks
directly to the backend over the public REST API ([`/api/v1/`](api.md)); there
are no backend, [StashKit](stashkit.md), or native-app changes behind it.

Clicking the toolbar button opens the full add-bookmark form, pre-filled with the
page's URL and title, with a "Fetch metadata" button, tag autocomplete, a "Read
later" checkbox, and a "Save" button.

## Prerequisites

- Firefox (or a Firefox fork such as Zen), or Chrome
- A running Stash instance you can sign in to, see
  [Running with Docker](backend-docker.md)
- Only for packaging the extension yourself: `zip`, `python3` (Pillow, for icons),
  and optionally `node`

## How it is built

A Manifest v3 WebExtension built from plain HTML, CSS, and vanilla JavaScript:
**no build step, no npm, no bundler**, the same philosophy as the Stash web UI.
The browser loads the files directly.

```
Extension/
├── manifest.json     WebExtension manifest v3
├── background.js     Background script: token storage, refresh, API calls
├── popup.html/.js/.css   Toolbar button popup (add-bookmark form)
├── options.html/.js/.css Settings page (server URL, sign in, 2FA)
├── icons/            Toolbar/store icons + the SVG master and generator
└── Makefile          lint / icons / package / clean
```

The manifest declares the background as **both** `service_worker` (used by
Chrome) **and** `scripts` (used by Firefox/Zen, which do not enable
`background.service_worker` by default), so one manifest serves both engines.

## Installation (development)

- **Firefox / Zen:** open `about:debugging` → **This Firefox** (or **This
  Zen**) → **Load Temporary Add-on…** → select `Extension/manifest.json`.
- **Chrome:** open `chrome://extensions` → enable **Developer mode** →
  **Load unpacked** → select the `Extension/` folder.

## First-time setup

1. Click the Stash icon in the toolbar.
2. Click **Open Settings**.
3. Enter your Stash server URL (e.g. `http://192.168.1.x:8080`), username, and
   password.
4. Click **Save & Sign In**. If your account has 2FA enabled, enter the code from
   your authenticator app (or a recovery code) when prompted.

The status line reads "Connected as _username_" once you are signed in.

## Usage

Navigate to any page, click the Stash icon, optionally click **Fetch metadata**
to pull the server-side title and description, add tags (with autocomplete from
your existing tags), check **Read later** if you want it to show up in Stash's
"To Read" view, and click **Save**. A confirmation appears with a link to view
the bookmark; it closes itself after a few seconds.

The URL field is read-only; the extension always saves the page you are on. If
the page is already saved, an inline "Already saved" message links to the existing
bookmark. There is no undo in the popup (its lifecycle is too short for a
timer-based undo); delete from the web UI or a native app if needed.

## Authentication

Credentials are exchanged for an access/refresh token pair via
`POST /api/v1/auth/login`; the tokens are stored in `chrome.storage.local`. The
background script decodes the access token's `exp` claim and silently refreshes
within 60 seconds of expiry (and once on any `401`), mirroring the CLI and iOS
app. The 2FA login branch (`/api/v1/auth/totp` and `/api/v1/auth/recovery`) is
handled inline on the settings page.

The background script is the single owner of token storage and API calls; the
popup and options pages never touch `chrome.storage` for tokens, communicating
with it over `chrome.runtime.sendMessage`.

`host_permissions: ["<all_urls>"]` is required: the server URL is user-supplied
and unknown at build time, so the extension must be allowed to call any host.

## Packaging

There is **no compile step**; "building" only means zipping the folder into a
store-ready package. A `Makefile` wraps the common tasks (run from `Extension/`):

```bash
cd Extension
make            # list targets
make lint       # validate (web-ext if installed, else manifest JSON + node --check)
make icons      # regenerate the PNG icons from icon.svg
make package    # build dist/stash-extension-<version>.zip
make clean      # remove dist/
```

The core targets need only `zip`, `python3`, and (optionally) `node`, no npm or
bundler. `make package` zips just the runtime files (the dev tooling and Makefile
are excluded).

CI mirrors this: `ci.yml` runs `make lint` on pushes and PRs that touch
non-documentation files, and `release.yml` runs `make package` on a `v*.*.*`
tag and attaches the zip to the GitHub Release (see
[Releasing a new version](releasing.md)).

## Icons

`Extension/icons/icon.svg` is the master vector (the Stash bookmark ribbon in deep
indigo, `#231468`). The four PNG sizes the manifest references are rendered by
`generate-icons.py` (Pillow only) in two treatments that match where each size is
shown: **16 and 32** (the toolbar action, `default_icon`) stay the deep-indigo
ribbon on a transparent background, legible on light and dark toolbars; **48 and
128** (the add-ons-manager / store display icons) wear the full app-icon look: a
white ribbon on an indigo rounded square, matching the native app and the web
favicon. Regenerate them rather than hand-editing the PNGs:

```bash
cd Extension/icons && python3 generate-icons.py
```

## Publishing

For personal use, sideloading via developer mode is sufficient. For distribution,
the packaged zip can be submitted to the
[Firefox Add-ons store](https://addons.mozilla.org) or the
[Chrome Web Store](https://chrome.google.com/webstore).
