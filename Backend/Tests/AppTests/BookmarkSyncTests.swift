// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the offline-sync endpoints: `GET /bookmarks/changes`,
/// `GET /bookmarks/deleted`, and the deletion tombstones that back them.
@Suite("Bookmark sync — changes, deletions, isolation")
struct BookmarkSyncTests {

    // MARK: Static Properties

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: Functions

    @Test("changes?since= returns only bookmarks updated after the timestamp, including archived")
    func changesSince() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            let reference = Date(timeIntervalSince1970: 1_700_000_000)
            let old = try await app.makeBookmark(for: user, url: "https://old.com")
            let recent = try await app.makeBookmark(for: user, url: "https://recent.com", isArchived: true)
            try await setUpdatedAt(reference.addingTimeInterval(-3600), id: old.requireID(), on: app.db)
            try await setUpdatedAt(reference.addingTimeInterval(3600), id: recent.requireID(), on: app.db)

            // When
            let since = Self.iso8601.string(from: reference)
            try await app.testing().test(
                .GET, "api/v1/bookmarks/changes?since=\(since)",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(res.status == .ok, "It should return 200 OK")
                let page = try res.content.decode(ChangesPage<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://recent.com"],
                    "It should return only bookmarks updated after `since`, including archived ones"
                )
            }
        }
    }

    @Test("changes with no since returns all bookmarks, archived included")
    func changesNoSince() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://a.com")
            try await app.makeBookmark(for: user, url: "https://b.com", isArchived: true)

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks/changes",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(ChangesPage<BookmarkResponse>.self)
                #expect(
                    Set(page.items.map(\.url)) == ["https://a.com", "https://b.com"],
                    "It should return every bookmark when `since` is omitted"
                )
            }
        }
    }

    @Test("DELETE /bookmarks/:id records a tombstone")
    func deleteRecordsTombstone() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let bookmark = try await app.makeBookmark(for: user, url: "https://gone.com")
            let bookmarkID = try bookmark.requireID()

            // When
            try await app.testing().test(
                .DELETE, "api/v1/bookmarks/\(bookmarkID)",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                #expect(res.status == .noContent, "It should return 204 No Content")
            }

            // Then
            try await app.testing().test(
                .GET, "api/v1/bookmarks/deleted",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let tombstones = try res.content.decode([DeletedBookmarkResponse].self)
                #expect(
                    tombstones.map(\.id) == [bookmarkID],
                    "It should record a tombstone carrying the deleted bookmark's ID"
                )
            }
        }
    }

    @Test("deleted?since= returns only tombstones after the timestamp")
    func deletedSince() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let userID = try user.requireID()

            let reference = Date(timeIntervalSince1970: 1_700_000_000)
            let oldID = UUID()
            let recentID = UUID()
            try await makeTombstone(
                bookmarkID: oldID, userID: userID, at: reference.addingTimeInterval(-3600), on: app.db
            )
            try await makeTombstone(
                bookmarkID: recentID, userID: userID, at: reference.addingTimeInterval(3600), on: app.db
            )

            // When
            let since = Self.iso8601.string(from: reference)
            try await app.testing().test(
                .GET, "api/v1/bookmarks/deleted?since=\(since)",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let tombstones = try res.content.decode([DeletedBookmarkResponse].self)
                #expect(
                    tombstones.map(\.id) == [recentID],
                    "It should return only tombstones recorded after `since`"
                )
            }
        }
    }

    @Test("deleted with no since returns all tombstones")
    func deletedNoSince() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let userID = try user.requireID()
            let first = UUID()
            let second = UUID()
            try await makeTombstone(bookmarkID: first, userID: userID, at: Date(), on: app.db)
            try await makeTombstone(bookmarkID: second, userID: userID, at: Date(), on: app.db)

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks/deleted",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let tombstones = try res.content.decode([DeletedBookmarkResponse].self)
                #expect(
                    Set(tombstones.map(\.id)) == [first, second],
                    "It should return every tombstone when `since` is omitted"
                )
            }
        }
    }

    @Test("a user cannot see another user's changes or tombstones")
    func userIsolation() async throws {
        try await withTestApp { app in
            // Given
            let owner = try await app.makeUser(username: "owner")
            let other = try await app.makeUser(username: "other")
            let otherPair = try await app.login(username: "other", password: "correct-horse-battery")

            try await app.makeBookmark(for: owner, url: "https://owner.com")
            try await makeTombstone(
                bookmarkID: UUID(), userID: owner.requireID(), at: Date(), on: app.db
            )

            // When / Then — changes
            try await app.testing().test(
                .GET, "api/v1/bookmarks/changes",
                headers: bearer(otherPair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(ChangesPage<BookmarkResponse>.self)
                #expect(page.items.isEmpty, "It should not surface another user's changed bookmarks")
            }

            // When / Then — tombstones
            try await app.testing().test(
                .GET, "api/v1/bookmarks/deleted",
                headers: bearer(otherPair.accessToken)
            ) { res async throws in
                let tombstones = try res.content.decode([DeletedBookmarkResponse].self)
                #expect(tombstones.isEmpty, "It should not surface another user's tombstones")
            }
        }
    }

    @Test("a web single delete records a tombstone")
    func webDeleteRecordsTombstone() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let session = try await webSession(app, username: "otavio", password: "correct-horse-battery")
            let bookmark = try await app.makeBookmark(for: user, url: "https://web-gone.com")
            let bookmarkID = try bookmark.requireID()

            // When
            try await app.testing().test(
                .POST, "app/bookmarks/\(bookmarkID)/delete",
                headers: session
            ) { res async throws in
                #expect(res.status == .seeOther, "It should redirect after the web delete")
            }

            // Then
            try await app.testing().test(
                .GET, "api/v1/bookmarks/deleted",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let tombstones = try res.content.decode([DeletedBookmarkResponse].self)
                #expect(
                    tombstones.map(\.id) == [bookmarkID],
                    "It should record a tombstone for the web-deleted bookmark"
                )
            }
        }
    }

    @Test("a web bulk delete records a tombstone for every bookmark")
    func webBulkDeleteRecordsTombstones() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let session = try await webSession(app, username: "otavio", password: "correct-horse-battery")
            let first = try await app.makeBookmark(for: user, url: "https://one.com").requireID()
            let second = try await app.makeBookmark(for: user, url: "https://two.com").requireID()
            let third = try await app.makeBookmark(for: user, url: "https://three.com").requireID()

            // When
            try await app.testing().test(
                .POST, "app/settings/delete-all-bookmarks",
                headers: session,
                beforeRequest: { req in
                    try req.content.encode(DeleteAllBookmarksForm(confirm: "delete all"), as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .seeOther, "It should redirect after the bulk delete")
                }
            )

            // Then
            try await app.testing().test(
                .GET, "api/v1/bookmarks/deleted",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let tombstones = try res.content.decode([DeletedBookmarkResponse].self)
                #expect(
                    Set(tombstones.map(\.id)) == [first, second, third],
                    "It should record a tombstone for every bulk-deleted bookmark"
                )
            }
        }
    }

    @Test("changes returns bookmarks sorted ascending by updatedAt")
    func changesSortedAscending() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            let reference = Date(timeIntervalSince1970: 1_700_000_000)
            let oldest = try await app.makeBookmark(for: user, url: "https://oldest.com")
            let middle = try await app.makeBookmark(for: user, url: "https://middle.com")
            let newest = try await app.makeBookmark(for: user, url: "https://newest.com")
            try await setUpdatedAt(reference.addingTimeInterval(-20), id: oldest.requireID(), on: app.db)
            try await setUpdatedAt(reference.addingTimeInterval(-10), id: middle.requireID(), on: app.db)
            try await setUpdatedAt(reference, id: newest.requireID(), on: app.db)

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks/changes",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(ChangesPage<BookmarkResponse>.self)
                let timestamps = page.items.map(\.updatedAt)
                #expect(
                    timestamps == timestamps.sorted(),
                    "It should return changes oldest-first for stable cursor pagination"
                )
                #expect(
                    page.items.map(\.url) == ["https://oldest.com", "https://middle.com", "https://newest.com"],
                    "It should order the bookmarks by ascending updatedAt"
                )
            }
        }
    }

    @Test("changes clamps per to the 1...500 range")
    func changesClampsPer() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            try await app.makeBookmark(for: user, url: "https://a.com")
            try await app.makeBookmark(for: user, url: "https://b.com")

            // When / Then — above the ceiling: no error, both returned, no further pages
            try await app.testing().test(
                .GET, "api/v1/bookmarks/changes?per=1000",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                #expect(res.status == .ok, "It should accept an oversized per without erroring")
                let page = try res.content.decode(ChangesPage<BookmarkResponse>.self)
                #expect(page.items.count == 2, "It should return both bookmarks under the clamped ceiling")
                #expect(page.hasMore == false, "It should report no further pages")
            }

            // When / Then — below the floor: per clamps to 1, so only one item and more remain
            try await app.testing().test(
                .GET, "api/v1/bookmarks/changes?per=0",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                #expect(res.status == .ok, "It should accept a zero per without erroring")
                let page = try res.content.decode(ChangesPage<BookmarkResponse>.self)
                #expect(page.items.count == 1, "It should clamp per to a minimum of 1, returning one item")
                #expect(page.hasMore == true, "It should report a further page when per is clamped to 1")
            }
        }
    }

    @Test("changes with a malformed since returns 422")
    func changesMalformedSince() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .GET, "api/v1/bookmarks/changes?since=not-a-date",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(res.status == .unprocessableEntity, "It should reject a non-ISO-8601 since")
                let err = try res.content.decode(TestError.self)
                #expect(err.code == "validation_failed", "It should return the validation_failed error code")
            }
        }
    }

    @Test("changes keyset pagination is stable under a concurrent edit")
    func changesKeysetStable() async throws {
        try await withTestApp { app in
            // Given — three bookmarks at t1 < t2 < t3
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            let reference = Date(timeIntervalSince1970: 1_700_000_000)
            let first = try await app.makeBookmark(for: user, url: "https://t1.com")
            let second = try await app.makeBookmark(for: user, url: "https://t2.com")
            let third = try await app.makeBookmark(for: user, url: "https://t3.com")
            try await setUpdatedAt(reference.addingTimeInterval(-30), id: first.requireID(), on: app.db)
            try await setUpdatedAt(reference.addingTimeInterval(-20), id: second.requireID(), on: app.db)
            try await setUpdatedAt(reference.addingTimeInterval(-10), id: third.requireID(), on: app.db)

            // When — page 1 (per=2) returns the two oldest and a keyset cursor
            var nextAfterUpdatedAt: String?
            var nextAfterId: UUID?
            try await app.testing().test(
                .GET, "api/v1/bookmarks/changes?per=2",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(ChangesPage<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://t1.com", "https://t2.com"],
                    "Page 1 should hold the two oldest bookmarks"
                )
                #expect(page.hasMore, "There should be a further page")
                nextAfterUpdatedAt = page.nextAfterUpdatedAt
                nextAfterId = page.nextAfterId
            }

            // A concurrent edit bumps the already-paged t1 to t4 (now the newest)
            try await setUpdatedAt(reference.addingTimeInterval(60), id: first.requireID(), on: app.db)

            // Then — page 2, continuing from the page-1 cursor, contains t3 AND the bumped t1; nothing skipped
            let afterUpdatedAt = try #require(nextAfterUpdatedAt)
            let afterId = try #require(nextAfterId)
            try await app.testing().test(
                .GET, "api/v1/bookmarks/changes?per=2&afterUpdatedAt=\(afterUpdatedAt)&afterId=\(afterId)",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let page = try res.content.decode(ChangesPage<BookmarkResponse>.self)
                #expect(
                    Set(page.items.map(\.url)) == ["https://t3.com", "https://t1.com"],
                    "Page 2 should contain the untouched t3 and the bumped t1 — the keyset skips nothing"
                )
            }
        }
    }

    @Test("create honors isArchived")
    func createArchived() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            var createdID: UUID?
            try await app.testing().test(
                .POST, "api/v1/bookmarks",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(CreateBookmarkInput(
                        url: "https://archived.com",
                        title: "Archived",
                        description: nil,
                        tags: nil,
                        fetchMetadata: false,
                        isArchived: true,
                        isReadLater: nil
                    ))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .created, "It should return 201 Created")
                    let bookmark = try res.content.decode(BookmarkResponse.self)
                    #expect(bookmark.isArchived == true, "It should create the bookmark archived")
                    createdID = bookmark.id
                }
            )

            let id = try #require(createdID)
            try await app.testing().test(
                .GET, "api/v1/bookmarks/\(id)",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let bookmark = try res.content.decode(BookmarkResponse.self)
                #expect(bookmark.isArchived == true, "It should persist the archived state")
            }
        }
    }

    // MARK: - Helpers

    private func webSession(
        _ app: Application,
        username: String,
        password: String
    ) async throws -> HTTPHeaders {
        var cookie: String?
        try await app.testing().test(
            .POST, "app/login",
            beforeRequest: { req in
                try req.content.encode(
                    LoginForm(username: username, password: password, totpCode: nil),
                    as: .urlEncodedForm
                )
            },
            afterResponse: { res async throws in
                cookie = res.headers.setCookie?["stash_session"]?.string
            }
        )
        guard let cookie else {
            throw Abort(.internalServerError, reason: "app web login did not set a session cookie")
        }

        return ["Cookie": "stash_session=\(cookie)"]
    }

    private func setUpdatedAt(_ date: Date, id: UUID, on db: Database) async throws {
        try await Bookmark.query(on: db)
            .filter(\.$id == id)
            .set(\.$updatedAt, to: date)
            .update()
    }

    private func makeTombstone(
        bookmarkID: UUID,
        userID: UUID,
        at date: Date,
        on db: Database
    ) async throws {
        let tombstone = DeletedBookmark(userID: userID, bookmarkID: bookmarkID)
        try await tombstone.save(on: db)
        try await DeletedBookmark.query(on: db)
            .filter(\.$id == tombstone.requireID())
            .set(\.$deletedAt, to: date)
            .update()
    }
}
