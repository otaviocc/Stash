// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies `PinboardJSONExporter`: Pinboard's field names, space-joined tags, `toread` mapping
/// from `isReadLater`, `shared` always `"no"`, the download route, and an export → import
/// round-trip.
@Suite("Pinboard JSON export")
struct PinboardJSONExportTests {

    // MARK: Nested Types

    private struct ExportedRecord: Decodable {

        let href: String
        let description: String
        let extended: String
        let tags: String
        let time: String
        let shared: String
        let toread: String
    }

    // MARK: Functions

    // MARK: - Shape

    @Test("exporting maps title/description/tags to Pinboard's field names")
    func exportsPinboardShape() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await app.makeBookmark(
                for: user, url: "https://example.com", title: "Example",
                description: "Desc", tags: ["topic/swift", "ios"]
            )

            // When
            let data = try await PinboardJSONExporter().export(for: user.requireID(), on: app.db)
            let records = try JSONDecoder().decode([ExportedRecord].self, from: data)

            // Then
            let record = try #require(records.first)
            #expect(record.href == "https://example.com", "It should export the URL as href")
            #expect(record.description == "Example", "It should export the title as description")
            #expect(record.extended == "Desc", "It should export the description as extended")
            #expect(record.tags == "topic/swift ios", "It should space-join tags")
            #expect(record.shared == "no", "It should always mark bookmarks private")
            #expect(record.toread == "no", "It should map isReadLater:false to toread:no")
        }
    }

    @Test("exporting a bookmark marked to read later sets toread:yes")
    func exportsReadLaterAsToread() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await app.makeBookmark(for: user, url: "https://example.com", title: "Example", isReadLater: true)

            // When
            let data = try await PinboardJSONExporter().export(for: user.requireID(), on: app.db)
            let records = try JSONDecoder().decode([ExportedRecord].self, from: data)

            // Then
            let record = try #require(records.first)
            #expect(record.toread == "yes", "It should map isReadLater:true to toread:yes")
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
            let data = try await PinboardJSONExporter().export(for: user.requireID(), on: app.db)
            let records = try JSONDecoder().decode([ExportedRecord].self, from: data)

            // Then
            #expect(records.count == 2, "It should export both active and archived bookmarks")
        }
    }

    // MARK: - Download route

    @Test("the export route serves a Pinboard JSON attachment")
    func exportRouteServesAttachment() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            try await app.makeBookmark(for: user, url: "https://example.com", title: "Example")

            // When / Then
            try await app.testing().test(
                .GET, "app/export?format=pinboard-json", headers: headers
            ) { res async throws in
                #expect(res.status == .ok, "It should respond 200")
                #expect(res.headers.contentType == .json, "It should serve application/json")
                let disposition = res.headers.first(name: .contentDisposition) ?? ""
                #expect(disposition.contains("attachment"), "It should be an attachment")
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
            let data = try await PinboardJSONExporter().export(for: user.requireID(), on: app.db)
            let result = try await PinboardJSONImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.updated == 1, "It should update the existing bookmark in place")
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.title == "Example", "It should preserve the title")
            #expect(bookmark.$description.value == "Desc", "It should preserve the description")
            #expect(bookmark.tags == ["topic/swift", "ios"], "It should preserve tags via the space-joined tags field")
            #expect(bookmark.createdAt == originalCreatedAt, "It should preserve createdAt")
        }
    }
}
