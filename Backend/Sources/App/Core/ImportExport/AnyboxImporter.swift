// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

/// Imports an Anybox JSON export, a flat top-level array of bookmark objects.
///
/// Field handling reflects Anybox's *actual* export shape (which differs from early docs):
/// - `url` (required; record skipped if missing/invalid)
/// - `title` (empty string if missing)
/// - `description`
/// - `tags`: Anybox stores **arrays of `[namespace, value]` pairs**, e.g.
///   `[["topic","music-gear"],["status","wishlist"]]`. Each pair is joined with `/` into a
///   hierarchical Stash tag (`topic/music-gear`), then normalized. A plain `[String]` is also
///   accepted for forward/backward compatibility.
/// - `dateAdded` (ISO-8601 string) → `createdAt`; a numeric `date_added`/`dateAdded` (Unix
///   seconds) is also accepted. Missing → current time.
/// - Folders and `comment`/`article`/`keyword`/`isStarred` are ignored (flat import).
///
/// A duplicate URL updates the existing bookmark in place (title/description/tags overwritten,
/// `createdAt` left untouched).
struct AnyboxImporter: BookmarkImporter {

    // MARK: Nested Types

    /// A tag entry that may be a string or an array of strings (Anybox uses the latter).
    private struct FlexibleTag: Decodable {

        // MARK: Properties

        let value: String?

        // MARK: Lifecycle

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let single = try? container.decode(String.self) {
                value = single
            } else if let parts = try? container.decode([String].self) {
                value = parts.joined(separator: "/")
            } else {
                value = nil
            }
        }
    }

    /// A single decoded Anybox bookmark record.
    private struct Record: Decodable {

        // MARK: Nested Types

        /// Coding keys covering both the camelCase and snake_case date fields.
        enum CodingKeys: String, CodingKey {

            case url, title, description, tags, dateAdded
            case dateAddedUnix = "date_added"
        }

        // MARK: Static Properties

        private static let iso = ISO8601DateFormatter()

        // MARK: Properties

        let url: String?
        let title: String?
        let description: String?
        let tags: [String]
        let createdAt: Date?

        // MARK: Lifecycle

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            url = (try? c.decodeIfPresent(String.self, forKey: .url))
            title = (try? c.decodeIfPresent(String.self, forKey: .title))
            description = (try? c.decodeIfPresent(String.self, forKey: .description))

            let rawTags = (try? c.decodeIfPresent([FlexibleTag].self, forKey: .tags)) ?? []
            tags = rawTags.compactMap(\.value)

            if let iso = (try? c.decodeIfPresent(String.self, forKey: .dateAdded)),
               let date = Record.iso.date(from: iso)
            {
                createdAt = date
            } else if let ts = (try? c.decodeIfPresent(Double.self, forKey: .dateAddedUnix))
                ?? (try? c.decodeIfPresent(Double.self, forKey: .dateAdded))
            {
                createdAt = Date(timeIntervalSince1970: ts)
            } else {
                createdAt = nil
            }
        }
    }

    // MARK: Static Properties

    static let identifier = "anybox"
    static let displayName = "Anybox JSON"
    static let fileExtension = "json"

    // MARK: Functions

    func `import`(from data: Data, for userID: UUID, on db: any Database) async throws -> ImportResult {
        let records: [Record]
        do {
            records = try JSONDecoder().decode([Record].self, from: data)
        } catch {
            throw ImportError
                .invalidFormat("This doesn't look like an Anybox JSON export (expected a JSON array of bookmarks).")
        }

        var imported = 0
        var updated = 0
        var skipped = 0
        var errors: [String] = []

        for (index, record) in records.enumerated() {
            let position = index + 1

            guard let rawURL = record.url?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
                skipped += 1
                errors.append("Record \(position): missing URL.")
                continue
            }

            let url: String
            do {
                url = try Bookmark.validatedURL(rawURL)
            } catch {
                skipped += 1
                errors.append("Record \(position): invalid URL “\(rawURL)”.")
                continue
            }

            let title = record.title ?? ""
            let description = record.description?.nonEmpty
            let tags = Bookmark.normalizeTags(record.tags)

            if let existing = try await Bookmark.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$url == url)
                .first()
            {
                existing.title = title
                existing.description = description
                existing.applyTags(tags)
                try await existing.save(on: db)
                updated += 1
            } else {
                let bookmark = Bookmark(userID: userID, url: url, title: title, description: description, tags: tags)
                try await bookmark.save(on: db)
                if let created = record.createdAt {
                    bookmark.createdAt = created
                    try await bookmark.save(on: db)
                }
                imported += 1
            }
        }

        if imported > 0, let user = try await User.find(userID, on: db) {
            user.bookmarkCount += imported
            try await user.save(on: db)
        }

        return ImportResult(imported: imported, updated: updated, skipped: skipped, errors: errors)
    }
}
