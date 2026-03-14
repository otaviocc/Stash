import Fluent
import Foundation
import Vapor

/// A saved bookmark, scoped to a single user. See PRD §7.2.
final class Bookmark: Model, Content, @unchecked Sendable {
    static let schema = "bookmarks"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    /// Required, valid http(s) URL. Unique per user (enforced by a unique index).
    @Field(key: "url")
    var url: String

    /// Auto-fetched at save time, overridable. Falls back to the URL if nothing is available.
    @Field(key: "title")
    var title: String

    @OptionalField(key: "description")
    var description: String?

    @OptionalField(key: "favicon_url")
    var faviconURL: String?

    /// Flat or hierarchical tags (e.g. `swift/vapor`). Source of truth for the API.
    @Field(key: "tags")
    var tags: [String]

    /// Derived, delimiter-wrapped tag string used for portable prefix queries. Not exposed.
    @Field(key: "tags_search")
    var tagsSearch: String

    @Field(key: "is_archived")
    var isArchived: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

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
        self.$user.id = userID
        self.url = url
        self.title = title
        self.description = description
        self.faviconURL = faviconURL
        self.tags = tags
        self.tagsSearch = Bookmark.searchString(for: tags)
        self.isArchived = isArchived
    }

    /// Set tags and keep the derived search string in sync.
    func applyTags(_ tags: [String]) {
        self.tags = tags
        self.tagsSearch = Bookmark.searchString(for: tags)
    }

    /// Normalised, pipe-wrapped tag string used for portable prefix queries.
    /// e.g. `["swift", "swift/vapor"]` -> `"|swift|swift/vapor|"`.
    static func searchString(for tags: [String]) -> String {
        tags.isEmpty ? "" : "|" + tags.joined(separator: "|") + "|"
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

// MARK: - Validation & normalisation

extension Bookmark {
    /// Validate and normalise a URL. Throws a 422 `validation_failed` on bad input (PRD §17.4).
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

    /// Normalise tags: trim, lowercase, drop surrounding slashes, strip the `|` delimiter,
    /// drop empties, and de-duplicate while preserving order.
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

    /// Normalise a `tag` query value the same way stored tags are normalised.
    static func normalizeTagQuery(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "|", with: "")
    }
}

extension String {
    /// The trimmed string, or nil if it is empty after trimming.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
