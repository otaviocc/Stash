// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies `PinboardJSONImporter`: Pinboard's Delicious-legacy field names, space-separated
/// tags, `toread` mapping to `isReadLater`, `shared` being dropped, duplicate-URL updates, and
/// parse failures.
@Suite("Pinboard JSON import")
struct PinboardJSONImportTests {

    // MARK: - Field mapping

    @Test("importing a Pinboard record maps href/description/extended to url/title/description")
    func mapsFields() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let json = """
            [{
              "href": "https://www.weather.com/",
              "description": "weather.com",
              "extended": "Local forecasts",
              "meta": "abc123",
              "hash": "def456",
              "time": "2005-11-29T20:30:47Z",
              "shared": "yes",
              "toread": "no",
              "tags": "weather reference"
            }]
            """
            let data = Data(json.utf8)

            // When
            let result = try await PinboardJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.imported == 1, "It should import the single record")
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.url == "https://www.weather.com/", "It should map href to url")
            #expect(bookmark.title == "weather.com", "It should map description to title")
            #expect(bookmark.$description.value == "Local forecasts", "It should map extended to description")
            #expect(bookmark.tags == ["weather", "reference"], "It should split space-separated tags")
            #expect(bookmark.isReadLater == false, "It should map toread:no to isReadLater:false")
            #expect(
                bookmark.createdAt == ISO8601DateFormatter().date(from: "2005-11-29T20:30:47Z"),
                "It should parse the ISO-8601 time field"
            )
        }
    }

    @Test("importing toread:yes maps to isReadLater; shared has no effect on the imported bookmark")
    func mapsToreadDropsShared() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let json = """
            [{ "href": "https://example.com", "description": "Example", "toread": "yes", "shared": "no" }]
            """
            let data = Data(json.utf8)

            // When
            _ = try await PinboardJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.isReadLater == true, "It should map toread:yes to isReadLater:true")
            #expect(bookmark.isArchived == false, "It should not map shared onto any Stash field")
        }
    }

    // MARK: - Missing/invalid URLs

    @Test("importing a record with a missing href skips it with an error")
    func skipsMissingHREF() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data(#"[{ "description": "No URL" }, { "href": "https://ok.com" }]"#.utf8)

            // When
            let result = try await PinboardJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.imported == 1, "It should import the valid record")
            #expect(result.skipped == 1, "It should skip the record without an href")
        }
    }

    // MARK: - Duplicates

    @Test("importing a duplicate href updates the existing bookmark in place")
    func updatesDuplicateURL() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let original = try await app.makeBookmark(
                for: user,
                url: "https://example.com",
                title: "Old",
                tags: ["old"]
            )
            let originalCreatedAt = try #require(try await Bookmark.find(original.requireID(), on: app.db)).createdAt
            let data = Data(
                #"[{ "href": "https://example.com", "description": "New", "tags": "new" }]"#.utf8
            )

            // When
            let result = try await PinboardJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.updated == 1, "It should count the record as updated")
            let bookmark = try #require(try await Bookmark.find(original.requireID(), on: app.db))
            #expect(bookmark.title == "New", "It should overwrite the title")
            #expect(bookmark.tags == ["new"], "It should overwrite the tags")
            #expect(bookmark.createdAt == originalCreatedAt, "It should preserve the original createdAt")
        }
    }

    // MARK: - Failures

    @Test("importing a payload that is not a JSON array throws invalidFormat")
    func throwsOnMalformedPayload() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data(#"{ "posts": [] }"#.utf8)

            // When / Then
            await #expect(throws: ImportError.self, "It should reject a non-array payload") {
                _ = try await PinboardJSONImporter().import(from: data, for: user.requireID(), on: app.db)
            }
        }
    }
}
