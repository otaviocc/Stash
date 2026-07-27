// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies `NetscapeHTMLExporter`: the flat (no-folder) shape with a `TAGS` attribute carrying
/// the full tag set, archived inclusion, the download route, and an export → import round-trip.
@Suite("Netscape HTML export")
struct NetscapeHTMLExportTests {

    // MARK: - Shape

    @Test("exporting produces a flat DL with a TAGS attribute per bookmark")
    func exportsFlatListWithTagsAttribute() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            try await app.makeBookmark(
                for: user, url: "https://example.com", title: "Example",
                description: "Desc", tags: ["topic/swift", "ios"]
            )

            // When
            let data = try await NetscapeHTMLExporter().export(for: user.requireID(), on: app.db)
            let html = try #require(String(data: data, encoding: .utf8))

            // Then
            #expect(html.contains("<!DOCTYPE NETSCAPE-Bookmark-file-1>"), "It should include the standard doctype")
            #expect(html.contains("HREF=\"https://example.com\""), "It should include the URL")
            #expect(html.contains("TAGS=\"topic/swift,ios\""), "It should carry the full tag set in TAGS")
            #expect(html.contains("<DD>Desc"), "It should include the description as a DD line")
            #expect(!html.contains("<H3"), "It should not emit any folder headers")
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
            let data = try await NetscapeHTMLExporter().export(for: user.requireID(), on: app.db)
            let html = try #require(String(data: data, encoding: .utf8))

            // Then
            #expect(html.contains("https://archived.com"), "It should include the archived bookmark")
        }
    }

    // MARK: - Download route

    @Test("the export route serves a Netscape HTML attachment")
    func exportRouteServesAttachment() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            try await app.makeBookmark(for: user, url: "https://example.com", title: "Example")

            // When / Then
            try await app.testing().test(
                .GET, "app/export?format=netscape-html", headers: headers
            ) { res async throws in
                #expect(res.status == .ok, "It should respond 200")
                let disposition = res.headers.first(name: .contentDisposition) ?? ""
                #expect(disposition.contains("attachment"), "It should be an attachment")
                #expect(disposition.contains(".html"), "It should have an .html filename")
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
            let data = try await NetscapeHTMLExporter().export(for: user.requireID(), on: app.db)
            let result = try await NetscapeHTMLImporter().import(from: data, for: user.requireID(), on: app.db)

            // Then
            #expect(result.updated == 1, "It should update the existing bookmark in place")
            #expect(result.imported == 0, "It should not create a duplicate")
            let bookmark = try #require(try await Bookmark.query(on: app.db).first())
            #expect(bookmark.title == "Example", "It should preserve the title")
            #expect(bookmark.$description.value == "Desc", "It should preserve the description")
            #expect(bookmark.tags == ["topic/swift", "ios"], "It should preserve tags via the TAGS attribute")
            #expect(
                bookmark.createdAt?.timeIntervalSince1970.rounded() == originalCreatedAt?.timeIntervalSince1970
                    .rounded(),
                "It should preserve createdAt to the second (ADD_DATE has no sub-second precision)"
            )
        }
    }
}
