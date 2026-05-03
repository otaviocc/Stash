// MIT License
//
// Copyright (c) 2026 Otávio C.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import Testing
import VaporTesting
@testable import App

/// Verifies HTML metadata parsing and the authenticated metadata endpoint.
@Suite("Metadata — HTML parsing")
struct MetadataTests {

    // MARK: Properties

    private let base = URL(string: "https://example.com/page")!

    // MARK: Functions

    @Test("parses title, description, and an absolute favicon")
    func parsesBasics() {
        // Given
        let html = """
        <html><head>
        <title>Hello &amp; World</title>
        <meta name="description" content="A great &quot;page&quot;">
        <link rel="icon" href="https://cdn.example.com/fav.png">
        </head><body>x</body></html>
        """

        // When
        let meta = MetadataFetcher.parse(html: html, baseURL: base)

        // Then
        #expect(meta.title == "Hello & World", "It should decode HTML entities in the title")
        #expect(meta.description == "A great \"page\"", "It should decode HTML entities in the description")
        #expect(meta.faviconURL == "https://cdn.example.com/fav.png", "It should keep an absolute favicon URL")
    }

    @Test("resolves a relative favicon href against the base URL")
    func relativeFavicon() {
        // Given
        let html = #"<head><link rel="shortcut icon" href="/assets/icon.ico"></head>"#

        // When
        let meta = MetadataFetcher.parse(html: html, baseURL: base)

        // Then
        #expect(
            meta.faviconURL == "https://example.com/assets/icon.ico",
            "It should resolve a relative favicon href against the base URL"
        )
    }

    @Test("falls back to /favicon.ico when no link tag is present")
    func defaultFavicon() {
        // Given
        let html = "<head><title>No icon here</title></head>"

        // When
        let meta = MetadataFetcher.parse(html: html, baseURL: base)

        // Then
        #expect(meta.title == "No icon here", "It should parse the title")
        #expect(
            meta.faviconURL == "https://example.com/favicon.ico",
            "It should fall back to /favicon.ico when no link tag is present"
        )
    }

    @Test("handles reversed attribute order and Open Graph fallbacks")
    func attributeOrderAndOG() {
        // Given
        let html = """
        <head>
        <meta content="reversed order desc" name="description">
        <meta property="og:title" content="OG Title">
        </head>
        """

        // When
        let meta = MetadataFetcher.parse(html: html, baseURL: base)

        // Then
        #expect(meta.description == "reversed order desc", "It should parse a meta tag with reversed attribute order")
        #expect(meta.title == "OG Title", "It should fall back to og:title when no title tag is present")
    }

    @Test("returns nil title/description for empty HTML but still a default favicon")
    func emptyHTML() {
        // Given — no setup required

        // When
        let meta = MetadataFetcher.parse(html: "", baseURL: base)

        // Then
        #expect(meta.title == nil, "It should return a nil title for empty HTML")
        #expect(meta.description == nil, "It should return a nil description for empty HTML")
        #expect(meta.faviconURL == "https://example.com/favicon.ico", "It should still return a default favicon")
    }

    @Test("POST /metadata requires authentication")
    func metadataRequiresAuth() async throws {
        try await withTestApp { app in
            // Given — no setup required

            // When
            try await app.testing().test(
                .POST, "api/v1/metadata",
                beforeRequest: { req in try req.content.encode(MetadataRequest(url: "https://example.com")) },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unauthorized, "It should reject unauthenticated metadata requests")
                }
            )
        }
    }

    @Test("POST /metadata rejects an invalid URL with 422")
    func metadataInvalidURL() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/metadata",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in try req.content.encode(MetadataRequest(url: "ftp://nope")) },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unprocessableEntity, "It should return 422 Unprocessable Entity")
                    #expect(
                        try res.content.decode(TestError.self).code == "validation_failed",
                        "It should return the validation_failed error code"
                    )
                }
            )
        }
    }
}
