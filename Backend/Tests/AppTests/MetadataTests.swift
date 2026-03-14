import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("Metadata — HTML parsing")
struct MetadataTests {
    private let base = URL(string: "https://example.com/page")!

    @Test("parses title, description, and an absolute favicon")
    func parsesBasics() async throws {
        let html = """
        <html><head>
        <title>Hello &amp; World</title>
        <meta name="description" content="A great &quot;page&quot;">
        <link rel="icon" href="https://cdn.example.com/fav.png">
        </head><body>x</body></html>
        """
        let meta = MetadataFetcher.parse(html: html, baseURL: base)
        #expect(meta.title == "Hello & World")
        #expect(meta.description == "A great \"page\"")
        #expect(meta.faviconURL == "https://cdn.example.com/fav.png")
    }

    @Test("resolves a relative favicon href against the base URL")
    func relativeFavicon() async throws {
        let html = #"<head><link rel="shortcut icon" href="/assets/icon.ico"></head>"#
        let meta = MetadataFetcher.parse(html: html, baseURL: base)
        #expect(meta.faviconURL == "https://example.com/assets/icon.ico")
    }

    @Test("falls back to /favicon.ico when no link tag is present")
    func defaultFavicon() async throws {
        let html = "<head><title>No icon here</title></head>"
        let meta = MetadataFetcher.parse(html: html, baseURL: base)
        #expect(meta.title == "No icon here")
        #expect(meta.faviconURL == "https://example.com/favicon.ico")
    }

    @Test("handles reversed attribute order and Open Graph fallbacks")
    func attributeOrderAndOG() async throws {
        let html = """
        <head>
        <meta content="reversed order desc" name="description">
        <meta property="og:title" content="OG Title">
        </head>
        """
        let meta = MetadataFetcher.parse(html: html, baseURL: base)
        #expect(meta.description == "reversed order desc")
        // No <title>, so og:title is used.
        #expect(meta.title == "OG Title")
    }

    @Test("returns nil title/description for empty HTML but still a default favicon")
    func emptyHTML() async throws {
        let meta = MetadataFetcher.parse(html: "", baseURL: base)
        #expect(meta.title == nil)
        #expect(meta.description == nil)
        #expect(meta.faviconURL == "https://example.com/favicon.ico")
    }

    @Test("POST /metadata requires authentication")
    func metadataRequiresAuth() async throws {
        try await withTestApp { app in
            try await app.testing().test(
                .POST, "api/v1/metadata",
                beforeRequest: { req in try req.content.encode(MetadataRequest(url: "https://example.com")) },
                afterResponse: { res async throws in #expect(res.status == .unauthorized) }
            )
        }
    }

    @Test("POST /metadata rejects an invalid URL with 422")
    func metadataInvalidURL() async throws {
        try await withTestApp { app in
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .POST, "api/v1/metadata",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in try req.content.encode(MetadataRequest(url: "ftp://nope")) },
                afterResponse: { res async throws in
                    #expect(res.status == .unprocessableEntity)
                    #expect(try res.content.decode(TestError.self).code == "validation_failed")
                }
            )
        }
    }
}
