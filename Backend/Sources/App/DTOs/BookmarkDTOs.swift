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
}

// MARK: - UpdateBookmarkInput

/// `PUT /bookmarks/:id` body — all fields optional; omitted fields are left unchanged.
struct UpdateBookmarkInput: Content {

    let url: String?
    let title: String?
    let description: String?
    let tags: [String]?
    let isArchived: Bool?
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
