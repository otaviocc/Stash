// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

/// Imports a Pinboard JSON export (`Settings → Backups → JSON`, backed by
/// `GET /v1/posts/all?format=json`), a flat top-level array of bookmark objects using Pinboard's
/// Delicious-legacy field names.
///
/// Field mapping:
/// - `href` (required; record skipped if missing/invalid) → `url`
/// - `description` (Pinboard's field for the page title, not a description) → `title`
/// - `extended` (Pinboard's actual description field) → `description`
/// - `tags`: a single **space-separated** string (Pinboard tags may not contain whitespace, so
///   this is unambiguous)
/// - `time`: ISO-8601 → `createdAt`
/// - `toread` (`"yes"`/`"no"`) → `isReadLater`
/// - `shared` is read and discarded: Stash has no public-sharing concept
///   (see Docs/product-technical.md §22, Out of Scope)
///
/// A duplicate URL updates the existing bookmark in place, same convention as every other
/// importer.
struct PinboardJSONImporter: BookmarkImporter {

    // MARK: Nested Types

    /// A single decoded Pinboard bookmark record.
    private struct Record: Decodable {

        let href: String?
        let description: String?
        let extended: String?
        let tags: String?
        let time: String?
        let toread: String?
    }

    // MARK: Static Properties

    static let identifier = "pinboard-json"
    static let displayName = "Pinboard (JSON)"
    static let fileExtension = "json"

    private static let iso = ISO8601DateFormatter()

    // MARK: Functions

    func `import`(from data: Data, for userID: UUID, on db: any Database) async throws -> ImportResult {
        let records: [Record]
        do {
            records = try JSONDecoder().decode([Record].self, from: data)
        } catch {
            throw ImportError
                .invalidFormat(
                    "This doesn't look like a Pinboard JSON export (expected a JSON array of bookmarks with an “href” field)."
                )
        }

        var imported = 0
        var updated = 0
        var skipped = 0
        var errors: [String] = []

        for (index, record) in records.enumerated() {
            let position = index + 1

            guard let rawHREF = record.href?.trimmingCharacters(in: .whitespacesAndNewlines), !rawHREF.isEmpty else {
                skipped += 1
                errors.append("Record \(position): missing URL.")
                continue
            }

            let url: String
            do {
                url = try Bookmark.validatedURL(rawHREF)
            } catch {
                skipped += 1
                errors.append("Record \(position): invalid URL “\(rawHREF)”.")
                continue
            }

            let title = record.description ?? ""
            let description = record.extended?.nonEmpty
            let tags = Bookmark.normalizeTags(
                (record.tags ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
            )
            let createdAt = record.time.flatMap(Self.iso.date(from:))
            let isReadLater = record.toread?.lowercased() == "yes"

            if let existing = try await Bookmark.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$url == url)
                .first()
            {
                existing.title = title
                existing.description = description
                existing.applyTags(tags)
                existing.isReadLater = isReadLater
                try await existing.save(on: db)
                updated += 1
            } else {
                let bookmark = Bookmark(
                    userID: userID,
                    url: url,
                    title: title,
                    description: description,
                    tags: tags,
                    isReadLater: isReadLater
                )
                try await bookmark.save(on: db)
                if let createdAt {
                    bookmark.createdAt = createdAt
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
