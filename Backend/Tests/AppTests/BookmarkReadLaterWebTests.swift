// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the "read later" feature in the user-facing web frontend: the add/edit form checkbox,
/// the detail-page "Mark to Read Later" / "Mark as Read" toggle actions, and the `__read_later__`
/// sentinel "To Read" sidebar view.
@Suite("Bookmarks: read later (web frontend)")
struct BookmarkReadLaterWebTests {

    @Test("submitting the add-bookmark form with the read-later checkbox checked marks it")
    func createWithReadLaterChecked() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()

            // When
            try await app.testing().test(
                .POST, "app/bookmarks",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(
                        ["url": "https://example.com", "title": "Example", "action": "save", "readLater": "true"],
                        as: .urlEncodedForm
                    )
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .seeOther, "It should redirect after saving")
                }
            )

            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.isReadLater == true, "It should mark the new bookmark to read later")
        }
    }

    @Test("submitting the add-bookmark form without the checkbox leaves read-later false")
    func createWithoutReadLaterDefaultsFalse() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()

            // When: the checkbox is simply absent from the body, as an unchecked HTML checkbox
            try await app.testing().test(
                .POST, "app/bookmarks",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(
                        ["url": "https://example.com", "title": "Example", "action": "save"],
                        as: .urlEncodedForm
                    )
                },
                afterResponse: { res async throws in
                    #expect(res.status == .seeOther, "It should redirect after saving")
                }
            )

            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.isReadLater == false, "It should default to not marked for read later")
        }
    }

    @Test("editing a bookmark can check or uncheck the read-later field")
    func editTogglesReadLater() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com", isReadLater: false)
            let id = try bookmark.requireID()

            // When: checking it on
            try await app.testing().test(
                .POST, "app/bookmarks/\(id)",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(["title": "Example", "readLater": "true"], as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .seeOther, "It should redirect after saving")
                }
            )

            var updated = try #require(try await Bookmark.find(id, on: app.db))
            #expect(updated.isReadLater == true, "It should mark the bookmark to read later")

            // When: unchecking it (absent from the submitted body)
            try await app.testing().test(
                .POST, "app/bookmarks/\(id)",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(["title": "Example"], as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .seeOther, "It should redirect after saving")
                }
            )

            updated = try #require(try await Bookmark.find(id, on: app.db))
            #expect(updated.isReadLater == false, "It should unmark the bookmark when unchecked")
        }
    }

    @Test("the read-later/mark-read actions toggle the flag and flash a confirmation")
    func toggleActionsSetFlagAndFlash() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let id = try bookmark.requireID()

            // When
            try await app.testing().test(
                .POST, "app/bookmarks/\(id)/read-later",
                headers: headers
            ) { res async throws in
                // Then
                #expect(
                    res.headers.first(name: .location) == "/app/bookmarks/\(id)?ok=read_later",
                    "It should redirect with the read_later flash"
                )
            }
            var updated = try #require(try await Bookmark.find(id, on: app.db))
            #expect(updated.isReadLater == true, "It should mark the bookmark to read later")

            try await app.testing().test(
                .POST, "app/bookmarks/\(id)/mark-read",
                headers: headers
            ) { res async throws in
                #expect(
                    res.headers.first(name: .location) == "/app/bookmarks/\(id)?ok=marked_read",
                    "It should redirect with the marked_read flash"
                )
            }
            updated = try #require(try await Bookmark.find(id, on: app.db))
            #expect(updated.isReadLater == false, "It should unmark the bookmark")
        }
    }

    @Test("the __read_later__ sentinel shows only bookmarks marked to read later as the 'To Read' view")
    func readLaterSentinelFiltersList() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            try await app.makeBookmark(for: user, url: "https://not-yet.com", title: "Not yet", isReadLater: false)
            try await app.makeBookmark(for: user, url: "https://to-read.com", title: "To read me", isReadLater: true)

            // When
            try await app.testing().test(
                .GET, "app?tag=__read_later__",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.body.string.contains("To read me"), "It should list the read-later bookmark")
                #expect(!res.body.string.contains("Not yet"), "It should exclude bookmarks not marked to read later")
                #expect(res.body.string.contains(">To Read<"), "It should show the 'To Read' view label")
            }
        }
    }
}
