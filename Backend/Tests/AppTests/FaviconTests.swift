// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

// MARK: - MockClient

/// A `Client` that returns canned responses keyed by URL substring and records every request,
/// so favicon-fetching tests never touch the network. The first matching stub wins; an unmatched
/// URL responds `404`.
final class MockClient: Client, @unchecked Sendable {

    // MARK: Nested Types

    struct Stub {

        let match: String
        let status: HTTPResponseStatus
        let contentType: String?
        let body: ByteBuffer?
    }

    // MARK: Properties

    let eventLoop: EventLoop
    let byteBufferAllocator: ByteBufferAllocator

    private(set) var requestedURLs: [String] = []

    private var stubs: [Stub] = []

    // MARK: Lifecycle

    init(eventLoop: EventLoop, byteBufferAllocator: ByteBufferAllocator = .init()) {
        self.eventLoop = eventLoop
        self.byteBufferAllocator = byteBufferAllocator
    }

    // MARK: Functions

    func delegating(to eventLoop: EventLoop) -> Client {
        self
    }

    func logging(to logger: Logger) -> Client {
        self
    }

    func allocating(to byteBufferAllocator: ByteBufferAllocator) -> Client {
        self
    }

    func stub(contains match: String, status: HTTPResponseStatus, contentType: String?, bytes: [UInt8]?) {
        let body = bytes.map { ByteBuffer(bytes: $0) }
        stubs.append(Stub(match: match, status: status, contentType: contentType, body: body))
    }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        let url = request.url.string
        requestedURLs.append(url)

        guard let stub = stubs.first(where: { url.contains($0.match) }) else {
            return eventLoop.makeSucceededFuture(ClientResponse(status: .notFound))
        }

        var headers = HTTPHeaders()
        if let contentType = stub.contentType {
            headers.replaceOrAdd(name: .contentType, value: contentType)
        }
        if let body = stub.body {
            headers.replaceOrAdd(name: .contentLength, value: String(body.readableBytes))
        }

        return eventLoop.makeSucceededFuture(
            ClientResponse(status: stub.status, headers: headers, body: stub.body)
        )
    }
}

// MARK: - DomainExtractorTests

@Suite("Favicon — domain extraction")
struct DomainExtractorTests {

    @Test("lowercases the host")
    func lowercases() {
        // Given / When / Then
        #expect(
            DomainExtractor.domain(from: "HTTPS://Example.COM/Path") == "example.com",
            "It should lowercase the host"
        )
    }

    @Test("strips a leading www.")
    func stripsWWW() {
        // Given / When / Then
        #expect(
            DomainExtractor.domain(from: "https://www.github.com/anything") == "github.com",
            "It should strip a leading www. so www.github.com and github.com share one entry"
        )
    }

    @Test("keeps a bare host unchanged")
    func bareHost() {
        // Given / When / Then
        #expect(DomainExtractor.domain(from: "https://github.com") == "github.com", "It should keep a bare host")
    }

    @Test("returns nil for an unparseable URL")
    func unparseable() {
        // Given / When / Then
        #expect(DomainExtractor.domain(from: "not a valid url") == nil, "It should return nil for an unparseable URL")
        #expect(DomainExtractor.domain(from: "") == nil, "It should return nil for an empty string")
    }

    @Test("keeps the port in the cache key so same-host different-port URLs don't collide")
    func preservesPort() {
        // Given / When / Then
        #expect(
            DomainExtractor.domain(from: "http://192.168.1.5:8080/a") == "192.168.1.5:8080",
            "It should keep the port so two services on one host get distinct cache keys"
        )
        #expect(
            DomainExtractor.domain(from: "http://192.168.1.5:9090/b") == "192.168.1.5:9090",
            "It should distinguish a second port on the same host"
        )
    }

    @Test("origin preserves the scheme and port for the favicon.ico guess")
    func origin() {
        // Given / When / Then
        #expect(
            DomainExtractor.origin(from: "http://192.168.1.5:8080/a") == "http://192.168.1.5:8080",
            "It should preserve the original scheme and port rather than assuming https"
        )
        #expect(
            DomainExtractor.origin(from: "https://www.github.com/x") == "https://www.github.com",
            "It should keep the real host (www) for the origin"
        )
    }
}

// MARK: - FaviconFetcherTests

@Suite("Favicon — fetch and cache")
struct FaviconFetcherTests {

    // MARK: Properties

    private let imageBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    // MARK: Functions

