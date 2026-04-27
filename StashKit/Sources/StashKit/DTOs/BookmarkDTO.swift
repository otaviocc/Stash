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

// MARK: - BookmarkDTO

/// A saved bookmark as returned by the API.
public struct BookmarkDTO: Codable, Identifiable, Sendable {

    public let id: UUID
    public let url: URL
    public let title: String
    public let description: String?
    public let faviconURL: URL?
    public let tags: [String]
    public let isArchived: Bool
    public let createdAt: Date
    public let updatedAt: Date
}

/// A paginated list of bookmarks.
public typealias BookmarkPageDTO = PageDTO<BookmarkDTO>

// MARK: - ChangesPageDTO

/// A keyset-paginated page of bookmark changes (`GET /bookmarks/changes`). `nextAfterUpdatedAt` is an
/// opaque continuation token (a server-formatted timestamp) the client echoes back verbatim alongside
/// `nextAfterId` to fetch the next page — it is never interpreted client-side, so no date-precision is
/// lost across the round-trip.
public struct ChangesPageDTO: Codable, Sendable {

    public let items: [BookmarkDTO]
    public let hasMore: Bool
    public let nextAfterUpdatedAt: String?
    public let nextAfterId: UUID?
}

// MARK: - DeletedBookmarkDTO

/// A tombstone record for a server-side bookmark deletion. `id` is the deleted
/// bookmark's ID, so a client can match it against its local copy and remove it.
public struct DeletedBookmarkDTO: Codable, Identifiable, Sendable {

    public let id: UUID
    public let deletedAt: Date
}
