// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Vapor

// MARK: - WaybackStatus

/// The lifecycle state of a bookmark's Wayback Machine submission. `none` until a submission is
/// requested, `pending` while queued or in flight, `archived` once a snapshot exists, `failed` when
/// the last attempt didn't succeed (retryable). Distinct from `Bookmark.isArchived`, which is
/// Stash's own unrelated archive/inbox flag.
enum WaybackStatus: String, Codable {

    case none
    case pending
    case archived
    case failed
}

// MARK: - Bookmark

/// A saved bookmark, scoped to a single user. See PRD §7.2.
final class Bookmark: Model, Content, @unchecked Sendable {

    // MARK: Static Properties

    static let schema = "bookmarks"
    static let untaggedSentinel = "__untagged__"
    static let todaySentinel = "__today__"
    static let thisWeekSentinel = "__this_week__"
    static let readLaterSentinel = "__read_later__"

    // MARK: Properties

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "url")
    var url: String

    @Field(key: "title")
    var title: String

    @OptionalField(key: "description")
    var description: String?

    @OptionalField(key: "favicon_url")
    var faviconURL: String?

    @Field(key: "tags")
    var tags: [String]

    @Field(key: "tags_search")
    var tagsSearch: String

    @Field(key: "is_archived")
    var isArchived: Bool

    /// Marked to read later. Independent of `isArchived` — neither flag clears the other.
    @Field(key: "is_read_later")
    var isReadLater: Bool

    @Field(key: "wayback_status")
    var waybackStatus: WaybackStatus

    @OptionalField(key: "wayback_url")
    var waybackURL: String?

    @OptionalField(key: "wayback_archived_at")
    var waybackArchivedAt: Date?

    /// Consecutive `429` (rate-limited) attempts since the last successful submission or give-up.
    /// Internal bookkeeping for `WaybackSubmitter`, not exposed via the API — reset to `0` whenever
    /// the bookmark leaves the retry loop (archived, or gives up and becomes failed).
    @Field(key: "wayback_retry_count")
    var waybackRetryCount: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    // MARK: Lifecycle

    init() {}

    init(
        id: UUID? = nil,
        userID: User.IDValue,
        url: String,
        title: String,
        description: String? = nil,
        faviconURL: String? = nil,
        tags: [String] = [],
        isArchived: Bool = false,
        isReadLater: Bool = false,
        waybackStatus: WaybackStatus = .none,
        waybackURL: String? = nil,
        waybackArchivedAt: Date? = nil,
        waybackRetryCount: Int = 0
    ) {
        self.id = id
        $user.id = userID
        self.url = url
        self.title = title
        self.description = description
        self.faviconURL = faviconURL
        self.tags = tags
        tagsSearch = Bookmark.searchString(for: tags)
        self.isArchived = isArchived
        self.isReadLater = isReadLater
        self.waybackStatus = waybackStatus
        self.waybackURL = waybackURL
        self.waybackArchivedAt = waybackArchivedAt
        self.waybackRetryCount = waybackRetryCount
    }

    // MARK: Static Functions

    static func searchString(for tags: [String]) -> String {
        tags.isEmpty ? "" : "|" + tags.joined(separator: "|") + "|"
    }

    // MARK: Functions

    func applyTags(_ tags: [String]) {
        self.tags = tags
        tagsSearch = Bookmark.searchString(for: tags)
    }

    func asResponse() throws -> BookmarkResponse {
        try BookmarkResponse(
            id: requireID(),
            url: url,
            title: title,
            description: description,
            faviconURL: faviconURL,
            tags: tags,
            isArchived: isArchived,
            isReadLater: isReadLater,
            waybackStatus: waybackStatus.rawValue,
            waybackURL: waybackURL,
            waybackArchivedAt: waybackArchivedAt,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }
}

// MARK: - Validation & normalization

extension Bookmark {

    static func validatedURL(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else {
            throw APIError.validationFailed("A valid http(s) URL is required.")
        }

        return trimmed
    }

    static func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let tag = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .replacingOccurrences(of: "|", with: "")
            guard !tag.isEmpty else { continue }

            if seen.insert(tag).inserted {
                result.append(tag)
            }
        }
        return result
    }

    /// Splits a free-text tag field (comma- or whitespace-separated, as the web forms submit it) and
    /// normalizes the result.
    static func normalizeTags(fromFreeText raw: String) -> [String] {
        normalizeTags(raw.components(separatedBy: CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines)))
    }

    /// Whether `tag` is one of the synthetic "Views" filters (Untagged/Today/This Week/To Read)
    /// rather than a real, storable tag.
    static func isSentinelTag(_ tag: String) -> Bool {
        [untaggedSentinel, todaySentinel, thisWeekSentinel, readLaterSentinel].contains(tag)
    }

    static func normalizeTagQuery(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "|", with: "")
    }

    static func dateBoundaries(now: Date = Date()) -> (today: Date, week: Date) {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today

        return (today, week)
    }

    /// Folds a set of bookmarks into per-tag counts: `visible` counts only non-archived bookmarks,
    /// `total` counts all (and its keys are the user's distinct tag names). The single reducer behind
    /// the web sidebar, the tag browser, and tag autocomplete.
    static func tagCounts(in bookmarks: [Bookmark]) -> (visible: [String: Int], total: [String: Int]) {
        var visible: [String: Int] = [:]
        var total: [String: Int] = [:]
        for bookmark in bookmarks {
            for tag in bookmark.tags {
                total[tag, default: 0] += 1
                if !bookmark.isArchived {
                    visible[tag, default: 0] += 1
                }
            }
        }
        return (visible, total)
    }
}

extension String {

    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
