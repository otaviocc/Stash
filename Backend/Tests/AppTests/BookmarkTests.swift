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

import Fluent
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies bookmark CRUD, duplicate handling, search, pagination, and per-user isolation.
@Suite("Bookmarks — CRUD, duplicates, search, isolation")
struct BookmarkTests {

    @Test("create returns 201 and the bookmark, and increments bookmarkCount")
    func create() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/bookmarks",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(createBody(
                        url: "https://example.com",
                        title: "Example",
                        tags: ["Swift", "swift/vapor"]
                    ))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .created, "It should return 201 Created")
                    let bookmark = try res.content.decode(BookmarkResponse.self)
                    #expect(bookmark.url == "https://example.com", "It should store the submitted URL")
                    #expect(bookmark.title == "Example", "It should store the submitted title")
                    #expect(bookmark.tags == ["swift", "swift/vapor"], "It should normalize and lowercase the tags")
                    #expect(bookmark.isArchived == false, "It should create the bookmark unarchived")
                }
            )

            try await app.testing().test(
                .GET, "api/v1/me",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let me = try res.content.decode(UserResponse.self)
                #expect(me.bookmarkCount == 1, "It should increment the user's bookmark count")
            }
        }
    }

    @Test("create with an invalid URL returns 422")
    func createInvalidURL() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/bookmarks",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(createBody(url: "not-a-url"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unprocessableEntity, "It should return 422 Unprocessable Entity")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "validation_failed", "It should return the validation_failed error code")
                }
            )
        }
    }

    @Test("duplicate URL returns 409 with the existing bookmark ID")
    func duplicateURL() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let existing = try await app.makeBookmark(for: user, url: "https://dupe.com")

            // When
            try await app.testing().test(
                .POST, "api/v1/bookmarks",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(createBody(url: "https://dupe.com"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .conflict, "It should return 409 Conflict")
                    let err = try res.content.decode(TestDuplicateError.self)
                    #expect(err.code == "duplicate_url", "It should return the duplicate_url error code")
                    #expect(err.existingID == existing.id, "It should report the ID of the existing bookmark")
                }
            )
        }
    }

    @Test("get, update, and delete a bookmark")
    func crud() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let bookmark = try await app.makeBookmark(for: user, url: "https://a.com", title: "A", tags: ["x"])
            let id = try bookmark.requireID()

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks/\(id)",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(res.status == .ok, "It should return 200 OK when fetching the bookmark")
                #expect(
                    try res.content.decode(BookmarkResponse.self).title == "A",
                    "It should return the bookmark's title"
                )
            }

            try await app.testing().test(
                .PUT, "api/v1/bookmarks/\(id)",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(UpdateBookmarkInput(
                        url: nil, title: "A updated", description: "desc", tags: ["y", "y/z"], isArchived: true
                    ))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok, "It should return 200 OK when updating the bookmark")
                    let updated = try res.content.decode(BookmarkResponse.self)
                    #expect(updated.title == "A updated", "It should update the title")
                    #expect(updated.description == "desc", "It should update the description")
                    #expect(updated.tags == ["y", "y/z"], "It should update the tags")
                    #expect(updated.isArchived == true, "It should update the archived flag")
                }
            )

            try await app.testing().test(
                .DELETE, "api/v1/bookmarks/\(id)",
                headers: bearer(pair.accessToken)
            ) { res async throws in #expect(
                res.status == .noContent,
                "It should return 204 No Content when deleting the bookmark"
            ) }

            try await app.testing().test(
                .GET, "api/v1/bookmarks/\(id)",
                headers: bearer(pair.accessToken)
            ) { res async throws in #expect(res.status == .notFound, "It should return 404 for the deleted bookmark") }
        }
    }

    @Test("updating to an existing URL returns 409")
    func updateToDuplicate() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            _ = try await app.makeBookmark(for: user, url: "https://one.com")
            let second = try await app.makeBookmark(for: user, url: "https://two.com")

            // When
            try await app.testing().test(
                .PUT, "api/v1/bookmarks/\(second.requireID())",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(UpdateBookmarkInput(
                        url: "https://one.com", title: nil, description: nil, tags: nil, isArchived: nil
                    ))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .conflict, "It should return 409 Conflict")
                    #expect(
                        try res.content.decode(TestDuplicateError.self).code == "duplicate_url",
                        "It should return the duplicate_url error code"
                    )
                }
            )
        }
    }

    @Test("a user cannot access another user's bookmark (404) and lists are isolated")
    func userIsolation() async throws {
        try await withTestApp { app in
            // Given
            let alice = try await app.makeUser(username: "alice", password: "alice-password-1234")
            try await app.makeUser(username: "bob", password: "bob-password-12345")
            let aliceBookmark = try await app.makeBookmark(for: alice, url: "https://alice-only.com")

            let bob = try await app.login(username: "bob", password: "bob-password-12345")

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks/\(aliceBookmark.requireID())",
                headers: bearer(bob.accessToken)
            ) { res async throws in #expect(
                res.status == .notFound,
                "It should hide another user's bookmark behind a 404"
            ) }

            // Then
            try await app.testing().test(
                .GET, "api/v1/bookmarks",
                headers: bearer(bob.accessToken)
            ) { res async throws in
                #expect(res.status == .ok, "It should return 200 OK")
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(page.items.isEmpty, "It should not include another user's bookmarks in the list")
                #expect(page.metadata.total == 0, "It should report a total of zero for the requesting user")
            }
        }
    }

    @Test("list pagination respects page/per and reports total")
    func pagination() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            for i in 0..<25 {
                try await app.makeBookmark(for: user, url: "https://site\(i).com")
            }

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks?page=1&per=10",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(page.items.count == 10, "It should return one page of items")
                #expect(page.metadata.total == 25, "It should report the total number of bookmarks")
                #expect(page.metadata.per == 10, "It should echo the requested page size")
                #expect(page.metadata.page == 1, "It should echo the requested page number")
            }

            try await app.testing().test(
                .GET, "api/v1/bookmarks?page=3&per=10",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(page.items.count == 5, "It should return the remaining items on the last page")
            }
        }
    }

    @Test("per is clamped to a maximum of 100")
    func perClamped() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://only.com")

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks?per=9999",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(
                    try res.content.decode(Page<BookmarkResponse>.self).metadata.per == 100,
                    "It should clamp the page size to a maximum of 100"
                )
            }
        }
    }

    @Test("full-text search matches url, title, and description case-insensitively")
    func fullTextSearch() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://vapor.codes", title: "Vapor framework")
            try await app.makeBookmark(
                for: user,
                url: "https://apple.com",
                title: "Apple",
                description: "Makes the iPhone"
            )
            try await app.makeBookmark(for: user, url: "https://example.com", title: "Nothing relevant")

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks?q=vapor",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(page.items.count == 1, "It should match a single bookmark by title")
                #expect(
                    page.items.first?.url == "https://vapor.codes",
                    "It should return the bookmark matched on title"
                )
            }

            try await app.testing().test(
                .GET, "api/v1/bookmarks?q=iPhone",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(page.items.count == 1, "It should match a single bookmark by description")
                #expect(
                    page.items.first?.url == "https://apple.com",
                    "It should return the bookmark matched on description"
                )
            }

            try await app.testing().test(
                .GET, "api/v1/bookmarks?q=VAPOR",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.first?.url == "https://vapor.codes",
                    "It should match a mixed-case title from an uppercase query"
                )
            }

            try await app.testing().test(
                .GET, "api/v1/bookmarks?q=iphone",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.first?.url == "https://apple.com",
                    "It should match a mixed-case description from a lowercase query"
                )
            }
        }
    }

    @Test("tag filter is a hierarchical prefix match")
    func tagPrefixFilter() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://1.com", tags: ["swift"])
            try await app.makeBookmark(for: user, url: "https://2.com", tags: ["swift/vapor"])
            try await app.makeBookmark(for: user, url: "https://3.com", tags: ["swiftui"])
            try await app.makeBookmark(for: user, url: "https://4.com", tags: ["music/jazz"])

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks?tag=swift",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                let urls = Set(page.items.map(\.url))
                #expect(
                    urls == ["https://1.com", "https://2.com"],
                    "It should match the exact tag and its descendants but not unrelated tags"
                )
            }
        }
    }

    @Test("the __untagged__ sentinel filters to bookmarks with no tags")
    func untaggedFilter() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://tagged.com", tags: ["swift"])
            try await app.makeBookmark(for: user, url: "https://untagged.com", tags: [])

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks?tag=__untagged__",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://untagged.com"],
                    "It should return only bookmarks that have no tags"
                )
            }
        }
    }

    @Test("the __today__ and __this_week__ sentinels filter by recency")
    func recencyFilters() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://recent.com")
            let old = try await app.makeBookmark(for: user, url: "https://old.com")
            old.createdAt = Date(timeIntervalSinceNow: -10 * 24 * 60 * 60)
            try await old.save(on: app.db)

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks?tag=__today__",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://recent.com"],
                    "It should return only bookmarks created since the start of today"
                )
            }

            try await app.testing().test(
                .GET, "api/v1/bookmarks?tag=__this_week__",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://recent.com"],
                    "It should return only bookmarks created since the start of this week"
                )
            }
        }
    }

    @Test("archived filter defaults to false and can be toggled")
    func archivedFilter() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://active.com", isArchived: false)
            try await app.makeBookmark(for: user, url: "https://archived.com", isArchived: true)

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://active.com"],
                    "It should return only unarchived bookmarks by default"
                )
            }

            try await app.testing().test(
                .GET, "api/v1/bookmarks?archived=true",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://archived.com"],
                    "It should return only archived bookmarks when archived=true"
                )
            }
        }
    }

    @Test("creating a bookmark requires authentication")
    func createRequiresAuth() async throws {
        try await withTestApp { app in
            // Given — no setup required

            // When
            try await app.testing().test(
                .POST, "api/v1/bookmarks",
                beforeRequest: { req in try req.content.encode(createBody(url: "https://x.com")) },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unauthorized, "It should reject unauthenticated bookmark creation")
                }
            )
        }
    }

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
}
