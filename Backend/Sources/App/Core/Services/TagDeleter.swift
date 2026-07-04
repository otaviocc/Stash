// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

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
