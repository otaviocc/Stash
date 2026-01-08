import Vapor

// MARK: - Requests

/// `POST /bookmarks` body (PRD §9.3). `title`/`description` auto-fetched when omitted
/// and `fetchMetadata` is true (default).
struct CreateBookmarkInput: Content {
    let url: String
    let title: String?
    let description: String?
    let tags: [String]?
    let fetchMetadata: Bool?
}

/// `PUT /bookmarks/:id` body — all fields optional; omitted fields are left unchanged.
struct UpdateBookmarkInput: Content {
    let url: String?
    let title: String?
    let description: String?
    let tags: [String]?
    let isArchived: Bool?
}

/// `GET /bookmarks` query parameters (PRD §9.3).
struct BookmarkListQuery: Content {
    let q: String?
    let tag: String?
    let archived: Bool?
    let page: Int?
    let per: Int?
}

/// `POST /metadata` body (PRD §9.5).
struct MetadataRequest: Content {
    let url: String
}

// MARK: - Responses

struct BookmarkResponse: Content {
    let id: UUID
    let url: String
    let title: String
    let description: String?
    let faviconURL: String?
    let tags: [String]
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
}

/// A tag with its bookmark count (PRD §9.4).
struct TagCount: Content {
    let name: String
    let count: Int
}

/// `POST /metadata` response (PRD §9.5).
struct MetadataResponse: Content {
    let title: String?
    let description: String?
    let faviconURL: String?
}
