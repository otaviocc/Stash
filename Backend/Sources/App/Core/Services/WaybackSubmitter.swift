// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import AsyncHTTPClient
import Fluent
import Foundation
import NIOCore
import Vapor

// MARK: - WaybackHTTPClient

/// Wraps a dedicated `HTTPClient` as a Vapor `Client`, so `WaybackSubmitter` can use the same
/// `client.get(...)`/`ClientRequest`/`ClientResponse` shape as everywhere else in the app while
/// getting its own connection pool and timeout configuration. This is deliberately **not**
/// `app.client`: that shared client's read timeout is tuned to 5 seconds for favicon and metadata
/// fetching, both of which run inline during a request and must fail fast, but the Internet Archive
/// save endpoint holds the connection open — sending no bytes — for tens of seconds while it
/// crawls the page, which trips a short read timeout long before any per-request deadline matters.
/// Confirmed in production: submissions were failing with `HTTPClientError.readTimeout` because
/// they were silently bound by the app-wide 5-second read timeout regardless of the per-request
/// `ClientRequest.timeout` override, which only extends the overall deadline, not the underlying
/// `HTTPClient`'s configured read timeout — those are two different mechanisms.
private struct WaybackHTTPClient: Client {

    // MARK: Properties

    let http: HTTPClient
    let eventLoop: EventLoop

    // MARK: Functions

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        guard let url = URL(string: request.url.string) else {
            return eventLoop.makeFailedFuture(Abort(
                .internalServerError,
                reason: "\(request.url.string) is an invalid URL"
            ))
        }

        do {
            let httpRequest = try HTTPClient.Request(
                url: url,
                method: request.method,
                headers: request.headers,
                body: request.body.map { .byteBuffer($0) }
            )
            let future = http.execute(
                request: httpRequest,
                eventLoop: .delegate(on: eventLoop),
                deadline: request.timeout.map { .now() + $0 }
            )
            return future.map { response in
                ClientResponse(status: response.status, headers: response.headers, body: response.body)
            }
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
    }

    func delegating(to eventLoop: EventLoop) -> Client {
        WaybackHTTPClient(http: http, eventLoop: eventLoop)
    }
}

// MARK: - WaybackHTTPClientKey

/// Storage key for the raw `HTTPClient` backing `WaybackHTTPClient`, kept only so its shutdown can
/// be registered; `WaybackWorker` holds the wrapped `Client`, not this key, at call time.
struct WaybackHTTPClientKey: StorageKey {

    typealias Value = HTTPClient
}

// MARK: - WaybackWorker

/// Drains bookmarks whose `waybackStatus` is `.pending`, submitting each to the Internet Archive's
/// anonymous save endpoint one at a time. An actor, not a plain enum like `FaviconFetcher`, because
/// submissions must never run concurrently: the anonymous endpoint has tight rate limits, and a
/// second drain starting while one is already in flight would burst it. Bookmarks carry their own
/// `.pending` state in the database (rather than an in-memory list), so the queue survives a
/// restart: `WaybackSubmitter.kick(on:)` re-discovers any row still `.pending` at boot.
actor WaybackWorker {

    // MARK: Nested Types

    /// What the drain loop is doing right now, surfaced on `/admin/internet-archive` so an admin can
    /// tell "actively running" from "paused waiting out a rate-limit backoff" instead of just seeing
    /// a static queued count. Carries the specific bookmark's URL (and, when rate-limited, its
    /// attempt count) rather than being re-derived from a fresh DB query, since by the time anyone
    /// reads this the "oldest pending" row may already be a different bookmark.
    enum QueueState: Sendable, Equatable {

        case idle
        case submitting(url: String)
        case waitingNormalPace
        case waitingAfterRateLimit(url: String, attempt: Int, maxAttempts: Int)
    }

    // MARK: Static Properties

    /// Delay between consecutive submissions, deliberately longer than the favicon queue's, since
    /// the anonymous save endpoint is far more rate-limit-sensitive than favicon providers.
    static let delayBetweenSubmissions: Duration = .seconds(30)

    /// Delay after a `429` before trying the next submission. The anonymous endpoint returns no
    /// `Retry-After` header, so this is a fixed, generous guess rather than a computed value.
    static let rateLimitBackoff: Duration = .seconds(300)

    // MARK: Properties

    private let app: Application
    private let client: Client
    private var isDraining = false
    private var state: QueueState = .idle

    // MARK: Lifecycle

    init(app: Application, client: Client) {
        self.app = app
        self.client = client
    }

    // MARK: Functions

    /// Starts a drain if one isn't already running. Safe to call repeatedly — every enqueue and the
    /// boot-time re-sweep just call this, and it's a no-op while a drain is in flight.
    func kick() {
        guard !isDraining else { return }

        isDraining = true
        Task { await self.drain() }
    }

    /// The drain loop's current phase, for the admin status display.
    func currentState() -> QueueState {
        state
    }

    /// Drains one `pending` bookmark at a time until none remain, pacing between submissions. Each
    /// loop's own fetch doubles as the "is there more work" check, so there's no separate count query.
    /// Re-checks the instance-wide switch on every iteration — not just at `kick()` time — so toggling
    /// it off mid-drain stops further submissions immediately instead of finishing whatever's already
    /// queued.
    private func drain() async {
        defer {
            isDraining = false
            state = .idle
        }

        while true {
            guard WaybackSubmitter.isInstanceEnabled(on: app) else { return }
            guard let bookmark = try? await Bookmark.query(on: app.db)
                .filter(\.$waybackStatus == .pending)
                .sort(\.$updatedAt)
                .first()
            else {
                return
            }

            state = .submitting(url: bookmark.url)
            let outcome = await WaybackSubmitter.submit(bookmark: bookmark, on: app.db, client: client)

            if outcome == .rateLimited {
                state = .waitingAfterRateLimit(
                    url: bookmark.url,
                    attempt: bookmark.waybackRetryCount,
                    maxAttempts: WaybackSubmitter.maxRateLimitRetries
                )
                try? await Task.sleep(for: Self.rateLimitBackoff)
            } else {
                state = .waitingNormalPace
                try? await Task.sleep(for: Self.delayBetweenSubmissions)
            }
        }
    }
}

