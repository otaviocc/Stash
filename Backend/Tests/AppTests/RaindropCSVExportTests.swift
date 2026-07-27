// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies `RaindropCSVExporter`: the documented `folder,url,title,note,tags,created` header,
/// an empty `folder` column, comma-joined tags, the download route, and an export → import
/// round-trip.
@Suite("Raindrop CSV export")
struct RaindropCSVExportTests {

    // MARK: - Shape

    @Test("exporting produces the documented header and an empty folder column")
    func exportsDocumentedHeader() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await app.makeBookmark(
                for: user, url: "https://example.com", title: "Example",
                description: "Desc", tags: ["topic/swift", "ios"]
            )

            // When
            let data = try await RaindropCSVExporter().export(for: user.requireID(), on: app.db)
            let text = try #require(String(data: data, encoding: .utf8))
            let rows = CSVParser.parse(text)

            // Then
            #expect(
                rows[0] == ["folder", "url", "title", "note", "tags", "created"],
                "It should emit the documented header"
            )
            #expect(rows[1][0] == "", "It should leave the folder column empty")
            #expect(rows[1][1] == "https://example.com", "It should export the URL")
            #expect(rows[1][2] == "Example", "It should export the title")
            #expect(rows[1][3] == "Desc", "It should export the description as note")
            #expect(rows[1][4] == "topic/swift, ios", "It should comma-join tags")
        }
    }

    @Test("exporting includes archived bookmarks")
    func includesArchivedBookmarks() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await app.makeBookmark(for: user, url: "https://active.com", title: "Active")
            try await app.makeBookmark(for: user, url: "https://archived.com", title: "Archived", isArchived: true)

            // When
            let data = try await RaindropCSVExporter().export(for: user.requireID(), on: app.db)
            let text = try #require(String(data: data, encoding: .utf8))

            // Then
            #expect(text.contains("https://archived.com"), "It should include the archived bookmark")
        }
    }

    // MARK: - Download route

    @Test("the export route serves a Raindrop CSV attachment")
    func exportRouteServesAttachment() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            try await app.makeBookmark(for: user, url: "https://example.com", title: "Example")

            // When / Then
            try await app.testing().test(
                .GET, "app/export?format=raindrop-csv", headers: headers
            ) { res async throws in
                #expect(res.status == .ok, "It should respond 200")
                let disposition = res.headers.first(name: .contentDisposition) ?? ""
                #expect(disposition.contains("attachment"), "It should be an attachment")
                #expect(disposition.contains(".csv"), "It should have a .csv filename")
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
            let originalCreatedAt = try #require(try await Bookmark.query(on: app.db).first()).createdAt

            // When
            let data = try await RaindropCSVExporter().export(for: user.requireID(), on: app.db)
            let result = try await RaindropCSVImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.updated == 1, "It should update the existing bookmark in place")
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.title == "Example", "It should preserve the title")
            #expect(bookmark.$description.value == "Desc", "It should preserve the description")
            #expect(bookmark.tags == ["topic/swift", "ios"], "It should preserve tags via the tags column")
            #expect(
                bookmark.createdAt?.timeIntervalSince1970.rounded() == originalCreatedAt?.timeIntervalSince1970
                    .rounded(),
                "It should preserve createdAt to the second"
            )
        }
    }
}
