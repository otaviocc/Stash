// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies `StashJSONImporter`: the envelope shape, bookmark and Smart View import, the optional
/// `smartViews` node, duplicate handling, invalid-record reporting, and parse failures.
@Suite("Stash JSON import")
struct StashJSONImportTests {

    // MARK: - Bookmarks

    @Test("importing bookmarks stores url, title, description, tags, archived, and read-later flags")
    func importsBookmarkFields() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let json = """
            {
              "version": "1",
              "bookmarks": [
                {
                  "url": "https://example.com",
                  "title": "Example",
                  "description": "Desc",
                  "tags": ["swift", "ios"],
                  "isArchived": true,
                  "isReadLater": true,
                  "createdAt": "2020-06-15T12:00:00Z"
                }
              ]
            }
            """
            let data = Data(json.utf8)

            // When
            let result = try await StashJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.imported == 1, "It should import the bookmark")
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.title == "Example", "It should import the title")
            #expect(bookmark.$description.value == "Desc", "It should import the description")
            #expect(bookmark.tags == ["swift", "ios"], "It should import the tags")
            #expect(bookmark.isArchived, "It should import the archived flag")
            #expect(bookmark.isReadLater, "It should import the read-later flag")
            #expect(
                bookmark.createdAt == ISO8601DateFormatter().date(from: "2020-06-15T12:00:00Z"),
                "It should import createdAt"
            )
        }
    }

    @Test("importing without a smartViews node imports bookmarks cleanly")
    func importsWithoutSmartViewsNode() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data(#"{ "bookmarks": [{ "url": "https://example.com", "title": "E" }] }"#.utf8)

            // When
            let result = try await StashJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.imported == 1, "It should import the bookmark")
            #expect(result.smartViewsImported == 0, "It should import no Smart Views")
        }
    }

    @Test("importing a duplicate URL updates in place and preserves createdAt")
    func updatesDuplicateBookmark() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let original = try await app.makeBookmark(
                for: user, url: "https://example.com", title: "Old", tags: ["old"]
            )
            let originalCreatedAt = original.createdAt
            let data = Data(
                #"{ "bookmarks": [{ "url": "https://example.com", "title": "New", "tags": ["new"] }] }"#.utf8
            )

            // When
            let result = try await StashJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.updated == 1, "It should update the existing bookmark")
            let bookmark = try #require(try await Bookmark.find(original.requireID(), on: app.db))
            #expect(bookmark.title == "New", "It should overwrite the title")
            #expect(bookmark.tags == ["new"], "It should overwrite the tags")
            #expect(bookmark.createdAt == originalCreatedAt, "It should preserve createdAt")
        }
    }

    @Test("importing a bookmark with a missing URL skips it with an error")
    func skipsBookmarkWithoutURL() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data(#"{ "bookmarks": [{ "title": "No URL" }] }"#.utf8)

            // When
            let result = try await StashJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.skipped == 1, "It should skip the record without a URL")
            #expect(result.errors.count == 1, "It should report one error")
        }
    }

    // MARK: - Smart Views

    @Test("importing a Smart View creates it with its conditions")
    func importsSmartView() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let json = """
            {
              "bookmarks": [],
              "smartViews": [
                {
                  "name": "Reading list",
                  "matchMode": "all",
                  "conditions": [{ "type": "tag", "value": "swift" }]
                }
              ]
            }
            """
            let data = Data(json.utf8)

            // When
            let result = try await StashJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.smartViewsImported == 1, "It should import the Smart View")
            let smartView = try #require(try await SmartView.query(on: app.db).first())
            #expect(smartView.name == "Reading list", "It should import the name")
            #expect(smartView.conditions.count == 1, "It should import the condition")
        }
    }

    @Test("importing a Smart View whose name already exists updates it in place")
    func updatesDuplicateSmartView() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await SmartView(
                userID: user.requireID(), name: "Reading list", conditions: [.tag("old")]
            ).save(on: app.db)
            let json = """
            {
              "bookmarks": [],
              "smartViews": [
                { "name": "Reading list", "matchMode": "any", "conditions": [{ "type": "tag", "value": "new" }] }
              ]
            }
            """
            let data = Data(json.utf8)

            // When
            let result = try await StashJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.smartViewsUpdated == 1, "It should update the existing Smart View")
            let count = try await SmartView.query(on: app.db).count()
            #expect(count == 1, "It should not create a duplicate")
        }
    }

    @Test("importing a Smart View with no valid conditions skips it with an error")
    func skipsInvalidSmartView() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data(
                #"{ "bookmarks": [], "smartViews": [{ "name": "Broken", "conditions": [] }] }"#.utf8
            )

            // When
            let result = try await StashJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.smartViewsSkipped == 1, "It should skip the invalid Smart View")
            #expect(result.errors.count == 1, "It should report one error")
        }
    }

    // MARK: - Failures

    @Test("importing a payload without a bookmarks array throws invalidFormat")
    func throwsOnMalformedPayload() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let data = Data(#"[{ "url": "https://example.com" }]"#.utf8)

            // When / Then
            await #expect(throws: ImportError.self, "It should reject a payload without a bookmarks array") {
                _ = try await StashJSONImporter().import(from: data, for: user.requireID(), on: app.db)
            }
        }
    }
}
