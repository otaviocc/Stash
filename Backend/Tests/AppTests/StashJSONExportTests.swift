// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies `StashJSONExporter`: the envelope shape, archived inclusion, sort orders, the download
/// route, and an export → import round-trip covering bookmarks and Smart Views.
@Suite("Stash JSON export")
struct StashJSONExportTests {

    // MARK: Nested Types

    private struct ExportedDocument: Decodable {

        let version: String
        let exportedAt: String
        let bookmarks: [ExportedBookmark]
        let smartViews: [ExportedSmartView]
    }

    private struct ExportedBookmark: Decodable {

        let id: String
        let url: String
        let title: String
        let description: String?
        let tags: [String]
        let isArchived: Bool
        let isReadLater: Bool
        let createdAt: String
    }

    private struct ExportedSmartView: Decodable {

        let id: String
        let name: String
        let matchMode: String
        let conditions: [ExportedCondition]
    }

    private struct ExportedCondition: Decodable {

        let type: String
        let value: String
    }

    // MARK: Functions

    // MARK: - Shape

    @Test("exporting wraps bookmarks and Smart Views in a versioned envelope")
    func exportsVersionedEnvelope() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await app.makeBookmark(
                for: user, url: "https://example.com", title: "Example",
                description: "Desc", tags: ["swift"]
            )
            try await SmartView(
                userID: user.requireID(), name: "Reading list", conditions: [.tag("swift")]
            ).save(on: app.db)

            // When
            let data = try await StashJSONExporter().export(for: user.requireID(), on: app.db)
            let document = try JSONDecoder().decode(ExportedDocument.self, from: data)

            // Then
            #expect(document.version == "1", "It should stamp the format version")
            #expect(!document.exportedAt.isEmpty, "It should stamp exportedAt")
            #expect(document.bookmarks.count == 1, "It should export the bookmark")
            #expect(document.smartViews.count == 1, "It should export the Smart View")
            #expect(document.smartViews.first?.conditions.count == 1, "It should export the condition")
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
            let data = try await StashJSONExporter().export(for: user.requireID(), on: app.db)
            let document = try JSONDecoder().decode(ExportedDocument.self, from: data)

            // Then
            #expect(document.bookmarks.count == 2, "It should export both bookmarks")
            #expect(
                document.bookmarks.contains { $0.isArchived },
                "It should include the archived bookmark"
            )
        }
    }

    @Test("exporting sorts bookmarks by createdAt ascending")
    func sortsBookmarksByCreatedAt() async throws {
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
            let data = try await StashJSONExporter().export(for: user.requireID(), on: app.db)
            let document = try JSONDecoder().decode(ExportedDocument.self, from: data)

            // Then
            #expect(
                document.bookmarks.map(\.url) == ["https://first.com", "https://second.com"],
                "It should sort oldest first"
            )
        }
    }

    // MARK: - Download route

    @Test("the export route serves a Stash JSON attachment by default")
    func exportRouteServesAttachment() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            try await app.makeBookmark(for: user, url: "https://example.com", title: "Example")

            // When / Then
            try await app.testing().test(
                .GET, "app/export", headers: headers
            ) { res async throws in
                #expect(res.status == .ok, "It should respond 200")
                #expect(res.headers.contentType == .json, "It should serve application/json")
                let disposition = res.headers.first(name: .contentDisposition) ?? ""
                #expect(disposition.contains("attachment"), "It should be an attachment")
            }
        }
    }

    // MARK: - Round-trip

    @Test("exporting then re-importing preserves bookmarks and Smart Views")
    func roundTripsThroughImporter() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await app.makeBookmark(
                for: user, url: "https://example.com", title: "Example",
                description: "Desc", tags: ["swift"], isArchived: true, isReadLater: true
            )
            try await SmartView(
                userID: user.requireID(), name: "Reading list", conditions: [.tag("swift")]
            ).save(on: app.db)
            let originalCreatedAt = try #require(try await Bookmark.query(on: app.db).first()).createdAt

            // When
            let data = try await StashJSONExporter().export(for: user.requireID(), on: app.db)
            let result = try await StashJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.updated == 1, "It should update the existing bookmark in place")
            #expect(result.smartViewsUpdated == 1, "It should update the existing Smart View in place")
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.title == "Example", "It should preserve the title")
            #expect(bookmark.tags == ["swift"], "It should preserve the tags")
            #expect(bookmark.isArchived, "It should preserve the archived flag")
            #expect(bookmark.isReadLater, "It should preserve the read-later flag")
            #expect(bookmark.createdAt == originalCreatedAt, "It should preserve createdAt")
        }
    }
}
