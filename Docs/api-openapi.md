# OpenAPI specification

Stash ships a hand-written [OpenAPI 3.0.3](https://spec.openapis.org/oas/v3.0.3)
description of its JSON REST API, plus a browsable [Swagger UI](https://swagger.io/tools/swagger-ui/)
page. This guide says where to find them and how to use them. The spec itself,
not this page, is the authoritative reference for request and response shapes;
see also the human-readable [API and routes reference](api.md).

## Where to find it

| What | Location |
|------|----------|
| The spec (source of truth) | `Backend/Public/openapi.yaml` |
| The spec (served, on any running instance) | `GET /openapi.yaml` |
| Swagger UI (browse + "Try it out") | `GET /docs.html` |

Both files are served as static assets by the backend's existing
`FileMiddleware`; no extra routes, no build step. Swagger UI loads from a CDN,
so the docs page needs network access to render; the spec file itself is fully
self-contained.

> The page is served at `/docs.html` (not `/docs`): a bare `/docs` alias would
> require a new Swift route, and adding one was out of scope for the spec work.

## Scope

The spec covers the **JSON API only**: every `/api/v1/` endpoint plus the
unversioned `/health` check. The server-rendered web UIs (`/app` and `/admin`)
are session-cookie driven and are deliberately **excluded**: they are not part
of the public, token-authenticated API surface.

Authentication is JWT Bearer (`Authorization: Bearer <accessToken>`). The
unauthenticated endpoints are `POST /api/v1/auth/*` (login/refresh/etc.),
`GET /api/v1/instance` (accent theme, for unauthenticated screens), the
favicon **serve** endpoint (`GET /api/v1/favicons/{domain}`), and `/health`.

## Using it with third-party tools

- **Browse interactively:** open `/docs.html` on a running instance, or paste
  the contents of `openapi.yaml` into <https://editor.swagger.io>.
- **Postman:** *Import → File* and select `openapi.yaml` (or *Import → Link*
  with `https://<your-instance>/openapi.yaml`). Postman generates a request
  collection from the operations.
- **Insomnia:** *Create → Import From File* and select `openapi.yaml`.
- **Client generation:** the spec feeds `openapi-generator`, `swagger-codegen`,
  or any 3.0.3-compatible tool, should you want a client in another language.

When trying requests against a live server from Swagger UI, click
**Authorize**, paste an access token from `POST /api/v1/auth/login`, and the
`bearerAuth` scheme attaches it to every authenticated call.

## Maintaining it

The spec is the source of truth and is kept in lockstep with the API by hand:

- **Update `Backend/Public/openapi.yaml` in the same commit** as any change to
  an `/api/v1/` endpoint: a new route, a renamed field, a changed status code,
  a new error case. Treat a spec that lags the code as a bug.
- After editing, **re-validate** before committing:
  ```sh
  npx @apidevtools/swagger-cli validate Backend/Public/openapi.yaml
  ```
  (or paste it into <https://editor.swagger.io>, which validates as you type).
- The wire shapes mirror the backend's `Content` response structs and StashKit's
  DTOs; keep all three in agreement.
