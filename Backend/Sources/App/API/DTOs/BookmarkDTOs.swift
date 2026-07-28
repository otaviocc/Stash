// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

// MARK: - CreateBookmarkInput

/// `POST /bookmarks` body (PRD §9.3). `title`/`description` auto-fetched when omitted
/// and `fetchMetadata` is true (default).
struct CreateBookmarkInput: Content {

    let url: String
    let title: String?
    let description: String?
    let tags: [String]?
    let fetchMetadata: Bool?
    let isArchived: Bool?
    let isReadLater: Bool?
}

// MARK: - ChangesPage

/// Keyset-paginated response for `GET /bookmarks/changes`. Replaces the offset-based `Page<T>`
/// envelope: `nextAfterUpdatedAt` (a fractional ISO-8601 timestamp, opaque to the client) and
/// `nextAfterId` form the `(updatedAt, id)` cursor for the next page, stable under concurrent edits.
struct ChangesPage<T: Content>: Content {

    let items: [T]
    let hasMore: Bool
    let nextAfterUpdatedAt: String?
    let nextAfterId: UUID?
}

// MARK: - UpdateBookmarkInput

/// `PUT /bookmarks/:id` body — all fields optional; omitted fields are left unchanged.
struct UpdateBookmarkInput: Content {

    let url: String?
    let title: String?
    let description: String?
    let tags: [String]?
    let isArchived: Bool?
    let isReadLater: Bool?
}

// MARK: - BookmarkListQuery

/// `GET /bookmarks` query parameters (PRD §9.3).
struct BookmarkListQuery: Content {

    let q: String?
    let tag: String?
    let archived: Bool?
    let page: Int?
    let per: Int?
}

// MARK: - MetadataRequest

/// `POST /metadata` body (PRD §9.5).
struct MetadataRequest: Content {

    let url: String
}

// MARK: - BookmarkResponse

/// Public bookmark projection returned by the API.
struct BookmarkResponse: Content {

    let id: UUID
    let url: String
    let title: String
    let description: String?
    let faviconURL: String?
    let tags: [String]
    let isArchived: Bool
    let isReadLater: Bool
    let waybackStatus: String
    let waybackURL: String?
    let waybackArchivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - DeletedBookmarkResponse

/// A tombstone record for a server-side bookmark deletion, returned by
/// `GET /bookmarks/deleted`. `id` is the deleted bookmark's ID (not the
/// tombstone's own ID), so a client can match it against a local copy.
struct DeletedBookmarkResponse: Content {

    let id: UUID
    let deletedAt: Date
}

// MARK: - TagCount

/// A tag with its bookmark count (PRD §9.4).
struct TagCount: Content {

    let name: String
    let count: Int
}

// MARK: - TagRenameRequest

/// `POST /tags/rename` body (PRD: tag renaming). Both names are normalized on receipt.
struct TagRenameRequest: Content {

    let from: String
    let to: String
}

// MARK: - TagRenameResponse

/// `POST /tags/rename` response.
struct TagRenameResponse: Content {

    let from: String
    let to: String
    let affectedBookmarks: Int
}

// MARK: - TagDeleteResponse

/// `DELETE /tags/:tag` response. The tag is normalized on receipt.
struct TagDeleteResponse: Content {

    let tag: String
    let affectedBookmarks: Int
}

// MARK: - MetadataResponse

/// `POST /metadata` response (PRD §9.5).
struct MetadataResponse: Content {

    let title: String?
    let description: String?
    let faviconURL: String?
}
