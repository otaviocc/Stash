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
import Vapor

// MARK: - Bookmark

/// A saved bookmark, scoped to a single user. See PRD §7.2.
final class Bookmark: Model, Content, @unchecked Sendable {

    // MARK: Static Properties

    static let schema = "bookmarks"
    static let untaggedSentinel = "__untagged__"
    static let todaySentinel = "__today__"
    static let thisWeekSentinel = "__this_week__"

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
        isArchived: Bool = false
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

            if seen.insert(tag).inserted { result.append(tag) }
        }
        return result
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
}

extension String {

    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
