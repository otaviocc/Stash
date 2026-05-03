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

/// Exports all of a user's bookmarks (archived included) in Stash's native JSON format,
/// sorted by `createdAt` ascending.
struct StashJSONExporter: BookmarkExporter {

    // MARK: Nested Types

    /// Top-level export envelope wrapping the format version and the bookmark items.
    private struct Document: Encodable {

        let version: String
        let exportedAt: String
        let bookmarks: [Item]
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

        let document = Document(version: "1", exportedAt: iso.string(from: Date()), bookmarks: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }
}
