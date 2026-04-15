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

@Suite("Metadata — HTML parsing")
struct MetadataTests {

    // MARK: Properties

    private let base = URL(string: "https://example.com/page")!

    // MARK: Functions

    @Test("parses title, description, and an absolute favicon")
    func parsesBasics() {
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
    func relativeFavicon() {
        let html = #"<head><link rel="shortcut icon" href="/assets/icon.ico"></head>"#
        let meta = MetadataFetcher.parse(html: html, baseURL: base)
        #expect(meta.faviconURL == "https://example.com/assets/icon.ico")
    }

    @Test("falls back to /favicon.ico when no link tag is present")
    func defaultFavicon() {
        let html = "<head><title>No icon here</title></head>"
        let meta = MetadataFetcher.parse(html: html, baseURL: base)
        #expect(meta.title == "No icon here")
        #expect(meta.faviconURL == "https://example.com/favicon.ico")
    }

    @Test("handles reversed attribute order and Open Graph fallbacks")
    func attributeOrderAndOG() {
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
    func emptyHTML() {
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
