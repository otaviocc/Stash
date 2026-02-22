# HTTPS with Caddy (optional)

Stash serves plain **HTTP** by default. For a machine on your local network that
is perfectly fine — your traffic never leaves the LAN, and nothing about Stash
requires TLS to work.

If you want HTTPS — to silence browser warnings, to expose Stash to the
internet, or just because you prefer encrypted connections — the simplest path
is to put [Caddy](https://caddyserver.com) in front of Stash as a reverse proxy.
Caddy terminates TLS and forwards plain HTTP to the Stash container on your
internal Docker network.

**No changes to the Stash image or its configuration are needed.** Stash keeps
serving plain HTTP internally; Caddy is an opt-in sidecar you add to your
existing `docker-compose.yml`.

## Two use cases

This directory covers both common setups:

| Use case | Certificate | What you need | Example file |
|----------|-------------|---------------|--------------|
| **Local network** | Self-signed (`tls internal`) | A hostname like `myserver.local` | [`Caddyfile.local`](Caddyfile.local) |
| **Internet-exposed** | Automatic Let's Encrypt | A real domain pointing at your public IP | [`Caddyfile.domain`](Caddyfile.domain) |

## How it fits together

`docker-compose.caddy.yml` is a Compose **override** you merge with your
existing `docker-compose.yml`. It:

- adds a `caddy` service (the `caddy:2-alpine` image) listening on ports 80 and
  443,
- removes Stash's direct `8080` port mapping, so all incoming traffic goes
  through Caddy, and
- mounts `./caddy/Caddyfile` as the active configuration.

`Caddyfile` is the active config Caddy actually reads. It ships as a copy of the
local-network example. **Copy whichever example you need over it** before
starting:

```bash
# Local network with a self-signed certificate
cp caddy/Caddyfile.local caddy/Caddyfile

# Internet-exposed with a real domain
cp caddy/Caddyfile.domain caddy/Caddyfile
```

Edit the copied `caddy/Caddyfile` to use your own hostname or domain, then start
the stack with both files:

```bash
docker compose -f docker-compose.yml -f caddy/docker-compose.caddy.yml up -d
```

> **Note on paths:** the override mounts `./caddy/Caddyfile`, so run the command
> from the directory that contains both your `docker-compose.yml` and this
> `caddy/` folder.

## Which one do I want?

- **Just using Stash on my home network?** Use `Caddyfile.local`. You'll get
  HTTPS with a self-signed certificate, and you'll trust Caddy's root CA on each
  device once (see [`Caddyfile.local`](Caddyfile.local) for instructions).
- **Exposing Stash to the internet on a domain I own?** Use `Caddyfile.domain`.
  Caddy obtains and renews a real Let's Encrypt certificate automatically — no
  certificate handling on your part (see [`Caddyfile.domain`](Caddyfile.domain)
  for the prerequisites).
