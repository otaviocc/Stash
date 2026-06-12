# Docker Compose + Caddy (HTTPS)

For users who want HTTPS — either on a local network or exposed to the internet.

Stash runs plain HTTP by default. [Caddy](https://caddyserver.com) is an optional
sidecar container that adds HTTPS in front of Stash as a reverse proxy: Caddy
terminates TLS and forwards plain HTTP to the Stash container on the internal Docker
network. **No changes to the Stash image or its configuration are needed** — Caddy is
an opt-in sidecar you add to your existing `docker-compose.yml`.

## How it fits together

You add a second Compose file (a *override*) that you merge with the published
`docker-compose.yml`. The override:

- adds a `caddy` service (the `caddy:2-alpine` image) listening on ports 80 and 443,
- removes Stash's direct `8080` port mapping, so all incoming traffic goes through
  Caddy, and
- mounts a `Caddyfile` (your configuration) into the Caddy container.

Create a folder named `caddy/` next to your `docker-compose.yml` and save the two files
below into it: the Compose override and the `Caddyfile`.

### `caddy/docker-compose.caddy.yml`

```yaml
services:
  app:
    # Remove the direct port exposure — Caddy handles incoming traffic
    ports: !reset []

  caddy:
    image: caddy:2-alpine
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - app
    restart: unless-stopped

volumes:
  caddy_data:
  caddy_config:
```

Then pick one of the two `Caddyfile` configurations below.

> **Note on paths:** the override mounts `./caddy/Caddyfile`, so run the start command
> from the directory that contains both your `docker-compose.yml` and the `caddy/`
> folder.

## Option A — Local network with a self-signed certificate

Use when accessing Stash only on your home network, with no public domain. Caddy
generates its own certificate authority and issues a certificate for your hostname; no
domain or internet connectivity is required.

Save as `caddy/Caddyfile` (replace `myserver.local` with your server's hostname):

```
myserver.local {
    tls internal
    reverse_proxy app:8080
}
```

Start with both Compose files:

```bash
docker compose -f docker-compose.yml -f caddy/docker-compose.caddy.yml up -d
```

### Trusting the certificate (one-time per device)

After the first run, trust Caddy's root CA on each device so browsers stop warning about
the self-signed certificate.

1. Extract the root certificate from the running Caddy container:

   ```bash
   docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt ./caddy-root.crt
   ```

2. Trust `caddy-root.crt` on each device:

   - **macOS:** Double-click `caddy-root.crt` → Keychain Access → find the "Caddy Local
     Authority" certificate → expand "Trust" → set "When using this certificate" to
     "Always Trust".
   - **iPhone/iPad:** AirDrop `caddy-root.crt` to the device → Settings → "Profile
     Downloaded" → Install. Then Settings → General → About → Certificate Trust
     Settings → enable full trust for the Caddy certificate.
   - **Linux:**

     ```bash
     sudo cp caddy-root.crt /usr/local/share/ca-certificates/
     sudo update-ca-certificates
     ```

After trusting the certificate, `https://myserver.local` works with no browser warnings.

## Option B — Internet-exposed with a real domain (automatic Let's Encrypt)

Use when you have a domain name and want Stash accessible from anywhere. Caddy obtains
and renews the certificate automatically — there is nothing to install, configure, or
rotate by hand.

Prerequisites:

- The server must be reachable from the internet on ports 80 and 443 (forward both
  through your router/firewall to this host).
- DNS for your domain must already point to the server's public IP address — Caddy
  validates domain ownership over HTTP/TLS on first run.

Save as `caddy/Caddyfile` (replace with your actual domain):

```
stash.yourdomain.com {
    reverse_proxy app:8080
}
```

Start with both Compose files:

```bash
docker compose -f docker-compose.yml -f caddy/docker-compose.caddy.yml up -d
```

Caddy fetches and renews the Let's Encrypt certificate automatically. No further
configuration is needed.
