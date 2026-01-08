import Fluent
import Testing
import Vapor
import VaporTesting

@testable import App

@Suite("Bookmarks — CRUD, duplicates, search, isolation")
struct BookmarkTests {
    // Helper: a create body that never triggers a network metadata fetch.
    private func createBody(
        url: String,
        title: String? = "Example",
        description: String? = nil,
        tags: [String]? = nil
    ) -> CreateBookmarkInput {
        CreateBookmarkInput(
            url: url, title: title, description: description, tags: tags, fetchMetadata: false
        )
    }

    @Test("create returns 201 and the bookmark, and increments bookmarkCount")
    func create() async throws {
        try await withTestApp { app in
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .POST, "api/v1/bookmarks",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(createBody(url: "https://example.com", title: "Example", tags: ["Swift", "swift/vapor"]))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .created)
                    let bookmark = try res.content.decode(BookmarkResponse.self)
                    #expect(bookmark.url == "https://example.com")
                    #expect(bookmark.title == "Example")
                    #expect(bookmark.tags == ["swift", "swift/vapor"]) // normalised + lowercased
                    #expect(bookmark.isArchived == false)
                }
            )

            try await app.testing().test(
                .GET, "api/v1/me",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in
                    let me = try res.content.decode(UserResponse.self)
                    #expect(me.bookmarkCount == 1)
                }
            )
        }
    }

    @Test("create with an invalid URL returns 422")
    func createInvalidURL() async throws {
        try await withTestApp { app in
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .POST, "api/v1/bookmarks",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(createBody(url: "not-a-url"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unprocessableEntity)
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "validation_failed")
                }
            )
        }
    }

    @Test("duplicate URL returns 409 with the existing bookmark ID")
    func duplicateURL() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let existing = try await app.makeBookmark(for: user, url: "https://dupe.com")

            try await app.testing().test(
                .POST, "api/v1/bookmarks",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(createBody(url: "https://dupe.com"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .conflict)
                    let err = try res.content.decode(TestDuplicateError.self)
                    #expect(err.code == "duplicate_url")
                    #expect(err.existingID == existing.id)
                }
            )
        }
    }

    @Test("get, update, and delete a bookmark")
    func crud() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let bookmark = try await app.makeBookmark(for: user, url: "https://a.com", title: "A", tags: ["x"])
            let id = try bookmark.requireID()

            try await app.testing().test(
                .GET, "api/v1/bookmarks/\(id)",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    #expect(try res.content.decode(BookmarkResponse.self).title == "A")
                }
            )

            try await app.testing().test(
                .PUT, "api/v1/bookmarks/\(id)",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(UpdateBookmarkInput(
                        url: nil, title: "A updated", description: "desc", tags: ["y", "y/z"], isArchived: true
                    ))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let updated = try res.content.decode(BookmarkResponse.self)
                    #expect(updated.title == "A updated")
                    #expect(updated.description == "desc")
                    #expect(updated.tags == ["y", "y/z"])
                    #expect(updated.isArchived == true)
                }
            )

            try await app.testing().test(
                .DELETE, "api/v1/bookmarks/\(id)",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in #expect(res.status == .noContent) }
            )

            try await app.testing().test(
                .GET, "api/v1/bookmarks/\(id)",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in #expect(res.status == .notFound) }
            )
        }
    }

    @Test("updating to an existing URL returns 409")
    func updateToDuplicate() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            _ = try await app.makeBookmark(for: user, url: "https://one.com")
            let second = try await app.makeBookmark(for: user, url: "https://two.com")

            try await app.testing().test(
                .PUT, "api/v1/bookmarks/\(try second.requireID())",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(UpdateBookmarkInput(
                        url: "https://one.com", title: nil, description: nil, tags: nil, isArchived: nil
                    ))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .conflict)
                    #expect(try res.content.decode(TestDuplicateError.self).code == "duplicate_url")
                }
            )
        }
    }

    @Test("a user cannot access another user's bookmark (404) and lists are isolated")
    func userIsolation() async throws {
        try await withTestApp { app in
            let alice = try await app.makeUser(username: "alice", password: "alice-password-1234")
            try await app.makeUser(username: "bob", password: "bob-password-12345")
            let aliceBookmark = try await app.makeBookmark(for: alice, url: "https://alice-only.com")

            let bob = try await app.login(username: "bob", password: "bob-password-12345")

            // Bob cannot GET Alice's bookmark.
            try await app.testing().test(
                .GET, "api/v1/bookmarks/\(try aliceBookmark.requireID())",
                headers: bearer(bob.accessToken),
                afterResponse: { res async throws in #expect(res.status == .notFound) }
            )

            // Bob's list is empty.
            try await app.testing().test(
                .GET, "api/v1/bookmarks",
                headers: bearer(bob.accessToken),
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let page = try res.content.decode(Page<BookmarkResponse>.self)
                    #expect(page.items.isEmpty)
                    #expect(page.metadata.total == 0)
                }
            )
        }
    }

    @Test("list pagination respects page/per and reports total")
    func pagination() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            for i in 0..<25 {
                try await app.makeBookmark(for: user, url: "https://site\(i).com")
            }

            try await app.testing().test(
                .GET, "api/v1/bookmarks?page=1&per=10",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in
                    let page = try res.content.decode(Page<BookmarkResponse>.self)
                    #expect(page.items.count == 10)
                    #expect(page.metadata.total == 25)
                    #expect(page.metadata.per == 10)
                    #expect(page.metadata.page == 1)
                }
            )

            try await app.testing().test(
                .GET, "api/v1/bookmarks?page=3&per=10",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in
                    let page = try res.content.decode(Page<BookmarkResponse>.self)
                    #expect(page.items.count == 5)
                }
            )
        }
    }

    @Test("per is clamped to a maximum of 100")
    func perClamped() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://only.com")

            try await app.testing().test(
                .GET, "api/v1/bookmarks?per=9999",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in
                    #expect(try res.content.decode(Page<BookmarkResponse>.self).metadata.per == 100)
                }
            )
        }
    }

    @Test("full-text search matches url, title, and description")
    func fullTextSearch() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://vapor.codes", title: "Vapor framework")
            try await app.makeBookmark(for: user, url: "https://apple.com", title: "Apple", description: "Makes the iPhone")
            try await app.makeBookmark(for: user, url: "https://example.com", title: "Nothing relevant")

            try await app.testing().test(
                .GET, "api/v1/bookmarks?q=vapor",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in
                    let page = try res.content.decode(Page<BookmarkResponse>.self)
                    #expect(page.items.count == 1)
                    #expect(page.items.first?.url == "https://vapor.codes")
                }
            )

            try await app.testing().test(
                .GET, "api/v1/bookmarks?q=iPhone",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in
                    let page = try res.content.decode(Page<BookmarkResponse>.self)
                    #expect(page.items.count == 1)
                    #expect(page.items.first?.url == "https://apple.com")
                }
            )
        }
    }

    @Test("tag filter is a hierarchical prefix match")
    func tagPrefixFilter() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://1.com", tags: ["swift"])
            try await app.makeBookmark(for: user, url: "https://2.com", tags: ["swift/vapor"])
            try await app.makeBookmark(for: user, url: "https://3.com", tags: ["swiftui"])
            try await app.makeBookmark(for: user, url: "https://4.com", tags: ["music/jazz"])

            try await app.testing().test(
                .GET, "api/v1/bookmarks?tag=swift",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in
                    let page = try res.content.decode(Page<BookmarkResponse>.self)
                    let urls = Set(page.items.map(\.url))
                    // swift and swift/vapor match; swiftui and music/jazz do NOT.
                    #expect(urls == ["https://1.com", "https://2.com"])
                }
            )
        }
    }

    @Test("archived filter defaults to false and can be toggled")
    func archivedFilter() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://active.com", isArchived: false)
            try await app.makeBookmark(for: user, url: "https://archived.com", isArchived: true)

            try await app.testing().test(
                .GET, "api/v1/bookmarks",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in
                    let page = try res.content.decode(Page<BookmarkResponse>.self)
                    #expect(page.items.map(\.url) == ["https://active.com"])
                }
            )

            try await app.testing().test(
                .GET, "api/v1/bookmarks?archived=true",
                headers: bearer(pair.accessToken),
                afterResponse: { res async throws in
                    let page = try res.content.decode(Page<BookmarkResponse>.self)
                    #expect(page.items.map(\.url) == ["https://archived.com"])
                }
            )
        }
    }

    @Test("creating a bookmark requires authentication")
    func createRequiresAuth() async throws {
        try await withTestApp { app in
            try await app.testing().test(
                .POST, "api/v1/bookmarks",
                beforeRequest: { req in try req.content.encode(createBody(url: "https://x.com")) },
                afterResponse: { res async throws in #expect(res.status == .unauthorized) }
            )
        }
    }
}
