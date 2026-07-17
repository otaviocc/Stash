// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

/// Exports all of a user's bookmarks (archived included) as an Anybox JSON export — a flat
/// top-level array of bookmark objects, sorted by `createdAt` ascending.
///
/// This is the inverse of `AnyboxImporter`, and is intentionally lossy: Anybox has no concept of
/// archived bookmarks or Smart Views, so `isArchived` is dropped and Smart Views are omitted.
///
/// Field mapping:
/// - `url`, `title`, `description` (omitted when empty)
/// - `tags`: emitted as a plain `[String]` (e.g. `["topic/swift", "ios"]`). The importer accepts
///   this shape as a documented fallback, so a Stash → Anybox → Stash round-trip preserves tags.
/// - `dateAdded`: ISO-8601 string derived from `createdAt`.
struct AnyboxExporter: BookmarkExporter {

    // MARK: Nested Types

    /// A single bookmark serialized into the Anybox JSON shape.
    private struct Record: Encodable {

        let url: String
        let title: String
        let description: String?
        let tags: [String]
        let dateAdded: String
    }

    // MARK: Static Properties

    static let identifier = "anybox"
    static let displayName = "Anybox JSON"
    static let fileExtension = "json"
    static let mimeType = "application/json"

    // MARK: Functions

    func export(for userID: UUID, on db: any Database) async throws -> Data {
        let bookmarks = try await Bookmark.query(on: db)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .ascending)
            .sort(\.$id, .ascending)
            .all()

        let iso = ISO8601DateFormatter()
        let records = bookmarks.map { bookmark in
            Record(
                url: bookmark.url,
                title: bookmark.title,
                description: bookmark.description,
                tags: bookmark.tags,
                dateAdded: iso.string(from: bookmark.createdAt ?? Date())
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(records)
    }
}
