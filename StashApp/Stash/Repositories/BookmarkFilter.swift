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
import StashKit

// MARK: - BookmarkFilter

/// Evaluates the bookmark list query and Smart View rules in memory, mirroring the backend's
/// SQL filters so a local read returns the same set the server would.
///
/// The backend matches case-insensitively with escaped `LIKE`, filters tags against a pipe-wrapped
/// `tags_search` string (`|swift|swift/server|`), honors the `__untagged__` / `__today__` /
/// `__this_week__` sentinels, and sorts newest-first by `createdAt` then `id`. These helpers reproduce
/// that behavior over the local `Bookmark` copies. See `QueryBuilder+Search` and `SmartView` on the
/// backend.
enum BookmarkFilter {

    static func dateBoundaries(now: Date = Date()) -> (today: Date, week: Date) {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today

        return (today, week)
    }

    static func newestFirst(_ lhs: Bookmark, _ rhs: Bookmark) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        return lhs.id.uuidString > rhs.id.uuidString
    }

    static func matches(
        _ bookmark: Bookmark,
        query: BookmarkQuery,
        boundaries: (today: Date, week: Date)
    ) -> Bool {
        guard bookmark.isArchived == query.archived else {
            return false
        }

        if let term = query.searchQuery?.trimmedNonEmpty, !matchesSearch(bookmark, term: term) {
            return false
        }

        if let tag = query.tag?.trimmedNonEmpty, !matchesTag(bookmark, rawTag: tag, boundaries: boundaries) {
            return false
        }

        return true
    }

    static func matches(
        _ bookmark: Bookmark,
        smartView: SmartView,
        boundaries: (today: Date, week: Date)
    ) -> Bool {
        let overridesArchived = smartView.conditions.contains { $0.type == SmartViewConditionType.isArchived.rawValue }

        if !overridesArchived, bookmark.isArchived {
            return false
        }

        guard !smartView.conditions.isEmpty else {
            return true
        }

        let results = smartView.conditions.map { matchesCondition(bookmark, $0, boundaries: boundaries) }

        return smartView.matchMode == "any"
            ? results.contains(true)
            : results.allSatisfy(\.self)
    }

    // MARK: Private

    private static func matchesSearch(_ bookmark: Bookmark, term: String) -> Bool {
        let needle = term.lowercased()

        if bookmark.url.absoluteString.lowercased().contains(needle) { return true }

        if bookmark.title.lowercased().contains(needle) { return true }

        if let description = bookmark.description?.lowercased(), description.contains(needle) { return true }

        return tagsSearch(bookmark.tags).contains(needle)
    }

    private static func matchesTag(
        _ bookmark: Bookmark,
        rawTag: String,
        boundaries: (today: Date, week: Date)
    ) -> Bool {
        switch rawTag {
        case BookmarkListQuery.untaggedTag:
            return bookmark.tags.isEmpty
        case BookmarkListQuery.todayTag:
            return bookmark.createdAt >= boundaries.today
        case BookmarkListQuery.thisWeekTag:
            return bookmark.createdAt >= boundaries.week
        default:
            let tag = normalizeTagQuery(rawTag)
            guard !tag.isEmpty else { return true }

            let haystack = tagsSearch(bookmark.tags)

            return haystack.contains("|\(tag)|") || haystack.contains("|\(tag)/")
        }
    }

    private static func matchesCondition(
        _ bookmark: Bookmark,
        _ condition: SmartViewCondition,
        boundaries: (today: Date, week: Date)
    ) -> Bool {
        switch SmartViewConditionType(rawValue: condition.type) {
        case .tag:
            let tag = normalizeTagQuery(condition.value)
            guard !tag.isEmpty else { return false }

            let haystack = tagsSearch(bookmark.tags)

            return haystack.contains("|\(tag)|") || haystack.contains("|\(tag)/")
        case .urlContains:
            return bookmark.url.absoluteString.lowercased().contains(condition.value.lowercased())
        case .titleContains:
            return bookmark.title.lowercased().contains(condition.value.lowercased())
        case .descriptionContains:
            return (bookmark.description ?? "").lowercased().contains(condition.value.lowercased())
        case .createdBefore:
            guard let date = parseDate(condition.value) else { return false }

            return bookmark.createdAt < date
        case .createdAfter:
            guard let date = parseDate(condition.value) else { return false }

            return bookmark.createdAt > date
        case .isArchived:
            return bookmark.isArchived == (condition.value == "true")
        case .hasTags:
            return condition.value == "true" ? !bookmark.tags.isEmpty : bookmark.tags.isEmpty
        case nil:
            return false
        }
    }

    /// The pipe-wrapped, lowercased tag string the backend stores as `tags_search` (`|a|b|`).
    private static func tagsSearch(_ tags: [String]) -> String {
        tags.isEmpty ? "" : "|" + tags.joined(separator: "|").lowercased() + "|"
    }

    /// Mirrors the backend's `Bookmark.normalizeTagQuery`: trim, lowercase, strip wrapping slashes,
    /// drop pipes.
    private static func normalizeTagQuery(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "|", with: "")
    }

    private static func parseDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return formatter.date(from: raw)
    }
}

// MARK: - String + TrimmedNonEmpty

private extension String {

    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : trimmed
    }
}
