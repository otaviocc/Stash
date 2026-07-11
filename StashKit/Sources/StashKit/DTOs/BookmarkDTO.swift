// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - WaybackStatusDTO

/// The lifecycle of a bookmark's Internet Archive (Wayback Machine) submission. Unrelated to
/// `BookmarkDTO.isArchived`, which is Stash's own archive/inbox flag.
public enum WaybackStatusDTO: String, Codable, Sendable {

    case none
    case pending
    case archived
    case failed
}

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
    public let waybackStatus: WaybackStatusDTO
    public let waybackURL: URL?
    public let waybackArchivedAt: Date?
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
