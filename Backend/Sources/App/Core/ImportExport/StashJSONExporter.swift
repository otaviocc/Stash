// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

/// Exports all of a user's bookmarks (archived included) in Stash's native JSON format,
/// sorted by `createdAt` ascending.
struct StashJSONExporter: BookmarkExporter {

    // MARK: Nested Types

    /// Top-level export envelope wrapping the format version, the bookmark items, and the
    /// user's Smart Views.
    private struct Document: Encodable {

        let version: String
        let exportedAt: String
        let bookmarks: [Item]
        let smartViews: [SmartViewItem]
    }

    /// A single bookmark serialized into the Stash JSON shape.
    private struct Item: Encodable {

        let id: String
        let url: String
        let title: String
        let description: String?
        let tags: [String]
        let faviconURL: String?
        let isArchived: Bool
        let createdAt: String
        let updatedAt: String
    }

    /// A single Smart View serialized into the Stash JSON shape.
    private struct SmartViewItem: Encodable {

        let id: String
        let name: String
        let matchMode: String
        let conditions: [ConditionItem]
        let createdAt: String
        let updatedAt: String
    }

    /// A single Smart View condition: a `{ type, value }` pair, matching the API wire shape.
    private struct ConditionItem: Encodable {

        let type: String
        let value: String
    }

    // MARK: Static Properties

    static let identifier = "stash-json"
    static let displayName = "Stash JSON"
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
        let items = try bookmarks.map { bookmark in
            try Item(
                id: bookmark.requireID().uuidString,
                url: bookmark.url,
                title: bookmark.title,
                description: bookmark.description,
                tags: bookmark.tags,
                faviconURL: bookmark.faviconURL,
                isArchived: bookmark.isArchived,
                createdAt: iso.string(from: bookmark.createdAt ?? Date()),
                updatedAt: iso.string(from: bookmark.updatedAt ?? Date())
            )
        }

        let smartViews = try await SmartView.query(on: db)
            .filter(\.$user.$id == userID)
            .sort(\.$name, .ascending)
            .all()

        let smartViewItems = try smartViews.map { smartView in
            try SmartViewItem(
                id: smartView.requireID().uuidString,
                name: smartView.name,
                matchMode: smartView.matchMode,
                conditions: smartView.conditions.map { ConditionItem(type: $0.typeString, value: $0.valueString) },
                createdAt: iso.string(from: smartView.createdAt ?? Date()),
                updatedAt: iso.string(from: smartView.updatedAt ?? Date())
            )
        }

        let document = Document(
            version: "1",
            exportedAt: iso.string(from: Date()),
            bookmarks: items,
            smartViews: smartViewItems
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }
}