    @Test("the site's own favicon succeeds → cached with image data")
    func ownFaviconSucceeds() async throws {
        try await withTestApp { app in
            // Given
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(contains: "/favicon.ico", status: .ok, contentType: "image/x-icon", bytes: imageBytes)

            // When
            await FaviconFetcher.fetchAndCache(domain: "example.com", on: app.db, client: client)

            // Then
            let cache = try #require(
                try await FaviconCache.query(on: app.db).filter(\.$domain == "example.com").first()
            )
            #expect(cache.status == .cached, "It should mark the favicon cached")
            #expect(cache.imageData != nil, "It should store the image bytes")
            #expect(cache.contentType == "image/x-icon", "It should store the content type")
            #expect(cache.sourceURL?.contains("/favicon.ico") == true, "It should record the site's own favicon URL")
        }
    }

    @Test("the site's own favicon fails, Google fallback succeeds")
    func googleFallback() async throws {
        try await withTestApp { app in
            // Given
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(contains: "/favicon.ico", status: .notFound, contentType: nil, bytes: nil)
            client.stub(contains: "google.com/s2", status: .ok, contentType: "image/png", bytes: imageBytes)

            // When
            await FaviconFetcher.fetchAndCache(domain: "example.com", on: app.db, client: client)

            // Then
            let cache = try #require(
                try await FaviconCache.query(on: app.db).filter(\.$domain == "example.com").first()
            )
            #expect(cache.status == .cached, "It should fall back to Google and cache the result")
            #expect(cache.sourceURL?.contains("google.com/s2") == true, "It should record the Google service URL")
        }
    }

    @Test("both the site's favicon and Google fail → failed with no image")
    func bothFail() async throws {
        try await withTestApp { app in
            // Given
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(contains: "/favicon.ico", status: .notFound, contentType: nil, bytes: nil)
            client.stub(contains: "google.com/s2", status: .internalServerError, contentType: nil, bytes: nil)

            // When
            await FaviconFetcher.fetchAndCache(domain: "example.com", on: app.db, client: client)

            // Then
            let cache = try #require(
                try await FaviconCache.query(on: app.db).filter(\.$domain == "example.com").first()
            )
            #expect(cache.status == .failed, "It should mark the favicon failed when every attempt fails")
            #expect(cache.imageData == nil, "It should not store any image bytes on failure")
        }
    }

    @Test("a non-image Content-Type is treated as a failure")
    func nonImageContentType() async throws {
        try await withTestApp { app in
            // Given
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(contains: "/favicon.ico", status: .ok, contentType: "text/html", bytes: imageBytes)
            client.stub(contains: "google.com/s2", status: .ok, contentType: "text/plain", bytes: imageBytes)

            // When
            await FaviconFetcher.fetchAndCache(domain: "example.com", on: app.db, client: client)

            // Then
            let cache = try #require(
                try await FaviconCache.query(on: app.db).filter(\.$domain == "example.com").first()
            )
            #expect(cache.status == .failed, "It should reject a non-image Content-Type")
            #expect(cache.imageData == nil, "It should not cache a non-image response")
        }
    }

    @Test("an SVG favicon is rejected to avoid serving active content from the Stash origin")
    func rejectsSVG() async throws {
        try await withTestApp { app in
            // Given
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(contains: "/favicon.ico", status: .ok, contentType: "image/svg+xml", bytes: imageBytes)
            client.stub(contains: "google.com/s2", status: .notFound, contentType: nil, bytes: nil)

            // When
            await FaviconFetcher.fetchAndCache(domain: "example.com", on: app.db, client: client)

            // Then
            let cache = try #require(
                try await FaviconCache.query(on: app.db).filter(\.$domain == "example.com").first()
            )
            #expect(cache.status == .failed, "It should reject image/svg+xml rather than caching active content")
        }
    }

    @Test("the favicon.ico guess uses the origin's scheme and port, not a hardcoded https")
    func originSchemeGuess() async throws {
        try await withTestApp { app in
            // Given
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(
                contains: "http://192.168.1.5:8080/favicon.ico",
                status: .ok,
                contentType: "image/png",
                bytes: imageBytes
            )

            // When
            await FaviconFetcher.fetchAndCache(
                domain: "192.168.1.5:8080",
                originURL: "http://192.168.1.5:8080",
                on: app.db,
                client: client
            )

            // Then
            let cache = try #require(
                try await FaviconCache.query(on: app.db).filter(\.$domain == "192.168.1.5:8080").first()
            )
            #expect(cache.status == .cached, "It should fetch favicon.ico over http on the original port")
            #expect(
                cache.sourceURL == "http://192.168.1.5:8080/favicon.ico",
                "It should not rewrite the scheme to https or drop the port"
            )
        }
    }

    @Test("an oversized response (> 100KB) is treated as a failure")
    func oversized() async throws {
        try await withTestApp { app in
            // Given
            let oversized = [UInt8](repeating: 0x41, count: 200 * 1024)
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(contains: "/favicon.ico", status: .ok, contentType: "image/png", bytes: oversized)
            client.stub(contains: "google.com/s2", status: .ok, contentType: "image/png", bytes: oversized)

            // When
            await FaviconFetcher.fetchAndCache(domain: "example.com", on: app.db, client: client)

            // Then
            let cache = try #require(
                try await FaviconCache.query(on: app.db).filter(\.$domain == "example.com").first()
            )
            #expect(cache.status == .failed, "It should reject an oversized response")
        }
    }

    @Test("a domain that already has a cache row is skipped — no duplicate row, no HTTP calls")
    func alreadyCachedSkips() async throws {
        try await withTestApp { app in
            // Given
            try await FaviconCache(
                domain: "example.com",
                imageData: Data(imageBytes),
                contentType: "image/png",
                status: .cached
            )
            .save(on: app.db)
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(contains: "/favicon.ico", status: .ok, contentType: "image/png", bytes: imageBytes)

            // When
            await FaviconFetcher.fetchAndCache(domain: "example.com", on: app.db, client: client)

            // Then
            let count = try await FaviconCache.query(on: app.db).filter(\.$domain == "example.com").count()
            #expect(count == 1, "It should not create a duplicate row")
            #expect(client.requestedURLs.isEmpty, "It should make no HTTP calls when a row already exists")
        }
    }

    @Test("two URLs on the same domain produce one row and one fetch")
    func sameDomainOneFetch() async throws {
        try await withTestApp { app in
            // Given
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(contains: "/favicon.ico", status: .ok, contentType: "image/png", bytes: imageBytes)

            // When
            await FaviconFetcher.fetchAndCache(domain: "example.com", on: app.db, client: client)
            let afterFirst = client.requestedURLs.count
            await FaviconFetcher.fetchAndCache(domain: "example.com", on: app.db, client: client)

            // Then
            let count = try await FaviconCache.query(on: app.db).filter(\.$domain == "example.com").count()
            #expect(count == 1, "It should create only one row for the shared domain")
            #expect(client.requestedURLs.count == afterFirst, "It should not fetch again for the second bookmark")
        }
    }

    @Test("backfill caches one favicon per distinct domain across a user's bookmarks")
    func backfillDistinctDomains() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await app.makeBookmark(for: user, url: "https://github.com/a")
            try await app.makeBookmark(for: user, url: "https://github.com/b")
            try await app.makeBookmark(for: user, url: "https://swift.org/x")
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(contains: "/favicon.ico", status: .ok, contentType: "image/png", bytes: imageBytes)

            // When
            try await FaviconFetcher.backfill(forUser: user.requireID(), on: app.db, client: client)

            // Then
            let count = try await FaviconCache.query(on: app.db).count()
            #expect(count == 2, "It should create one row per distinct domain (github.com, swift.org)")
            #expect(
                client.requestedURLs.count { $0.contains("/favicon.ico") } == 2,
                "It should fetch once per distinct domain, not once per bookmark"
            )
        }
    }
}

