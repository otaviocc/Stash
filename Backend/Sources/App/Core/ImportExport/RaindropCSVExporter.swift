// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

/// Exports all of a user's bookmarks (archived included) as a Raindrop.io-compatible CSV, using
/// the exact column layout Raindrop documents accepting back (`folder,url,title,note,tags,created`
/// (see help.raindrop.io/import#csv), for the best round-trip fidelity into Raindrop itself.
///
/// `folder` is left empty: Stash has no folder concept, and Raindrop has no hierarchical-tag
/// concept, so a Stash tag like `topic/swift` is written as-is into `tags` rather than guessing a
/// single "primary" folder for a bookmark that may carry several tags.
///
/// `isArchived`/`isReadLater` and Smart Views have no equivalent in this format and are dropped,
/// same as `AnyboxExporter`.
struct RaindropCSVExporter: BookmarkExporter {

    // MARK: Static Properties

    static let identifier = "raindrop-csv"
    static let displayName = "Raindrop.io (CSV)"
    static let fileExtension = "csv"
    static let mimeType = "text/csv"

    // MARK: Functions

    func export(for userID: UUID, on db: any Database) async throws -> Data {
        let bookmarks = try await ExportSupport.sortedBookmarks(for: userID, on: db)

        var lines = [CSVParser.makeLine(["folder", "url", "title", "note", "tags", "created"])]

        for bookmark in bookmarks {
            lines.append(
                CSVParser.makeLine([
                    "",
                    bookmark.url,
                    bookmark.title,
                    bookmark.description ?? "",
                    bookmark.tags.joined(separator: ", "),
                    ExportSupport.iso8601.string(from: bookmark.createdAt ?? Date())
                ])
            )
        }

        return Data(lines.joined(separator: "\n").utf8)
    }
}
