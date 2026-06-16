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

/// Deletes a tag (and its hierarchical children) across a single user's bookmarks. Shared by the
/// JSON API (`DELETE /api/v1/tags/:tag`) and the web tag browser so both behave identically.
enum TagDeleter {

    // MARK: Nested Types

    /// Outcome of a tag deletion: the normalized tag and how many bookmarks changed.
    struct Result {

        let tag: String
        let affectedBookmarks: Int
    }

    // MARK: Static Functions

    static func delete(
        rawTag: String,
        for userID: UUID,
        on db: any Database
    ) async throws -> Result {
        let tag = Bookmark.normalizeTagQuery(rawTag)

        guard !tag.isEmpty else {
            throw APIError.validationFailed("Tag must be a non-empty tag name.")
        }

        let candidates = try await Bookmark.query(on: db)
            .filter(\.$user.$id == userID)
            .group(.or) { group in
                group.filter(\.$tagsSearch ~~ "|\(tag)|")
                group.filter(\.$tagsSearch ~~ "|\(tag)/")
            }
            .all()

        var affected = 0
        for bookmark in candidates {
            let remaining = removeTag(bookmark.tags, tag: tag)
            if remaining != bookmark.tags {
                bookmark.applyTags(remaining)
                try await bookmark.save(on: db)
                affected += 1
            }
        }

        return Result(tag: tag, affectedBookmarks: affected)
    }

    static func removeTag(_ tags: [String], tag: String) -> [String] {
        tags.filter { $0 != tag && !$0.hasPrefix(tag + "/") }
    }
}
