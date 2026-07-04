// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

/// Imports Stash's own native export format (see `StashJSONExporter` / PRD §11.3): an object with
/// a `bookmarks` array and an optional `smartViews` array. Round-trips a Stash export, and is the
/// natural restore-from-backup path.
///
/// Per-bookmark mapping:
/// - `url` (required; record skipped if missing/invalid)
/// - `title` (empty string if missing) · `description` · `tags` (normalized) · `isArchived`
/// - `faviconURL`
/// - `createdAt` (ISO-8601 string; current time if missing/unparseable)
/// - `id`/`updatedAt` and the top-level `version`/`exportedAt` are ignored.
///
/// A duplicate URL updates the existing bookmark in place (title/description/tags/isArchived/
/// faviconURL overwritten, `createdAt` left untouched).
///
/// Per-Smart-View mapping: `name`, `matchMode` (defaults to `all`), and `conditions` are used and
/// validated; `id`/`createdAt`/`updatedAt` are ignored. A Smart View whose name already exists is
/// updated in place; otherwise a new one is created — so re-importing is idempotent. The
/// `smartViews` node is optional, so older exports without it still import cleanly.
struct StashJSONImporter: BookmarkImporter {

    // MARK: Nested Types

    /// Top-level decoded envelope holding the bookmark and Smart View records.
    private struct Document: Decodable {

        let bookmarks: [Record]
        let smartViews: [SmartViewRecord]?
    }

    /// A single decoded Stash JSON bookmark record.
    private struct Record: Decodable {

        let url: String?
        let title: String?
        let description: String?
        let tags: [String]?
        let isArchived: Bool?
        let faviconURL: String?
        let createdAt: String?
    }

    /// A single decoded Stash JSON Smart View record.
    private struct SmartViewRecord: Decodable {

        let name: String?
        let matchMode: String?
        let conditions: [ConditionRecord]?
    }

    /// A single decoded Smart View condition: a `{ type, value }` pair.
    private struct ConditionRecord: Decodable {

        let type: String?
        let value: String?
    }

    // MARK: Static Properties

    static let identifier = "stash-json"
    static let displayName = "Stash JSON"
    static let fileExtension = "json"

    private static let iso = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: Static Functions

    private static func parseDate(_ string: String) -> Date? {
        iso.date(from: string) ?? isoFractional.date(from: string)
    }

    // MARK: Functions

    func `import`(from data: Data, for userID: UUID, on db: any Database) async throws -> ImportResult {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw ImportError
                .invalidFormat(
                    #"This doesn't look like a Stash JSON export (expected an object with a "bookmarks" array)."#
                )
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

        var smartViewsImported = 0
        var smartViewsUpdated = 0
        var smartViewsSkipped = 0

        for (index, record) in (document.smartViews ?? []).enumerated() {
            let position = index + 1

            let name: String
            let matchMode: String
            let conditions: [SmartViewCondition]
            do {
                name = try SmartViewController.validatedName(record.name ?? "")
                matchMode = try SmartViewController.validatedMatchMode(record.matchMode)
                conditions = try SmartViewController.validatedConditions(
                    (record.conditions ?? [])
                        .map { SmartViewConditionPayload(type: $0.type ?? "", value: $0.value ?? "") }
                )
            } catch {
                smartViewsSkipped += 1
                let reason = (error as? APIError)?.reason ?? "could not be imported."
                errors.append("Smart View \(position): \(reason)")
                continue
            }

            if let existing = try await SmartView.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$name == name)
                .first()
            {
                existing.matchMode = matchMode
                existing.conditions = conditions
                try await existing.save(on: db)
                smartViewsUpdated += 1
            } else {
                let smartView = SmartView(userID: userID, name: name, conditions: conditions, matchMode: matchMode)
                try await smartView.save(on: db)
                smartViewsImported += 1
            }
        }

        return ImportResult(
            imported: imported,
            updated: updated,
            skipped: skipped,
            smartViewsImported: smartViewsImported,
            smartViewsUpdated: smartViewsUpdated,
            smartViewsSkipped: smartViewsSkipped,
            errors: errors
        )
    }
}
