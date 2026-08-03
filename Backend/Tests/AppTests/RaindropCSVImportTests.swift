// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies `RaindropCSVImporter`: Raindrop's documented column shape, comma-separated tags,
/// folder → tag mapping, both accepted `created` formats, column-name aliasing/tolerance of
/// unrecognized extra columns, and parse failures.
@Suite("Raindrop CSV import")
struct RaindropCSVImportTests {

    // MARK: - Documented shape

    @Test("importing Raindrop's documented CSV shape maps every column")
    func importsDocumentedShape() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let csv = """
            folder,url,title,note,tags,created
            "Folder",http://google.com,Google,"Note","search, app",1629980125
            """
            let data = Data(csv.utf8)

            // When
            let result = try await RaindropCSVImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.imported == 1, "It should import the single row")
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.title == "Google", "It should map title")
            #expect(bookmark.$description.value == "Note", "It should map note to description")
            #expect(
                bookmark.tags == ["folder", "search", "app"],
                "It should combine the folder tag with the comma-separated tags"
            )
            #expect(
                bookmark.createdAt == Date(timeIntervalSince1970: 1_629_980_125),
                "It should parse a Unix-seconds created value"
            )
        }
    }

    @Test("importing a nested folder path keeps the slash as a hierarchical tag")
    func importsNestedFolderAsHierarchicalTag() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let csv = """
            folder,url,title,note,tags,created
            "Folder/Nested folder",http://yahoo.com,Yahoo,"Note","search, app",1629980125
            """
            let data = Data(csv.utf8)

            // When
            _ = try await RaindropCSVImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(
                bookmark.tags.contains("folder/nested folder"),
                "It should keep the folder path as one hierarchical tag"
            )
        }
    }

    @Test("importing an ISO-8601 created value parses it too")
    func importsISOCreatedDate() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let csv = """
            url,title,created
            https://example.com,Example,2020-06-15T12:00:00Z
            """
            let data = Data(csv.utf8)

            // When
            _ = try await RaindropCSVImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            let expected = ISO8601DateFormatter().date(from: "2020-06-15T12:00:00Z")
            #expect(bookmark.createdAt == expected, "It should parse an ISO-8601 created value")
        }
    }

    // MARK: - Column aliasing & tolerance

    @Test("importing a header using link/excerpt aliases still maps correctly")
    func importsColumnAliases() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let csv = """
            link,title,excerpt
            https://example.com,Example,A note
            """
            let data = Data(csv.utf8)

            // When
            _ = try await RaindropCSVImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.title == "Example", "It should map title")
            #expect(bookmark.$description.value == "A note", "It should map excerpt to description")
        }
    }

    @Test("importing extra unrecognized columns is tolerated")
    func toleratesUnknownColumns() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let csv = """
            id,url,title,favorite,cover
            42,https://example.com,Example,true,https://example.com/cover.png
            """
            let data = Data(csv.utf8)

            // When
            let result = try await RaindropCSVImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.imported == 1, "It should import the row despite unrecognized columns")
        }
    }

    // MARK: - Missing/invalid URLs

    @Test("importing a row with a missing URL skips it with an error")
    func skipsMissingURL() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let csv = """
            url,title
            ,No URL
            https://ok.com,OK
            """
            let data = Data(csv.utf8)

            // When
            let result = try await RaindropCSVImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.imported == 1, "It should import the valid row")
            #expect(result.skipped == 1, "It should skip the row without a URL")
        }
    }

    // MARK: - Duplicates

    @Test("importing a duplicate URL updates the existing bookmark in place")
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
            let csv = """
            url,title,tags
            https://example.com,New,new
            """
            let data = Data(csv.utf8)

            // When
            let result = try await RaindropCSVImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.updated == 1, "It should count the row as updated")
            let bookmark = try #require(try await Bookmark.find(original.requireID(), on: app.db))
            #expect(bookmark.title == "New", "It should overwrite the title")
            #expect(bookmark.createdAt == originalCreatedAt, "It should preserve the original createdAt")
        }
    }

    // MARK: - Failures

    @Test("importing a CSV without a url column throws invalidFormat")
    func throwsWithoutURLColumn() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data("title,note\nExample,A note".utf8)

            // When / Then
            await #expect(throws: ImportError.self, "It should reject a header without a url column") {
                _ = try await RaindropCSVImporter().import(from: data, for: user.requireID(), on: app.db)
            }
        }
    }
}