// MARK: - WaybackWorkerKey

/// Storage key for the app-level `WaybackWorker`, seeded once at boot (mirrors
/// `SiteSettingsCacheKey`'s seeded-holder pattern).
struct WaybackWorkerKey: StorageKey {

    typealias Value = WaybackWorker
}

// MARK: - WaybackSubmitter

/// Submits a bookmark's URL to the Internet Archive's Wayback Machine, anonymously, via
/// `https://web.archive.org/save/<url>`. Submission is queued (bookmark set to `.pending`) rather
/// than run inline, so a bookmark save is never blocked and the rate-limited endpoint is never
/// bursted. See the Internet Archive section of `DECISIONS.md`.
enum WaybackSubmitter {

    // MARK: Nested Types

    /// The result of one `submit(bookmark:on:client:)` call, so the drain loop can back off longer
    /// after a `429` than after an ordinary submission, without needing to re-inspect the bookmark.
    enum SubmitOutcome: Sendable {

        case archived
        case rateLimited
        case failed
    }

    // MARK: Static Properties

    static let savePrefix = "https://web.archive.org/save/"

    /// The `/save` endpoint holds the connection open, sending no bytes, while it crawls and
    /// archives the live page — routinely for tens of seconds. Both timeouts are generous on
    /// purpose: `read` (idle-between-bytes) is what actually matters here, `connect` just guards
    /// against a hung TCP handshake.
    static let httpClientTimeout = HTTPClient.Configuration.Timeout(connect: .seconds(10), read: .seconds(90))

    /// Overall per-request deadline, slightly above `httpClientTimeout.read` so a slow-but-still-
    /// trickling response isn't cut off right as the read timeout would otherwise allow it to finish.
    static let submitTimeout: TimeAmount = .seconds(120)

    /// How many consecutive `429`s a bookmark tolerates before giving up (`.failed`) instead of
    /// staying `.pending` forever. Without this, a persistently rate-limited bookmark — its
    /// `updatedAt` never advancing, since a plain retry doesn't save it — stays the oldest `pending`
    /// row forever and blocks every other bookmark queued behind it, not just itself.
    static let maxRateLimitRetries = 3

    // MARK: Static Functions

    /// Whether the admin-controlled instance-wide switch is on (`/admin/internet-archive`, default
    /// on). Every submission path — auto-submit on create, the detail-page and API "submit" actions,
    /// and the admin bulk actions — gates on this first.
    static func isInstanceEnabled(on app: Application) -> Bool {
        app.storage[SiteSettingsCacheKey.self]?.current.internetArchiveEnabled ?? true
    }

    /// Seeds the app-level worker (and its own dedicated `HTTPClient`, see `WaybackHTTPClient`) and,
    /// outside `.testing`, re-sweeps any bookmark left `.pending` from a previous run (e.g. the
    /// process died mid-drain). Call once, from `configure.swift`, after the database is migrated.
    static func bootstrap(on app: Application) async {
        let httpClient = HTTPClient(
            eventLoopGroupProvider: .shared(app.eventLoopGroup),
            configuration: .init(timeout: httpClientTimeout)
        )
        await app.storage.setWithAsyncShutdown(WaybackHTTPClientKey.self, to: httpClient) { client in
            try await client.shutdown()
        }

        let client = WaybackHTTPClient(http: httpClient, eventLoop: app.eventLoopGroup.next())
        app.storage[WaybackWorkerKey.self] = WaybackWorker(app: app, client: client)

        guard app.environment != .testing else { return }

        kick(on: app)
    }

