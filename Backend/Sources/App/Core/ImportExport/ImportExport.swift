// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Vapor

// MARK: - BookmarkImporter

/// A pluggable bookmark importer. Add a new format by conforming a type and registering it in
/// `ImportExportRegistry`; no controller changes required.
protocol BookmarkImporter: Sendable {

    // MARK: Static Computed Properties

    static var identifier: String { get }
    static var displayName: String { get }
    static var fileExtension: String { get }

    // MARK: Functions

    func `import`(from data: Data, for userID: UUID, on db: any Database) async throws -> ImportResult
}

// MARK: - BookmarkExporter

/// A pluggable bookmark exporter. Add a new format by conforming a type and registering it.
protocol BookmarkExporter: Sendable {

    // MARK: Static Computed Properties

    static var identifier: String { get }
    static var displayName: String { get }
    static var fileExtension: String { get }
    static var mimeType: String { get }

    // MARK: Functions

    func export(for userID: UUID, on db: any Database) async throws -> Data
}

// MARK: - ImportResult

/// Outcome of an import run. The `smartViews*` counts default to zero so importers that only
/// handle bookmarks (e.g. Anybox) need not set them.
struct ImportResult {

    // MARK: Properties

    let imported: Int
    let updated: Int
    let skipped: Int
    let smartViewsImported: Int
    let smartViewsUpdated: Int
    let smartViewsSkipped: Int
    let errors: [String]

    // MARK: Lifecycle

    init(
        imported: Int,
        updated: Int,
        skipped: Int,
        smartViewsImported: Int = 0,
        smartViewsUpdated: Int = 0,
        smartViewsSkipped: Int = 0,
        errors: [String]
    ) {
        self.imported = imported
        self.updated = updated
        self.skipped = skipped
        self.smartViewsImported = smartViewsImported
        self.smartViewsUpdated = smartViewsUpdated
        self.smartViewsSkipped = smartViewsSkipped
        self.errors = errors
    }
}

// MARK: - ImportError

/// Thrown when a file cannot be parsed at all (wrong format / invalid JSON). Individual bad
/// records are reported via `ImportResult.skipped`/`.errors`, not by throwing.
enum ImportError: Error, CustomStringConvertible {

    case invalidFormat(String)

    // MARK: Computed Properties

    var description: String {
        switch self {
        case let .invalidFormat(message): message
        }
    }
}

// MARK: - FormatOption

/// A registered format option (identifier + display name) for the UI selectors.
struct FormatOption: Content {

    let identifier: String
    let displayName: String
}

// MARK: - ExportSupport

/// Shared plumbing for `BookmarkExporter` conformers, so every format fetches, dates, and encodes
/// consistently.
enum ExportSupport {

    // MARK: Static Properties

    /// Shared ISO-8601 formatter for `dateAdded`/`createdAt`/`updatedAt` fields.
    static let iso8601 = ISO8601DateFormatter()

    // MARK: Static Functions

    /// All of a user's bookmarks (archived included), stably sorted `createdAt` ascending with
    /// `id` as a tie-breaker.
    static func sortedBookmarks(for userID: UUID, on db: any Database) async throws -> [Bookmark] {
        try await Bookmark.query(on: db)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .ascending)
            .sort(\.$id, .ascending)
            .all()
    }

    /// A `JSONEncoder` configured with the shared export formatting (pretty-printed, sorted keys,
    /// unescaped slashes).
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
