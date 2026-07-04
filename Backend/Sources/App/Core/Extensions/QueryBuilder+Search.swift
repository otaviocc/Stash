// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import FluentSQL
import Foundation
import SQLKit

// MARK: - QueryBuilder + BookmarkSearch

extension QueryBuilder where Model == Bookmark {

    /// Adds a case-insensitive `OR` group matching `term` against the URL, title, description, and
    /// derived tag-search column.
    ///
    /// Matching is case-insensitive and portable across SQLite (tests) and PostgreSQL (production):
    /// the column is lowered before a `LIKE` comparison against a lowered, bound term. PostgreSQL's
    /// `LIKE` is otherwise case-sensitive, which the PRD's full-text search (§9.3, "ILIKE on
    /// PostgreSQL") does not want. `LIKE` metacharacters in the term are escaped, so `%` and `_`
    /// match as literal characters rather than acting as wildcards.
    @discardableResult
    func filterFullText(_ term: String) -> Self {
        let pattern = likeContainsPattern(term)

        return group(.or) { group in
            for column in ["url", "title", "description", "tags_search"] {
                group.filter(.sql(likeContainsExpression(column: column, pattern: pattern)))
            }
        }
    }

    /// Adds a case-insensitive "contains" filter against a single column, using the same portable,
    /// metacharacter-escaped `lower(column) LIKE` approach as `filterFullText` (Smart Views, the
    /// `urlContains` / `titleContains` / `descriptionContains` conditions).
    @discardableResult
    func filterColumn(_ column: String, contains value: String) -> Self {
        filter(.sql(likeContainsExpression(column: column, pattern: likeContainsPattern(value))))
    }

    /// Applies the bookmark-list `tag` filter, honoring the internal "Views" sentinels
    /// (`__untagged__`, `__today__`, `__this_week__`) before falling back to a hierarchical prefix
    /// match (`tag` matches the exact tag and its `tag/*` children). Shared by the JSON API
    /// (`BookmarkController`) and the web frontend (`BookmarkWebController`) so the two never diverge —
    /// see `DECISIONS.md`. Pass `boundaries` to reuse a value already computed for sidebar counts.
    @discardableResult
    func filterByTag(
        _ rawTag: String,
        boundaries: (today: Date, week: Date) = Bookmark.dateBoundaries()
    ) -> Self {
        switch rawTag {
        case Bookmark.untaggedSentinel:
            return filter(\.$tagsSearch == "")
        case Bookmark.todaySentinel:
            return filter(\.$createdAt >= boundaries.today)
        case Bookmark.thisWeekSentinel:
            return filter(\.$createdAt >= boundaries.week)
        default:
            let tag = Bookmark.normalizeTagQuery(rawTag)
            guard !tag.isEmpty else { return self }

            return group(.or) { group in
                group.filter(\.$tagsSearch ~~ "|\(tag)|")
                group.filter(\.$tagsSearch ~~ "|\(tag)/")
            }
        }
    }
}

private func likeContainsPattern(_ raw: String) -> String {
    let escaped = raw.lowercased()
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "%", with: "\\%")
        .replacingOccurrences(of: "_", with: "\\_")

    return "%\(escaped)%"
}

private func likeContainsExpression(column: String, pattern: String) -> SQLExpression {
    let expression: SQLQueryString = "lower(\(ident: column)) LIKE \(bind: pattern) ESCAPE '\\'"

    return expression
}
