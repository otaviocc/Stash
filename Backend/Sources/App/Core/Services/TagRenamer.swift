// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

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
