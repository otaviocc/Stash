# `stash` CLI admin commands

Reference companion to the `stash-cli` skill; read on demand when working with admin-only user management and stats.

## `admin` (admin accounts only)

All admin commands require the logged-in account to be an admin; a non-admin
gets `Error: You don't have permission to perform that action.` The admin API is
keyed by UUID, but every CLI admin command that targets a user takes a
**username** and resolves it to a UUID internally by listing users and matching
case-insensitively. An unknown name fails with `Error: No user named
'<username>'.`

```bash
stash admin users [--json]                              # list all users
stash admin create-user --username <u> [--password <p>] [--json]
stash admin suspend-user <username>                     # set isActive=false
stash admin unsuspend-user <username>                   # set isActive=true
stash admin reset-password <username> [--password <p>]
stash admin reset-totp <username>                       # clear the user's 2FA
stash admin delete-user <username> [--force]            # hard-delete (irreversible)
stash admin stats [--json]                              # aggregate + per-user stats
```

- `create-user` and `reset-password` prompt for a hidden password if
  `--password` is omitted. `create-user` prints `Created user <username>.`;
  accounts are always created with the `user` role.
- `suspend-user`/`unsuspend-user` print `Suspended <username>.` / `Unsuspended
  <username>.`
- `reset-password` prints `Reset password for <username>.`; `reset-totp` prints
  `Reset 2FA for <username>.`
- `delete-user` prompts `Delete user <username>? [y/N] ` unless `--force`; on
  success `Deleted <username>.` Admins cannot delete their own account.
- `users` and `stats` default to text tables (see Admin output formats below); add `--json` for
  structured output.

> Known gap: `stash admin reset-totp` calls a JSON-API route that may not yet be exposed by the
> backend; if so it surfaces `Error: Not found.` The command is otherwise correct.

## Admin output formats

### Human-readable (default)

**`stash admin users`**: columns USERNAME (20), ROLE (6), ACTIVE (7), 2FA (4),
BOOKMARKS (10), ID (full UUID). ACTIVE is `yes`/`no`; 2FA is `on`/`off`.

**`stash admin stats`**: two summary lines then a table:

```
Total users:     3
Total bookmarks: 214

USERNAME              ACTIVE   BOOKMARKS
alice                 yes      120
bob                   no       94
```

### JSON (`--json`)

Keys are sorted alphabetically. Dates are ISO-8601 without fractional seconds.

**`stash admin users --json`**: an array of user objects:

```json
[
  {
    "bookmarkCount" : 120,
    "createdAt" : "2026-01-01T00:00:00Z",
    "id" : "11111111-2222-3333-4444-555555555555",
    "isActive" : true,
    "isTOTPEnabled" : false,
    "role" : "user",
    "username" : "alice"
  }
]
```

**`stash admin stats --json`**:

```json
{
  "totalBookmarks" : 214,
  "totalUsers" : 3,
  "users" : [
    {
      "bookmarkCount" : 120,
      "id" : "11111111-2222-3333-4444-555555555555",
      "isActive" : true,
      "username" : "alice"
    }
  ]
}
```

## Workflow example

**Admin: create and manage a user:**

```bash
stash admin create-user --username alice --password "securepassword123"
stash admin users --json
stash admin suspend-user alice
stash admin unsuspend-user alice
stash admin reset-password alice --password "newpassword123"
stash admin delete-user alice --force
```
