import Fluent
import Foundation
import Vapor

/// A pluggable bookmark importer. Add a new format by conforming a type and registering it in
/// `ImportExportRegistry` — no controller changes required.
protocol BookmarkImporter: Sendable {
    /// Stable machine identifier, e.g. `"anybox"`.
    static var identifier: String { get }
    /// Human-facing name shown in the format selector, e.g. `"Anybox JSON"`.
    static var displayName: String { get }
    /// Expected file extension (no dot), e.g. `"json"`.
    static var fileExtension: String { get }

    func `import`(from data: Data, for userID: UUID, on db: any Database) async throws -> ImportResult
}

/// A pluggable bookmark exporter. Add a new format by conforming a type and registering it.
protocol BookmarkExporter: Sendable {
    static var identifier: String { get }
    static var displayName: String { get }
    static var fileExtension: String { get }
    static var mimeType: String { get }

    func export(for userID: UUID, on db: any Database) async throws -> Data
}

/// Outcome of an import run.
struct ImportResult {
    /// New bookmarks created.
    let imported: Int
    /// Existing bookmarks updated (matched by URL).
    let updated: Int
    /// Records skipped (invalid URL, missing required fields).
    let skipped: Int
    /// Human-readable descriptions of the skipped records.
    let errors: [String]
}

/// Thrown when a file cannot be parsed at all (wrong format / invalid JSON). Individual bad
/// records are reported via `ImportResult.skipped`/`.errors`, not by throwing.
enum ImportError: Error, CustomStringConvertible {
    case invalidFormat(String)

    var description: String {
        switch self {
        case let .invalidFormat(message): return message
        }
    }
}

/// A registered format option (identifier + display name) for the UI selectors.
struct FormatOption: Content {
    let identifier: String
    let displayName: String
}
