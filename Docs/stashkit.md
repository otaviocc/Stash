# StashKit (shared Swift package)

The shared Swift package that the [CLI](cli-build.md) and the [iOS/macOS
apps](mobile-build.md) use to talk to the backend over its REST API
(`/api/v1/`). StashKit is **deliberately thin**: it decodes the wire-shape DTOs
and stops there. It does **no** token storage,
**no** silent refresh, **no** DTO→domain mapping, and **no** business logic;
those belong to the client's repository layer.

## Dependencies

Fetched automatically by SwiftPM (`swift-tools-version:6.2`, iOS 26 / macOS 26):

| Package | Purpose |
|---------|---------|
| [`otaviocc/MicroClient`](https://github.com/otaviocc/MicroClient) | Typed networking layer (`NetworkRequest` / `NetworkClient` / interceptors) |

Add it to a SwiftPM target:

```swift
.package(path: "../StashKit")               // local
// or
.package(url: "…/StashKit.git", from: "…")  // remote
```

## Architecture

Four directories, in dependency order:

1. **DTOs** (`Sources/StashKit/DTOs/`): `Codable & Sendable` structs matching
   the API's JSON shapes (`BookmarkDTO`, `TagDTO`, `UserDTO`, `TokenPairDTO`,
   `SmartViewDTO`, `SmartViewConditionDTO`, `PageDTO<T>`, `APIErrorDTO`,
   `InstanceDTO`, `MetadataDTO` (as `PageMetadataDTO`), `ChangesPageDTO`,
   `DeletedBookmarkDTO`, …).
2. **Requests** (`Sources/StashKit/Requests/`): the `NetworkRequest` bodies
   themselves, one file per domain, kept separate from the factories that
   assemble them.
3. **Request factories** (`Sources/StashKit/Factories/`): one `enum` per API
   domain whose `public static` methods build typed
   `NetworkRequest<RequestModel, ResponseModel>` values. They are pure value
   builders with no I/O, so they're trivially testable by inspecting the returned
   request.
4. **`StashClient`** (`Sources/StashKit/Client/`): a thin wrapper over
   `MicroClient.NetworkClient` that owns the configuration (base URL +
   interceptors) and exposes a single `run(_:)`. Its only value-add over
   `NetworkClient` is mapping non-2xx responses to a typed `StashAPIError`.

## 1. Initialize a client

`StashClient` is storage-agnostic: instead of holding a token, it takes a
`tokenProvider` closure that it calls at request time, so a refresh that
rewrites your token store is picked up without rebuilding the client.

```swift
import StashKit

let client = StashClient(
    baseURL: URL(string: "http://localhost:8080")!,
    tokenProvider: { await tokenStore.accessToken }   // your storage; return nil when signed out
)
```

The client configures its JSON coders with `.iso8601` dates (matching the
backend) and installs a bearer-auth, content-type, and accept-header
interceptor. Token storage and refresh are **your** responsibility: call
`AuthRequestFactory.makeRefreshRequest(...)` before a request when the access
token is near expiry.

## 2. Assemble a network request

Build a request with the factory for its domain. Each method returns a typed
`NetworkRequest<RequestModel, ResponseModel>`, so the response type is known at
the call site.

```swift
// GET /api/v1/bookmarks?q=swift&tag=ios&archived=false&page=1&per=20
let listRequest = BookmarkRequestFactory.makeListRequest(
    query: BookmarkListQuery(searchQuery: "swift", tag: "ios")
)

// POST /api/v1/bookmarks
let createRequest = BookmarkRequestFactory.makeCreateRequest(
    CreateBookmarkRequest(url: "https://example.com", tags: ["swift", "ios"])
)

// POST /api/v1/auth/login
let loginRequest = AuthRequestFactory.makeLoginRequest(
    username: "alice",
    password: "secret"
)
```

The factories:

| Factory | Domain |
|---------|--------|
| `AuthRequestFactory` | login, TOTP, recovery, refresh, logout, TOTP setup/verify/disable |
| `BookmarkRequestFactory` | list, get, create, update, delete, submit to Wayback, offline-sync `changes`/`deleted` |
| `TagRequestFactory` | list, rename, delete |
| `SmartViewRequestFactory` | list, get, create, update, delete, run query (`:id/bookmarks`) |
| `MetadataRequestFactory` | fetch title/description/favicon for a URL |
| `FaviconRequestFactory` | refresh a domain's cached favicon |
| `InstanceRequestFactory` | unauthenticated instance info (accent theme) |
| `UserRequestFactory` | current user (`/me`), change password |
| `AdminRequestFactory` | list/create/update/delete users, reset a user's TOTP, stats |

`BookmarkListQuery` maps to the API's `q`/`tag`/`archived`/`page`/`per` query
items; its sentinel tags (`untaggedTag` = `__untagged__`, `todayTag`,
`thisWeekTag`, `readLaterTag`) select the sidebar "Views" instead of filtering
by a real tag.

## 3. Trigger the request

Pass the request to `client.run(_:)`. On success it returns a
`NetworkResponse<ResponseModel>` whose `.value` is the decoded DTO; on a non-2xx
response it throws a typed `StashAPIError`.

```swift
do {
    let response = try await client.run(listRequest)
    let page = response.value          // BookmarkPageDTO
    print(page.items, page.metadata.total)
} catch let error as StashAPIError {
    switch error {
    case .invalidCredentials:           break // ...
    case .duplicateURL(let existingID): break // 409 carries the existing bookmark's id
    case .notFound, .forbidden, .validationFailed, .serverError:
        break
    default:
        break
    }
}
```

`StashAPIError` enumerates the known backend error codes (`invalidCredentials`,
`accountSuspended`, `tokenExpired`, `tokenInvalid`, `totpRequired`,
`totpInvalid`, `forbidden`, `notFound`, `duplicateURL(existingID:)`,
`usernameTaken`, `validationFailed`, `serverError`) and falls back to
`.serverError` (5xx) or `.unknown(Error)` for anything unrecognized.

> **Note: the 2FA login branch.** `POST /auth/login` returns *either* a token pair *or*
> `{ requires2FA, tempToken }`, both as HTTP 200. `makeLoginRequest` is typed to
> `TokenPairDTO` only, so a client that needs to handle the challenge builds that one
> request directly on `MicroClient` and decodes both shapes (see how the CLI and app do
> it).

## Tests

```sh
swift test
swift test --filter <TestName>
```

Tests inject a `MockURLSession` (conforming to `MicroClient.URLSessionProtocol`)
that records the last request and replays a canned status + body, covering
factory paths/methods/query items, body encoding, success decoding, and every
error-code → `StashAPIError` mapping.

## Lint

```sh
swiftformat . --lint     # must be idempotent
swiftlint lint           # must report 0 violations
```
