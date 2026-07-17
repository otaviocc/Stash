// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies `AnyboxImporter`: the flat top-level JSON array shape, Anybox's `[[namespace, value]]`
/// tag pairs, date parsing, missing-field handling, duplicate-URL updates, and parse failures.
@Suite("Anybox import")
struct AnyboxImportTests {

    // MARK: - Tags

    @Test("importing Anybox namespace/value tag pairs produces hierarchical tags")
    func importsNamespaceValueTagPairs() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let json = """
            [
              {
                "url": "https://example.com",
                "title": "Example",
                "tags": [["topic", "swift"], ["status", "reading"]],
                "dateAdded": "2026-01-01T00:00:00Z"
              }
            ]
            """
            let data = Data(json.utf8)

            // When
            let result = try await AnyboxImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.imported == 1, "It should import the single record")
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.tags == ["topic/swift", "status/reading"], "It should join pairs with a slash")
        }
    }

    @Test("importing plain string tags is accepted as a fallback shape")
    func importsPlainStringTags() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let json = """
            [{ "url": "https://example.com", "title": "Example", "tags": ["swift", "ios"] }]
            """
            let data = Data(json.utf8)

            // When
            let result = try await AnyboxImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.imported == 1, "It should import the record")
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.tags == ["swift", "ios"], "It should keep plain tags")
        }
    }

    // MARK: - Dates

    @Test("importing an ISO-8601 dateAdded sets createdAt")
    func importsISODate() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let json = """
            [{ "url": "https://example.com", "title": "Example", "dateAdded": "2020-06-15T12:00:00Z" }]
            """
            let data = Data(json.utf8)

            // When
            _ = try await AnyboxImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            let expected = ISO8601DateFormatter().date(from: "2020-06-15T12:00:00Z")
            #expect(bookmark.createdAt == expected, "It should parse the ISO date into createdAt")
        }
    }

    @Test("importing a numeric Unix date_added sets createdAt")
    func importsUnixDate() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let json = """
            [{ "url": "https://example.com", "title": "Example", "date_added": 1592222400 }]
            """
            let data = Data(json.utf8)

            // When
            _ = try await AnyboxImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(
                bookmark.createdAt == Date(timeIntervalSince1970: 1_592_222_400),
                "It should parse the Unix timestamp into createdAt"
            )
        }
    }

    // MARK: - Missing fields

    @Test("importing a record without a title stores an empty title")
    func importsMissingTitleAsEmpty() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data(#"[{ "url": "https://example.com" }]"#.utf8)

            // When
            _ = try await AnyboxImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.title == "", "It should default a missing title to an empty string")
        }
    }

    @Test("importing a record with a missing URL skips it with an error")
    func skipsRecordWithoutURL() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data(#"[{ "title": "No URL" }, { "url": "https://ok.com" }]"#.utf8)

            // When
            let result = try await AnyboxImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.imported == 1, "It should import the valid record")
            #expect(result.skipped == 1, "It should skip the record without a URL")
            #expect(result.errors.count == 1, "It should report one error")
        }
    }

    @Test("importing a record with an invalid URL skips it")
    func skipsRecordWithInvalidURL() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data(#"[{ "url": "not-a-url", "title": "Bad" }]"#.utf8)

            // When
            let result = try await AnyboxImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.skipped == 1, "It should skip the invalid URL")
            #expect(result.imported == 0, "It should import nothing")
        }
    }

    // MARK: - Duplicates

    @Test("importing a duplicate URL updates the existing bookmark in place")
    func updatesDuplicateURL() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let original = try await app.makeBookmark(
                for: user, url: "https://example.com", title: "Old", tags: ["old"]
            )
            let originalCreatedAt = original.createdAt
            let data = Data(
                #"[{ "url": "https://example.com", "title": "New", "tags": ["new"] }]"#.utf8
            )

            // When
            let result = try await AnyboxImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.updated == 1, "It should count the record as updated")
            #expect(result.imported == 0, "It should not count it as imported")
            let bookmark = try #require(try await Bookmark.find(original.requireID(), on: app.db))
            #expect(bookmark.title == "New", "It should overwrite the title")
            #expect(bookmark.tags == ["new"], "It should overwrite the tags")
            #expect(bookmark.createdAt == originalCreatedAt, "It should preserve the original createdAt")
        }
    }

    // MARK: - Counts & failures

    @Test("importing increments the user's bookmark count by the imported total")
    func incrementsBookmarkCount() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data(
                #"[{ "url": "https://a.com" }, { "url": "https://b.com" }]"#.utf8
            )

            // When
            _ = try await AnyboxImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            let refreshed = try #require(try await User.find(user.requireID(), on: app.db))
            #expect(refreshed.bookmarkCount == 2, "It should add the imported count to bookmarkCount")
        }
    }

    @Test("importing a payload that is not a JSON array throws invalidFormat")
    func throwsOnMalformedPayload() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data(#"{ "bookmarks": [] }"#.utf8)

            // When / Then
            await #expect(throws: ImportError.self, "It should reject a non-array payload") {
                _ = try await AnyboxImporter().import(from: data, for: user.requireID(), on: app.db)
            }
        }
    }
}
