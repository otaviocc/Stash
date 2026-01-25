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

/// Renames a tag (and its hierarchical children) across a single user's bookmarks. Shared by the
/// JSON API (`POST /api/v1/tags/rename`) and the web tag browser so both behave identically.
enum TagRenamer {

    // MARK: Nested Types

    /// Outcome of a tag rename: the normalized source/target names and how many bookmarks changed.
    struct Result {

        let from: String
        let to: String
        let affectedBookmarks: Int
    }

    // MARK: Static Functions

    static func rename(
        rawFrom: String,
        rawTo: String,
        for userID: UUID,
        on db: any Database
    ) async throws -> Result {
        let from = Bookmark.normalizeTagQuery(rawFrom)
        let to = Bookmark.normalizeTagQuery(rawTo)

        guard !from.isEmpty, !to.isEmpty else {
            throw APIError.validationFailed("Both 'from' and 'to' must be non-empty tag names.")
        }
        guard from != to else {
            return Result(from: from, to: to, affectedBookmarks: 0)
        }

        let candidates = try await Bookmark.query(on: db)
            .filter(\.$user.$id == userID)
            .group(.or) { group in
                group.filter(\.$tagsSearch ~~ "|\(from)|")
                group.filter(\.$tagsSearch ~~ "|\(from)/")
            }
            .all()

        var affected = 0
        for bookmark in candidates {
            let renamed = renameTags(bookmark.tags, from: from, to: to)
            if renamed != bookmark.tags {
                bookmark.applyTags(renamed)
                try await bookmark.save(on: db)
                affected += 1
            }
        }

        return Result(from: from, to: to, affectedBookmarks: affected)
    }

    static func renameTags(_ tags: [String], from: String, to: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let renamed: String = if tag == from {
                to
            } else if tag.hasPrefix(from + "/") {
                to + String(tag.dropFirst(from.count))
            } else {
                tag
            }
            if seen.insert(renamed).inserted {
                result.append(renamed)
            }
        }
        return result
    }
}
