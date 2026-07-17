// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies `AnyboxExporter`: the flat top-level JSON array shape, plain-string tags, archived
/// inclusion, sort order, the download route, and an export → import round-trip.
@Suite("Anybox export")
struct AnyboxExportTests {

    // MARK: Nested Types

    private struct ExportedRecord: Decodable {

        let url: String
        let title: String
        let description: String?
        let tags: [String]
        let dateAdded: String
    }

    // MARK: Functions

    // MARK: - Shape

    @Test("exporting produces a flat JSON array of bookmark records")
    func exportsFlatArray() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await app.makeBookmark(
                for: user, url: "https://example.com", title: "Example",
                description: "Desc", tags: ["topic/swift", "ios"]
            )

            // When
            let data = try await AnyboxExporter().export(for: user.requireID(), on: app.db)
            let records = try JSONDecoder().decode([ExportedRecord].self, from: data)

            // Then
            #expect(records.count == 1, "It should export the single bookmark")
            let record = try #require(records.first)
            #expect(record.url == "https://example.com", "It should export the URL")
            #expect(record.title == "Example", "It should export the title")
            #expect(record.description == "Desc", "It should export the description")
            #expect(record.tags == ["topic/swift", "ios"], "It should emit tags as plain strings")
            #expect(!record.dateAdded.isEmpty, "It should emit an ISO-8601 dateAdded")
        }
    }

    @Test("exporting includes archived bookmarks")
    func includesArchivedBookmarks() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await app.makeBookmark(for: user, url: "https://active.com", title: "Active")
            try await app.makeBookmark(
                for: user, url: "https://archived.com", title: "Archived", isArchived: true
            )

            // When
            let data = try await AnyboxExporter().export(for: user.requireID(), on: app.db)
            let records = try JSONDecoder().decode([ExportedRecord].self, from: data)

            // Then
            #expect(records.count == 2, "It should export both active and archived bookmarks")
            #expect(
                records.contains { $0.url == "https://archived.com" },
                "It should include the archived bookmark"
            )
        }
    }

    @Test("exporting sorts records by createdAt ascending")
    func sortsByCreatedAtAscending() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let first = try await app.makeBookmark(for: user, url: "https://first.com", title: "First")
            first.createdAt = Date(timeIntervalSince1970: 1000)
            try await first.save(on: app.db)
            let second = try await app.makeBookmark(for: user, url: "https://second.com", title: "Second")
            second.createdAt = Date(timeIntervalSince1970: 2000)
            try await second.save(on: app.db)

            // When
            let data = try await AnyboxExporter().export(for: user.requireID(), on: app.db)
            let records = try JSONDecoder().decode([ExportedRecord].self, from: data)

            // Then
            #expect(records.map(\.url) == ["https://first.com", "https://second.com"], "It should sort oldest first")
        }
    }

    @Test("exporting omits the description when the bookmark has none")
    func omitsMissingDescription() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await app.makeBookmark(for: user, url: "https://example.com", title: "Example")

            // When
            let data = try await AnyboxExporter().export(for: user.requireID(), on: app.db)
            let json = try #require(String(data: data, encoding: .utf8))

            // Then
            #expect(!json.contains("description"), "It should omit the description key when nil")
        }
    }

    // MARK: - Download route

    @Test("the export route serves an Anybox JSON attachment")
    func exportRouteServesAttachment() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            try await app.makeBookmark(for: user, url: "https://example.com", title: "Example")

            // When / Then
            try await app.testing().test(
                .GET, "app/export?format=anybox", headers: headers
            ) { res async throws in
                #expect(res.status == .ok, "It should respond 200")
                #expect(res.headers.contentType == .json, "It should serve application/json")
                let disposition = res.headers.first(name: .contentDisposition) ?? ""
                #expect(disposition.contains("attachment"), "It should be an attachment")
                #expect(disposition.contains(".json"), "It should have a .json filename")
            }
        }
    }

    // MARK: - Round-trip

    @Test("exporting then re-importing preserves bookmarks and tags")
    func roundTripsThroughImporter() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await app.makeBookmark(
                for: user, url: "https://example.com", title: "Example",
                description: "Desc", tags: ["topic/swift", "ios"]
            )
            let originalCreatedAt = try #require(
                try await Bookmark.query(on: app.db).first()
            ).createdAt

            // When
            let data = try await AnyboxExporter().export(for: user.requireID(), on: app.db)
            let result = try await AnyboxImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.updated == 1, "It should update the existing bookmark in place")
            #expect(result.imported == 0, "It should not create a duplicate")
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.title == "Example", "It should preserve the title")
            #expect(bookmark.$description.value == "Desc", "It should preserve the description")
            #expect(bookmark.tags == ["topic/swift", "ios"], "It should preserve hierarchical tags")
            #expect(bookmark.createdAt == originalCreatedAt, "It should preserve createdAt")
        }
    }
}
