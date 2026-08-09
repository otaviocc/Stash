// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the bookmark detail page's `returnTo` mechanism: the back link and every detail-page
/// action (edit, archive, delete, etc.) preserve the tag/Smart View list the user came from, and
/// the `safeReturnTo` guard rejects unsafe redirect targets while still accepting legitimate ones.
@Suite("Bookmark detail: returnTo list-context preservation")
struct BookmarkReturnToTests {

    @Test("the detail page's back link uses a safe, caller-supplied returnTo value")
    func detailBackLinkUsesReturnTo() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let bookmarkID = try bookmark.requireID()

            // When
            try await app.testing().test(
                .GET, "app/bookmarks/\(bookmarkID)?returnTo=%2Fapp%3Ftag%3Dswift",
                headers: headers
            ) { res async throws in
                // Then
                #expect(
                    res.body.string.contains(#"href="/app?tag=swift">← Back to bookmarks"#),
                    "It should point the back link at the originating tag list"
                )
            }
        }
    }

    @Test("the detail page falls back to /app for an unsafe returnTo value")
    func detailBackLinkRejectsUnsafeReturnTo() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let bookmarkID = try bookmark.requireID()

            // When
            try await app.testing().test(
                .GET, "app/bookmarks/\(bookmarkID)?returnTo=https://evil.example.com",
                headers: headers
            ) { res async throws in
                // Then
                #expect(
                    res.body.string.contains(#"href="/app">← Back to bookmarks"#),
                    "It should reject an absolute URL and fall back to /app"
                )
                #expect(!res.body.string.contains("evil.example.com"), "It should never surface the unsafe value")
            }
        }
    }

    @Test("a returnTo value containing :// in its search text is still accepted, not just paths without it")
    func detailBackLinkAcceptsSearchTextContainingScheme() async throws {
        try await withTestApp { app in
            // Given: a returnTo built from a real search for a URL-shaped term, matching what
            // BookmarkPresenter.listURL/TagPresenter.queryValue actually produce for `?q=`.
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let bookmarkID = try bookmark.requireID()
            let returnTo = TagPresenter.queryValue("/app?q=https://example.com")

            // When
            try await app.testing().test(
                .GET, "app/bookmarks/\(bookmarkID)?returnTo=\(returnTo)",
                headers: headers
            ) { res async throws in
                // Then
                #expect(
                    res.body.string.contains(#"href="/app?q=https://example.com">← Back to bookmarks"#),
                    "It should preserve a local path even though it contains :// in the search text"
                )
            }
        }
    }

    @Test("the detail page rejects a returnTo value carrying embedded control characters")
    func detailBackLinkRejectsControlCharacters() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let bookmarkID = try bookmark.requireID()

            // When
            try await app.testing().test(
                .GET, "app/bookmarks/\(bookmarkID)?returnTo=/app%0d%0aSet-Cookie:%20evil=1",
                headers: headers
            ) { res async throws in
                // Then
                #expect(
                    res.body.string.contains(#"href="/app">← Back to bookmarks"#),
                    "It should reject an embedded CR/LF and fall back to /app"
                )
            }
        }
    }

    @Test("deleting a bookmark redirects back to the originating list, not /app")
    func deleteRedirectsToReturnTo() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let bookmarkID = try bookmark.requireID()

            // When
            try await app.testing().test(
                .POST, "app/bookmarks/\(bookmarkID)/delete?returnTo=%2Fapp%3Ftag%3Dswift",
                headers: headers
            ) { res async throws in
                // Then
                #expect(
                    res.headers.first(name: .location) == "/app?tag=swift",
                    "It should redirect to the tag list the bookmark was opened from"
                )
            }
        }
    }

    @Test("deleting a bookmark with no returnTo still redirects to /app")
    func deleteWithoutReturnToFallsBackToApp() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let bookmarkID = try bookmark.requireID()

            // When
            try await app.testing().test(
                .POST, "app/bookmarks/\(bookmarkID)/delete",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.headers.first(name: .location) == "/app", "It should redirect to /app as before")
            }
        }
    }

    @Test("creating a bookmark carries returnTo forward to the new bookmark's detail-page redirect")
    func createRedirectCarriesReturnToForward() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()

            // When: as the "Add bookmark" form itself submits, with returnTo on the action URL
            try await app.testing().test(
                .POST, "app/bookmarks?returnTo=%2Fapp%3Ftag%3Dswift",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(["url": "https://example.com", "action": "save"], as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    // Then
                    let location = try #require(res.headers.first(name: .location))
                    let components = try #require(URLComponents(string: location))
                    let items = components.queryItems ?? []
                    #expect(items.first { $0.name == "ok" }?.value == "created", "It should carry the flash")
                    #expect(
                        items.first { $0.name == "returnTo" }?.value == "/app?tag=swift",
                        "It should carry returnTo forward so the new bookmark's back link points at the tag list"
                    )
                }
            )
        }
    }

    @Test("archiving a bookmark opened from the unfiltered list ignores a self-referential Referer")
    func archiveIgnoresRefererWhenNoExplicitReturnTo() async throws {
        try await withTestApp { app in
            // Given: no returnTo query param (as when opened from plain /app), and a Referer that
            // (as it would in a real browser) points at the detail page's own prior URL, this must
            // never be treated as return context, or the back link would loop back on itself.
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let bookmarkID = try bookmark.requireID()
            var refererHeaders = headers
            refererHeaders.add(name: "Host", value: "stash.example.com")
            refererHeaders.add(name: "Referer", value: "http://stash.example.com/app/bookmarks/\(bookmarkID)")

            // When
            try await app.testing().test(
                .POST, "app/bookmarks/\(bookmarkID)/archive",
                headers: refererHeaders
            ) { res async throws in
                // Then
                #expect(
                    res.headers.first(name: .location) == "/app/bookmarks/\(bookmarkID)?ok=archived",
                    "It should redirect with no returnTo, not loop back on the detail page's own Referer"
                )
            }
        }
    }

    @Test("archiving a bookmark re-attaches returnTo to the detail-page redirect")
    func archiveRedirectReattachesReturnTo() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let bookmarkID = try bookmark.requireID()

            // When
            try await app.testing().test(
                .POST, "app/bookmarks/\(bookmarkID)/archive?returnTo=%2Fapp%3Ftag%3Dswift",
                headers: headers
            ) { res async throws in
                // Then: decode the Location header rather than comparing the encoded string
                // verbatim, since the exact percent-encoding is an implementation detail.
                let location = try #require(res.headers.first(name: .location))
                let components = try #require(URLComponents(string: location))
                let items = components.queryItems ?? []
                #expect(components.path == "/app/bookmarks/\(bookmarkID)", "It should redirect to the detail page")
                #expect(items.first { $0.name == "ok" }?.value == "archived", "It should carry the flash")
                #expect(
                    items.first { $0.name == "returnTo" }?.value == "/app?tag=swift",
                    "It should carry returnTo forward so the back link still points at the tag list"
                )
            }
        }
    }

    // MARK: - Add-bookmark page: Referer fallback + tag pre-fill

    @Test("the add-bookmark page falls back to the Referer header when no returnTo param is given")
    func newBookmarkFormFallsBackToReferer() async throws {
        try await withTestApp { app in
            // Given: no explicit returnTo, only a same-origin Referer (what a plain nav link click
            // sends), simulating the global nav "Add" link from a tag-filtered list page. Vapor's
            // in-memory test harness doesn't synthesize a Host header, so it's set explicitly here to
            // match Referer's host, required by the same-origin check.
            var headers = try await app.appWebSession()
            headers.add(name: "Host", value: "stash.example.com")
            headers.add(name: "Referer", value: "http://stash.example.com/app?tag=swift")

            // When
            try await app.testing().test(.GET, "app/bookmarks/new", headers: headers) { res async throws in
                // Then
                #expect(
                    res.body.string.contains(#"href="/app?tag=swift">← Back to bookmarks"#),
                    "It should point the back link at the tag list found in the Referer header"
                )
            }
        }
    }

    @Test("the add-bookmark page ignores a Referer from a different host")
    func newBookmarkFormIgnoresCrossOriginReferer() async throws {
        try await withTestApp { app in
            // Given
            var headers = try await app.appWebSession()
            headers.add(name: "Host", value: "stash.example.com")
            headers.add(name: "Referer", value: "https://evil.example/app?tag=swift")

            // When
            try await app.testing().test(.GET, "app/bookmarks/new", headers: headers) { res async throws in
                // Then
                #expect(
                    res.body.string.contains(#"href="/app">← Back to bookmarks"#),
                    "It should not trust a Referer from a different host, even one shaped like a local path"
                )
            }
        }
    }

    @Test("an explicit returnTo param wins over a differing Referer header")
    func newBookmarkFormPrefersExplicitReturnToOverReferer() async throws {
        try await withTestApp { app in
            // Given
            var headers = try await app.appWebSession()
            headers.add(name: "Referer", value: "http://testserver/app?tag=other")

            // When
            try await app.testing().test(
                .GET, "app/bookmarks/new?returnTo=%2Fapp%3Ftag%3Dswift",
                headers: headers
            ) { res async throws in
                // Then
                #expect(
                    res.body.string.contains(#"href="/app?tag=swift">← Back to bookmarks"#),
                    "It should use the explicit returnTo, not the Referer"
                )
            }
        }
    }

    @Test("with neither returnTo nor Referer, the add-bookmark page falls back to /app")
    func newBookmarkFormFallsBackToAppWithNoContext() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()

            // When
            try await app.testing().test(.GET, "app/bookmarks/new", headers: headers) { res async throws in
                // Then
                #expect(
                    res.body.string.contains(#"href="/app">← Back to bookmarks"#),
                    "It should fall back to /app with no context available"
                )
            }
        }
    }

    @Test("the add-bookmark page pre-fills the tags field from a tag-filtered returnTo/Referer")
    func newBookmarkFormPrefillsTagFromReturnTo() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()

            // When
            try await app.testing().test(
                .GET, "app/bookmarks/new?returnTo=%2Fapp%3Ftag%3Dswift",
                headers: headers
            ) { res async throws in
                // Then
                #expect(
                    res.body.string.contains(#"<input name="tags" value="swift""#),
                    "It should pre-fill the tag the user was browsing"
                )
            }
        }
    }

    @Test("the add-bookmark page does not pre-fill a tag from a Smart View or sentinel returnTo")
    func newBookmarkFormDoesNotPrefillNonTagContext() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()

            // When: a sentinel filter (Untagged/Today/This Week), not a real tag
            try await app.testing().test(
                .GET, "app/bookmarks/new?returnTo=%2Fapp%3Ftag%3D__untagged__",
                headers: headers
            ) { res async throws in
                // Then
                #expect(
                    res.body.string.contains(#"<input name="tags" value=""#),
                    "It should leave the tags field empty for a sentinel filter, not a real tag"
                )
            }

            // When: a Smart View returnTo has no `tag` query item at all
            try await app.testing().test(
                .GET, "app/bookmarks/new?returnTo=%2Fapp%2Fsmart-views%2F00000000-0000-0000-0000-000000000000",
                headers: headers
            ) { res async throws in
                // Then
                #expect(
                    res.body.string.contains(#"<input name="tags" value=""#),
                    "It should leave the tags field empty for a Smart View, which has no single tag"
                )
            }
        }
    }
}
