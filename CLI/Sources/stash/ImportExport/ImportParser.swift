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

import Foundation

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
}

// MARK: - ImportParser

/// Parses Anybox and Stash JSON exports into a common `[ParsedBookmark]`, re-implementing the
/// backend's importer field mapping locally because the import endpoint is web-only (PRD §13).
///
/// Anybox stores `tags` as arrays of `[namespace, value]` pairs joined with `/`; a plain `[String]`
/// is accepted as a fallback. Validation, duplicate handling, and submission are the caller's job.
enum ImportParser {

    static func parse(_ data: Data, format: ImportFormat) throws -> [ParsedBookmark] {
        switch format {
        case .anybox:
            try parseAnybox(data)
        case .stashJSON:
            try parseStashJSON(data)
        }
    }

    private static func parseAnybox(_ data: Data) throws -> [ParsedBookmark] {
        let records: [AnyboxRecord]
        do {
            records = try JSONDecoder().decode([AnyboxRecord].self, from: data)
        } catch {
            throw CLIError("This doesn't look like an Anybox JSON export (expected a JSON array of bookmarks).")
        }

        return records.map { record in
            ParsedBookmark(
                url: record.url,
                title: record.title,
                description: record.description,
                tags: record.tags,
                isArchived: false
            )
        }
    }

    private static func parseStashJSON(_ data: Data) throws -> [ParsedBookmark] {
        let document: StashDocument
        do {
            document = try JSONDecoder().decode(StashDocument.self, from: data)
        } catch {
            throw CLIError(
                #"This doesn't look like a Stash JSON export (expected an object with a "bookmarks" array)."#
            )
        }

        return document.bookmarks.map { record in
            ParsedBookmark(
                url: record.url,
                title: record.title,
                description: record.description,
                tags: record.tags ?? [],
                isArchived: record.isArchived ?? false
            )
        }
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
}

// MARK: - StashRecord

/// A single decoded Stash JSON bookmark record.
private struct StashRecord: Decodable {

    let url: String?
    let title: String?
    let description: String?
    let tags: [String]?
    let isArchived: Bool?
}
