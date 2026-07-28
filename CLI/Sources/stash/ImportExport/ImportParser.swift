// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

// MARK: - ImportFormat

/// The file formats the CLI can import.
enum ImportFormat: String, CaseIterable {

    case anybox
    case stashJSON = "stash-json"
}

// MARK: - ParsedBookmark

/// A single bookmark parsed from an import file, before validation and submission.
struct ParsedBookmark {

    var url: String?
    var title: String?
    var description: String?
    var tags: [String]
    var isArchived: Bool
    var isReadLater: Bool
}

// MARK: - ParsedSmartView

/// A single Smart View parsed from an import file, before validation and submission.
struct ParsedSmartView {

    var name: String?
    var matchMode: String?
    var conditions: [SmartViewConditionDTO]
}

// MARK: - ParsedImport

/// The bookmarks and Smart Views parsed from an import file. Anybox imports carry no Smart Views.
struct ParsedImport {

    var bookmarks: [ParsedBookmark]
    var smartViews: [ParsedSmartView]
}

// MARK: - ImportParser

/// Parses Anybox and Stash JSON exports into a common `ParsedImport` (bookmarks plus, for Stash
/// JSON, Smart Views), re-implementing the backend's importer field mapping locally because the
/// import endpoint is web-only (PRD §13).
///
/// Anybox stores `tags` as arrays of `[namespace, value]` pairs joined with `/`; a plain `[String]`
/// is accepted as a fallback, and Anybox carries no Smart Views. Validation, duplicate handling,
/// and submission are the caller's job.
enum ImportParser {

    static func parse(_ data: Data, format: ImportFormat) throws -> ParsedImport {
        switch format {
        case .anybox:
            try parseAnybox(data)
        case .stashJSON:
            try parseStashJSON(data)
        }
    }

    private static func parseAnybox(_ data: Data) throws -> ParsedImport {
        let records: [AnyboxRecord]
        do {
            records = try JSONDecoder().decode([AnyboxRecord].self, from: data)
        } catch {
            throw CLIError("This doesn't look like an Anybox JSON export (expected a JSON array of bookmarks).")
        }

        let bookmarks = records.map { record in
            ParsedBookmark(
                url: record.url,
                title: record.title,
                description: record.description,
                tags: record.tags,
                isArchived: false,
                isReadLater: false
            )
        }

        return ParsedImport(bookmarks: bookmarks, smartViews: [])
    }

    private static func parseStashJSON(_ data: Data) throws -> ParsedImport {
        let document: StashDocument
        do {
            document = try JSONDecoder().decode(StashDocument.self, from: data)
        } catch {
            throw CLIError(
                #"This doesn't look like a Stash JSON export (expected an object with a "bookmarks" array)."#
            )
        }

        let bookmarks = document.bookmarks.map { record in
            ParsedBookmark(
                url: record.url,
                title: record.title,
                description: record.description,
                tags: record.tags ?? [],
                isArchived: record.isArchived ?? false,
                isReadLater: record.isReadLater ?? false
            )
        }

        let smartViews = (document.smartViews ?? []).map { record in
            ParsedSmartView(
                name: record.name,
                matchMode: record.matchMode,
                conditions: (record.conditions ?? []).map { SmartViewConditionDTO(
                    type: $0.type ?? "",
                    value: $0.value ?? ""
                ) }
            )
        }

        return ParsedImport(bookmarks: bookmarks, smartViews: smartViews)
    }
}

// MARK: - AnyboxTag

/// A tag entry that may be a string or a `[namespace, value]` array (Anybox uses the latter).
private struct AnyboxTag: Decodable {

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

// MARK: - AnyboxRecord

/// A single decoded Anybox bookmark record.
private struct AnyboxRecord: Decodable {

    // MARK: Nested Types

    private enum CodingKeys: String, CodingKey {

        case url, title, description, tags
    }

    // MARK: Properties

    let url: String?
    let title: String?
    let description: String?
    let tags: [String]

    // MARK: Lifecycle

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        description = try? container.decodeIfPresent(String.self, forKey: .description)

        let rawTags = (try? container.decodeIfPresent([AnyboxTag].self, forKey: .tags)) ?? []
        tags = rawTags.compactMap(\.value)
    }
}

// MARK: - StashDocument

/// The top-level Stash JSON export envelope.
private struct StashDocument: Decodable {

    let bookmarks: [StashRecord]
    let smartViews: [StashSmartViewRecord]?
}

// MARK: - StashRecord

/// A single decoded Stash JSON bookmark record.
private struct StashRecord: Decodable {

    let url: String?
    let title: String?
    let description: String?
    let tags: [String]?
    let isArchived: Bool?
    let isReadLater: Bool?
}

// MARK: - StashSmartViewRecord

/// A single decoded Stash JSON Smart View record.
private struct StashSmartViewRecord: Decodable {

    let name: String?
    let matchMode: String?
    let conditions: [StashConditionRecord]?
}

// MARK: - StashConditionRecord

/// A single decoded Smart View condition: a `{ type, value }` pair.
private struct StashConditionRecord: Decodable {

    let type: String?
    let value: String?
}
