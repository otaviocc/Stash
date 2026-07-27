// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

/// Imports a Raindrop.io CSV export (`Settings → Backups`, or `Export` on a collection). Raindrop
/// documents the columns it both produces and accepts back as `folder,url,title,note,tags,created`
/// (see help.raindrop.io/import#csv), but a full-account export may carry extra columns from
/// Raindrop's richer API object model (`id`, `cover`, `highlights`, `favorite`, …) that this backend
/// has no use for — so columns are matched **by header name** (case-insensitively, with a couple of
/// aliases), and any column this importer doesn't recognize is silently ignored rather than
/// rejecting the file, following this codebase's existing "tolerate shape variance" convention
/// (see `AnyboxImporter`).
///
/// Field mapping:
/// - `url`/`link`/`href` (required; row skipped if missing/invalid)
/// - `title` (empty string if missing)
/// - `note`/`excerpt`/`description` → `description`
/// - `tags`: comma-separated (Raindrop's own convention — split on comma only, not whitespace, so
///   a tag containing a space survives)
/// - `folder`/`collection`: Raindrop already uses `/` to nest folders, the same separator Stash
///   uses for hierarchical tags, so the whole folder path becomes one additional tag as-is
/// - `created`: Unix seconds or ISO-8601 (both documented as accepted by Raindrop itself)
///
/// A duplicate URL updates the existing bookmark in place, same convention as every other
/// importer.
struct RaindropCSVImporter: BookmarkImporter {

    // MARK: Static Properties

    static let identifier = "raindrop-csv"
    static let displayName = "Raindrop.io (CSV)"
    static let fileExtension = "csv"

    private static let iso = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let urlAliases = ["url", "link", "href"]
    private static let titleAliases = ["title"]
    private static let noteAliases = ["note", "excerpt", "description"]
    private static let tagsAliases = ["tags"]
    private static let folderAliases = ["folder", "collection"]
    private static let createdAliases = ["created", "date"]

    // MARK: Static Functions

    private static func columnIndex(for aliases: [String], in header: [String]) -> Int? {
        let lowered = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        for alias in aliases {
            if let index = lowered.firstIndex(of: alias) {
                return index
            }
        }
        return nil
    }

    private static func field(_ row: [String], at index: Int?) -> String? {
        guard let index, row.indices.contains(index) else { return nil }

        return row[index].trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    private static func parseDate(_ raw: String) -> Date? {
        if let seconds = Double(raw) {
            return Date(timeIntervalSince1970: seconds)
        }
        return iso.date(from: raw) ?? isoFractional.date(from: raw)
    }

    // MARK: Functions

    func `import`(from data: Data, for userID: UUID, on db: any Database) async throws -> ImportResult {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError
                .invalidFormat("This doesn't look like a Raindrop CSV export (couldn't decode the file as text).")
        }

        let rows = CSVParser.parse(text)
        guard let header = rows.first, Self.columnIndex(for: Self.urlAliases, in: header) != nil else {
            throw ImportError
                .invalidFormat(
                    "This doesn't look like a Raindrop CSV export (expected a header row with a url column)."
                )
        }

        let urlIndex = Self.columnIndex(for: Self.urlAliases, in: header)
        let titleIndex = Self.columnIndex(for: Self.titleAliases, in: header)
        let noteIndex = Self.columnIndex(for: Self.noteAliases, in: header)
        let tagsIndex = Self.columnIndex(for: Self.tagsAliases, in: header)
        let folderIndex = Self.columnIndex(for: Self.folderAliases, in: header)
        let createdIndex = Self.columnIndex(for: Self.createdAliases, in: header)

        var imported = 0
        var updated = 0
        var skipped = 0
        var errors: [String] = []

        for (index, row) in rows.dropFirst().enumerated() {
            let position = index + 1

            guard let rawURL = Self.field(row, at: urlIndex) else {
                skipped += 1
                errors.append("Row \(position): missing URL.")
                continue
            }

            let url: String
            do {
                url = try Bookmark.validatedURL(rawURL)
            } catch {
                skipped += 1
                errors.append("Row \(position): invalid URL “\(rawURL)”.")
                continue
            }

            let title = Self.field(row, at: titleIndex) ?? ""
            let description = Self.field(row, at: noteIndex)

            var tags: [String] = []
            if let folder = Self.field(row, at: folderIndex) {
                tags.append(folder)
            }
            if let tagsField = Self.field(row, at: tagsIndex) {
                tags += tagsField.components(separatedBy: ",")
            }
            let normalizedTags = Bookmark.normalizeTags(tags)

            let createdAt = Self.field(row, at: createdIndex).flatMap(Self.parseDate)

            if let existing = try await Bookmark.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$url == url)
                .first()
            {
                existing.title = title
                existing.description = description
                existing.applyTags(normalizedTags)
                try await existing.save(on: db)
                updated += 1
            } else {
                let bookmark = Bookmark(
                    userID: userID,
                    url: url,
                    title: title,
                    description: description,
                    tags: normalizedTags
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
