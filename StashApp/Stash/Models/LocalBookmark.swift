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
import SwiftData

// MARK: - LocalBookmark

/// A locally persisted bookmark, mirroring the server model with sync metadata.
///
/// The SwiftData store holds a full copy of the user's bookmarks so the app can read offline. `id` is
/// a local UUID used as the SwiftData primary key — stable for SwiftUI identity even before the server
/// confirms a record — while `serverID` is the identifier used to match against the server during
/// sync. The sync-metadata fields (`pendingSyncAt`, `locallyDeletedAt`, `isLocalOnly`) exist for the
/// offline write queue; in this version every write reaches the server immediately, so they stay clean.
@Model
final class LocalBookmark {

    // MARK: Properties

    @Attribute(.unique) var id: UUID

    @Attribute(.unique) var serverID: UUID
    var url: String
    var title: String
    var bookmarkDescription: String?
    var tags: [String]
    var isArchived: Bool
    var faviconDomain: String?
    var serverCreatedAt: Date
    var serverUpdatedAt: Date

    /// Set when the bookmark was modified offline. Cleared after a successful push.
    var pendingSyncAt: Date?

    /// Set when the bookmark was deleted offline. Kept until the `DELETE` is pushed.
    var locallyDeletedAt: Date?

    /// True until the first successful push assigns a real server ID.
    var isLocalOnly: Bool

    // MARK: Lifecycle

    init(from dto: BookmarkDTO) {
        id = UUID()
        serverID = dto.id
        url = dto.url.absoluteString
        title = dto.title
        bookmarkDescription = dto.description
        tags = dto.tags
        isArchived = dto.isArchived
        faviconDomain = Self.faviconDomain(for: dto.url)
        serverCreatedAt = dto.createdAt
        serverUpdatedAt = dto.updatedAt
        pendingSyncAt = nil
        locallyDeletedAt = nil
        isLocalOnly = false
    }

    /// Builds a brand-new record from an offline create. It carries a temporary `serverID` and is
    /// flagged `isLocalOnly` + `pendingSyncAt` until the push assigns a real server ID.
    init(localCreate input: CreateBookmarkInput, now: Date) {
        let trimmedTitle = input.title?.trimmingCharacters(in: .whitespacesAndNewlines)

        id = UUID()
        serverID = UUID()
        url = input.url.absoluteString
        title = (trimmedTitle?.isEmpty == false ? trimmedTitle : nil) ?? input.url.absoluteString
        bookmarkDescription = input.description
        tags = input.tags
        isArchived = false
        faviconDomain = Self.faviconDomain(for: input.url)
        serverCreatedAt = now
        serverUpdatedAt = now
        pendingSyncAt = now
        locallyDeletedAt = nil
        isLocalOnly = true
    }

    #if DEBUG
        /// Builds a record from a domain `Bookmark` for seeding the in-memory preview store.
        init(previewBookmark bookmark: Bookmark) {
            id = UUID()
            serverID = bookmark.id
            url = bookmark.url.absoluteString
            title = bookmark.title
            bookmarkDescription = bookmark.description
            tags = bookmark.tags
            isArchived = bookmark.isArchived
            faviconDomain = Self.faviconDomain(for: bookmark.url)
            serverCreatedAt = bookmark.createdAt
            serverUpdatedAt = bookmark.updatedAt
            pendingSyncAt = nil
            locallyDeletedAt = nil
            isLocalOnly = false
        }
    #endif

    // MARK: Static Functions

    /// Cache key for Stash's favicon endpoint, matching the backend's `DomainExtractor`: lowercased
    /// host, leading `www.` stripped, explicit port kept.
    static func faviconDomain(for url: URL) -> String? {
        guard var host = url.host()?.lowercased(), !host.isEmpty else { return nil }

        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
            guard !host.isEmpty else { return nil }
        }

        if let port = url.port {
            return "\(host):\(port)"
        }

        return host
    }

    // MARK: Functions

    /// Overwrites the server-owned fields with a fresh DTO and clears the sync metadata, since the
    /// applied data is authoritative server state.
    func apply(_ dto: BookmarkDTO) {
        serverID = dto.id
        url = dto.url.absoluteString
        title = dto.title
        bookmarkDescription = dto.description
        tags = dto.tags
        isArchived = dto.isArchived
        faviconDomain = Self.faviconDomain(for: dto.url)
        serverCreatedAt = dto.createdAt
        serverUpdatedAt = dto.updatedAt
        pendingSyncAt = nil
        locallyDeletedAt = nil
        isLocalOnly = false
    }
}

// MARK: - Bookmark + LocalBookmark

extension Bookmark {

    /// Maps a persisted record to the view-facing domain model. Fails only if the stored URL string
    /// cannot be parsed — every URL is server-validated as http(s), so this is effectively total.
    init?(local: LocalBookmark) {
        guard let url = URL(string: local.url) else { return nil }

        id = local.serverID
        self.url = url
        title = local.title.isEmpty ? local.url : local.title
        description = local.bookmarkDescription
        faviconURL = nil
        tags = local.tags
        isArchived = local.isArchived
        createdAt = local.serverCreatedAt
        updatedAt = local.serverUpdatedAt
        isPendingSync = local.pendingSyncAt != nil
    }
}
