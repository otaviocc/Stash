// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

/// Exports all of a user's bookmarks (archived included) as a Pinboard-shaped JSON array, using
/// Pinboard's own Delicious-legacy field names (`href`/`description`/`extended`/`tags`/`time`) so
/// the file is importable by Pinboard itself and by the many tools that already speak this shape.
///
/// Known lossy edge case: Pinboard's `tags` field is a single space-separated string (Pinboard
/// tags may not contain whitespace), so a Stash tag containing a literal space (rare, but not
/// disallowed by `Bookmark.normalizeTags`) would not survive a round-trip through this format.
///
/// `isArchived` and Smart Views have no equivalent in this format and are dropped, same as
/// `AnyboxExporter`. `shared`/`toread` are always written as `"no"`: Stash has no public-sharing or
/// read-later/unread concept.
struct PinboardJSONExporter: BookmarkExporter {

    // MARK: Nested Types

    /// A single bookmark serialized into Pinboard's JSON shape.
    private struct Record: Encodable {

        let href: String
        let description: String
        let extended: String
        let tags: String
        let time: String
        let shared: String
        let toread: String
    }

    // MARK: Static Properties

    static let identifier = "pinboard-json"
    static let displayName = "Pinboard (JSON)"
    static let fileExtension = "json"
    static let mimeType = "application/json"

    // MARK: Functions

    func export(for userID: UUID, on db: any Database) async throws -> Data {
        let bookmarks = try await ExportSupport.sortedBookmarks(for: userID, on: db)

        let records = bookmarks.map { bookmark in
            Record(
                href: bookmark.url,
                description: bookmark.title,
                extended: bookmark.description ?? "",
                tags: bookmark.tags.joined(separator: " "),
                time: ExportSupport.iso8601.string(from: bookmark.createdAt ?? Date()),
                shared: "no",
                toread: "no"
            )
        }

        return try ExportSupport.makeEncoder().encode(records)
    }
}
