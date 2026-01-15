import Fluent
import Foundation

/// Imports Stash's own native export format (see `StashJSONExporter` / PRD §11.3): an object with
/// a `bookmarks` array. Round-trips a Stash export, and is the natural restore-from-backup path.
///
/// Per-bookmark mapping:
/// - `url` (required; record skipped if missing/invalid)
/// - `title` (empty string if missing) · `description` · `tags` (normalised) · `isArchived`
/// - `faviconURL`
/// - `createdAt` (ISO-8601 string; current time if missing/unparseable)
/// - `id`/`updatedAt` and the top-level `version`/`exportedAt` are ignored.
///
/// A duplicate URL updates the existing bookmark in place (title/description/tags/isArchived/
/// faviconURL overwritten, `createdAt` left untouched).
struct StashJSONImporter: BookmarkImporter {
    static let identifier = "stash-json"
    static let displayName = "Stash JSON"
    static let fileExtension = "json"

    private struct Document: Decodable {
        let bookmarks: [Record]
    }

    private struct Record: Decodable {
        let url: String?
        let title: String?
        let description: String?
        let tags: [String]?
        let isArchived: Bool?
        let faviconURL: String?
        let createdAt: String?
    }

    func `import`(from data: Data, for userID: UUID, on db: any Database) async throws -> ImportResult {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw ImportError.invalidFormat(#"This doesn't look like a Stash JSON export (expected an object with a "bookmarks" array)."#)
        }

        var imported = 0
        var updated = 0
        var skipped = 0
        var errors: [String] = []

        for (index, record) in document.bookmarks.enumerated() {
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
            let tags = Bookmark.normalizeTags(record.tags ?? [])
            let isArchived = record.isArchived ?? false
            let faviconURL = record.faviconURL?.nonEmpty

            if let existing = try await Bookmark.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$url == url)
                .first()
            {
                existing.title = title
                existing.description = description
                existing.applyTags(tags)
                existing.isArchived = isArchived
                existing.faviconURL = faviconURL
                try await existing.save(on: db)
                updated += 1
            } else {
                let bookmark = Bookmark(
                    userID: userID,
                    url: url,
                    title: title,
                    description: description,
                    faviconURL: faviconURL,
                    tags: tags,
                    isArchived: isArchived
                )
                try await bookmark.save(on: db)
                // Fluent sets createdAt to "now" on insert; restore the imported timestamp with a
                // follow-up update (which only touches updatedAt, leaving createdAt as set).
                if let createdAt = record.createdAt, let date = Self.parseDate(createdAt) {
                    bookmark.createdAt = date
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

    private static let iso = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func parseDate(_ string: String) -> Date? {
        iso.date(from: string) ?? isoFractional.date(from: string)
    }
}
