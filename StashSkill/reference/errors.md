# `stash` CLI error messages

Reference companion to the `stash-cli` skill; read on demand for the full table of error messages and their remedies.

## 7. Error handling

Every failure prints a single `Error: <message>` line to **stderr** and exits
non-zero. These are the **actual** messages emitted by the CLI (note they are
human-readable sentences, not the API's snake_case codes). When you see one,
take the matching action.

| stderr message | Meaning | Remedy |
|---|---|---|
| `No server URL configured. Run: stash config set-url <url>` | No `baseURL` in config | Run `stash config set-url <url>` |
| `Not logged in. Run: stash login` | No access token in config | Run `stash login` |
| `Session expired, please run stash login` | Refresh token expired/revoked (local refresh failed); tokens cleared | Run `stash login` again |
| `Session expired, please run stash login.` | Server rejected the access token as expired (note the trailing period, this is the API-mapped variant) | Run `stash login` again |
| `Session invalid, please run stash login.` | Server rejected the access token as malformed/invalid (not merely expired) | Run `stash login` again |
| `Two-factor authentication is required.` | A 2FA-gated action hit the API without a completed 2FA login | Complete `stash login` (it prompts for the 2FA code) |
| `Could not reach the server. <detail> (Check the URL and scheme: a plain HTTP server needs http://, not https://.)` | Network/TLS/URL issue (e.g. `https://` against a plain-HTTP server); `<detail>` is the underlying transport error | Check the URL scheme and that the server is up |
| `The server URL is invalid. Set it with: stash config set-url <url>` | Malformed base URL | Re-set with `stash config set-url <url>` |
| `This URL is already saved (existing bookmark <uuid>).` | Duplicate URL on `add` | Use `stash list --search` to find the existing one; or `get`/update it |
| `Not found.` | ID/resource doesn't exist (also `admin reset-totp` if route is unexposed) | Verify the UUID with `stash list --json` |
| `You don't have permission to perform that action.` | Not an admin | The command requires an admin account |
| `Invalid username or password.` | Bad credentials at login | Re-check credentials |
| `This account is suspended.` | Account inactive | Have an admin unsuspend it |
| `Invalid two-factor code.` | Wrong TOTP/recovery code | Re-enter the current code |
| `That username is already taken.` | `admin create-user` conflict | Choose a different username |
| `The request was invalid.` | Validation failed (e.g. password too short) | Fix the input (passwords need ≥12 chars) |
| `The server returned HTTP <code>.` / `The server encountered an error.` | Unexpected server status / 5xx | Retry; check server logs |
| `Could not decode the server's response.` / `Could not encode the request.` / `Request preparation failed. <detail>` / `Response handling failed. <detail>` | Rare client-side encode/decode or interceptor failure (usually a version/contract mismatch) | Verify the CLI and backend are on compatible versions; report if it persists |
| `Invalid bookmark ID: <value>` / `Invalid Smart View ID: <value>` | A non-UUID was passed to `get`/`delete`/`archive` or `smart-views bookmarks` | Pass a full UUID from `stash list --json` / `smart-views list --json` |
