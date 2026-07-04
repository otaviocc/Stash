// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

// MARK: - ExportDocument

/// The top-level Stash JSON export envelope, matching the backend exporter (PRD §11.4).
struct ExportDocument: Encodable {

    // MARK: Properties

    let version: String
    let exportedAt: String
    let bookmarks: [ExportItem]
    let smartViews: [ExportSmartViewItem]

    // MARK: Lifecycle

    init(bookmarks: [BookmarkDTO], smartViews: [SmartViewDTO], exportedAt: Date) {
        let formatter = ISO8601DateFormatter()
        version = "1"
        self.exportedAt = formatter.string(from: exportedAt)
        self.bookmarks = bookmarks
            .sorted { $0.createdAt < $1.createdAt }
            .map { ExportItem(bookmark: $0, formatter: formatter) }
        self.smartViews = smartViews
            .sorted { $0.name < $1.name }
            .map { ExportSmartViewItem(smartView: $0, formatter: formatter) }
    }

    // MARK: Functions

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        return try encoder.encode(self)
    }
}

// MARK: - ExportItem

/// A single bookmark serialized into the Stash JSON shape.
struct ExportItem: Encodable {

    // MARK: Properties

    let id: String
    let url: String
    let title: String
    let description: String?
    let tags: [String]
    let faviconURL: String?
    let isArchived: Bool
    let createdAt: String
    let updatedAt: String

    // MARK: Lifecycle

    init(bookmark: BookmarkDTO, formatter: ISO8601DateFormatter) {
        id = bookmark.id.uuidString
        url = bookmark.url.absoluteString
        title = bookmark.title
        description = bookmark.description
        tags = bookmark.tags
        faviconURL = bookmark.faviconURL?.absoluteString
        isArchived = bookmark.isArchived
        createdAt = formatter.string(from: bookmark.createdAt)
        updatedAt = formatter.string(from: bookmark.updatedAt)
    }
}

// MARK: - ExportSmartViewItem

/// A single Smart View serialized into the Stash JSON shape.
struct ExportSmartViewItem: Encodable {

    // MARK: Properties

    let id: String
    let name: String
    let matchMode: String
    let conditions: [SmartViewConditionDTO]
    let createdAt: String
    let updatedAt: String

    // MARK: Lifecycle

    init(smartView: SmartViewDTO, formatter: ISO8601DateFormatter) {
        id = smartView.id.uuidString
        name = smartView.name
        matchMode = smartView.matchMode
        conditions = smartView.conditions
        createdAt = formatter.string(from: smartView.createdAt)
        updatedAt = formatter.string(from: smartView.updatedAt)
    }
}
