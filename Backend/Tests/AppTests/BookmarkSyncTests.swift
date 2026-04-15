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
                let page = try res.content.decode(Page<BookmarkResponse>.self)
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
                let page = try res.content.decode(Page<BookmarkResponse>.self)
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
                let page = try res.content.decode(Page<BookmarkResponse>.self)
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

    // MARK: - Helpers

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