    /// Marks a bookmark for submission and wakes the drain worker. This is the only enqueue path:
    /// there is no separate in-memory queue, just this status flip plus a query-driven drain. The
    /// status flip always happens (so tests can assert on it); only the actual background drain is
    /// suppressed under `.testing`, via `kick(on:)`.
    static func enqueue(_ bookmark: Bookmark, on app: Application) async {
        bookmark.waybackStatus = .pending
        try? await bookmark.save(on: app.db)
        kick(on: app)
    }

    /// Auto-submits a freshly created bookmark when both the instance-wide switch and the owning
    /// user's `archiveNewBookmarks` preference allow it. The single gate shared by the API and web
    /// create handlers, so the auto-submit rule can't drift between the two.
    static func enqueueIfAllowed(_ bookmark: Bookmark, for user: User, on app: Application) async {
        guard isInstanceEnabled(on: app), user.archiveNewBookmarks else { return }

        await enqueue(bookmark, on: app)
    }

    static func kick(on app: Application) {
        guard app.environment != .testing, let worker = app.storage[WaybackWorkerKey.self] else { return }

        Task { await worker.kick() }
    }

    /// Submits one bookmark and persists the resulting status. Never throws: a genuine failure
    /// (network, timeout, unexpected response) leaves the bookmark `.failed`, retryable via the admin
    /// "Retry failed" action or the next boot's re-sweep. A `429` is treated as transient rather than
    /// terminal, up to `maxRateLimitRetries`: the bookmark stays `.pending` (so the next drain cycle
    /// retries it automatically) and the caller is told to back off longer before the next
    /// submission. Crucially, the bookmark is *saved* on every `429` (bumping `updatedAt`), not just
    /// when it gives up — otherwise it stays the oldest `pending` row forever and starves every other
    /// bookmark queued behind it. Every non-success path logs the response status or error, since a
    /// silent `.failed` gives no way to diagnose *why*.
    @discardableResult
    static func submit(bookmark: Bookmark, on db: Database, client: Client) async -> SubmitOutcome {
        do {
            var headers = HTTPHeaders()
            headers.add(name: .userAgent, value: StashUserAgent.value)

            let target = URI(string: "\(savePrefix)\(bookmark.url)")
            let response = try await client.get(target, headers: headers) { request in
                request.timeout = submitTimeout
            }

            if response.status == .tooManyRequests {
                bookmark.waybackRetryCount += 1

                guard bookmark.waybackRetryCount < maxRateLimitRetries else {
                    db.logger.notice(
                        "Wayback submit giving up for \(bookmark.url) after \(bookmark.waybackRetryCount) rate-limited attempts"
                    )
                    bookmark.waybackStatus = .failed
                    bookmark.waybackRetryCount = 0
                    try await bookmark.save(on: db)
                    return .failed
                }

                db.logger.notice(
                    "Wayback submit rate-limited for \(bookmark.url) (attempt \(bookmark.waybackRetryCount)/\(maxRateLimitRetries)); will retry later"
                )
                try await bookmark.save(on: db)
                return .rateLimited
            }

            let acceptableStatuses: Set<HTTPResponseStatus> = [.ok, .movedPermanently, .found]
            guard acceptableStatuses.contains(response.status) else {
                db.logger.error("Wayback submit failed for \(bookmark.url): HTTP \(response.status.code)")
                bookmark.waybackStatus = .failed
                bookmark.waybackRetryCount = 0
                try await bookmark.save(on: db)
                return .failed
            }

            bookmark.waybackStatus = .archived
            bookmark.waybackURL = snapshotURL(from: response, originalURL: bookmark.url)
            bookmark.waybackArchivedAt = Date()
            bookmark.waybackRetryCount = 0
            try await bookmark.save(on: db)
            db.logger.info("\(ActivityLog.waybackArchived(url: bookmark.url))")
            return .archived
        } catch {
            db.logger.error("Wayback submit failed for \(bookmark.url): \(String(reflecting: error))")
            bookmark.waybackStatus = .failed
            bookmark.waybackRetryCount = 0
            try? await bookmark.save(on: db)
            return .failed
        }
    }

    /// Resolves the captured snapshot's absolute URL from the save response's `Content-Location`
    /// (the usual anonymous-save header) or `Location` header. Falls back to the Wayback Machine's
    /// own "latest snapshot" redirect for the original URL if neither header is present, so "View on
    /// Wayback Machine" always has somewhere to send the user even when the header shape changes.
    private static func snapshotURL(from response: ClientResponse, originalURL: String) -> String {
        guard let path = response.headers.first(name: .contentLocation) ?? response.headers.first(name: .location)
        else {
            return "https://web.archive.org/web/2/\(originalURL)"
        }

        return path.hasPrefix("http") ? path : "https://web.archive.org\(path)"
    }
}