// MARK: - FaviconServeTests

@Suite("Favicon — serve and refresh endpoints")
struct FaviconServeTests {

    // MARK: Properties

    private let imageBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

    // MARK: Functions

    @Test("GET a cached favicon returns the image bytes with caching headers")
    func serveCached() async throws {
        try await withTestApp { app in
            // Given
            try await FaviconCache(
                domain: "example.com",
                imageData: Data(imageBytes),
                contentType: "image/png",
                status: .cached
            ).save(on: app.db)

            // When
            try await app.testing().test(.GET, "api/v1/favicons/example.com") { res async throws in
                // Then
                #expect(res.status == .ok, "It should return 200 OK")
                #expect(res.headers.first(name: .contentType) == "image/png", "It should set the stored content type")
                #expect(
                    res.headers.first(name: .cacheControl) == "public, max-age=2592000, immutable",
                    "It should set a long, immutable Cache-Control header"
                )
                #expect(
                    res.headers.first(name: "X-Content-Type-Options") == "nosniff",
                    "It should send nosniff so the browser can't MIME-sniff the bytes into active content"
                )
                #expect(res.body.readableBytes == imageBytes.count, "It should return the stored image bytes")
            }
        }
    }

    @Test("GET a failed favicon returns 404")
    func serveFailed() async throws {
        try await withTestApp { app in
            // Given
            try await FaviconCache(domain: "example.com", status: .failed).save(on: app.db)

            // When
            try await app.testing().test(.GET, "api/v1/favicons/example.com") { res async throws in
                // Then
                #expect(res.status == .notFound, "It should return 404 for a failed favicon")
            }
        }
    }

    @Test("GET a favicon with no row returns 404")
    func serveMissing() async throws {
        try await withTestApp { app in
            // Given — no row

            // When
            try await app.testing().test(.GET, "api/v1/favicons/nope.com") { res async throws in
                // Then
                #expect(res.status == .notFound, "It should return 404 when no row exists")
            }
        }
    }

    @Test("POST refresh deletes the existing row and returns 202")
    func refreshDeletesAndAccepts() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await FaviconCache(
                domain: "example.com",
                imageData: Data(imageBytes),
                contentType: "image/png",
                status: .cached
            ).save(on: app.db)

            // When
            try await app.testing().test(
                .POST, "api/v1/favicons/example.com/refresh",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(res.status == .accepted, "It should return 202 Accepted immediately")
            }

            let count = try await FaviconCache.query(on: app.db).filter(\.$domain == "example.com").count()
            #expect(count == 0, "It should delete the existing favicon row before re-fetching")
        }
    }

    @Test("POST refresh requires authentication")
    func refreshRequiresAuth() async throws {
        try await withTestApp { app in
            // Given — no auth

            // When
            try await app.testing().test(.POST, "api/v1/favicons/example.com/refresh") { res async throws in
                // Then
                #expect(res.status == .unauthorized, "It should reject an unauthenticated refresh")
            }
        }
    }
}
