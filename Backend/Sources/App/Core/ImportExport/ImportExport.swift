// MIT License
//
// Copyright (c) 2026 Otávio C.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Fluent
import Foundation
import Vapor

// MARK: - BookmarkImporter

/// A pluggable bookmark importer. Add a new format by conforming a type and registering it in
/// `ImportExportRegistry` — no controller changes required.
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
