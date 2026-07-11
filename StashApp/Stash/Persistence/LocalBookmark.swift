// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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

    /// The server ID of the user who owns this record. Set at insert time from the authenticated
    /// session and never changed, so a pending offline write is only ever pushed by — and a wipe only
    /// preserves it for — the user it belongs to. Prevents one user's queued writes from syncing into
    /// another user's account on a shared device.
    var userID: String
    var url: String
    var title: String
    var bookmarkDescription: String?
    var tags: [String]
    var isArchived: Bool
    var faviconDomain: String?
    var serverCreatedAt: Date
    var serverUpdatedAt: Date

    /// The captured Internet Archive snapshot URL, mirrored from `BookmarkDTO.waybackURL`. Stored as
    /// a `String?`, matching how `url` itself is stored, rather than `URL?`.
    var waybackURL: String?

    /// Set when the bookmark was modified offline. Cleared after a successful push.
    var pendingSyncAt: Date?

    /// Set when the bookmark was deleted offline. Kept until the `DELETE` is pushed.
    var locallyDeletedAt: Date?

    /// True until the first successful push assigns a real server ID.
    var isLocalOnly: Bool

    /// Whether a server-side metadata fetch was requested for this optimistically-created bookmark.
    /// Honored when the create is pushed (`POST` with `fetchMetadata`); meaningless once synced.
    var wantsMetadataFetch = false

    /// A human-readable message set when this record's push failed with a permanent error (e.g. a
    /// 422/403 the server will always reject). Set alongside clearing `pendingSyncAt` to stop the
    /// retry loop; surfaced to the user. `nil` means no error.
    var syncError: String?

    // MARK: Lifecycle

    init(from dto: BookmarkDTO, userID: String) {
        id = UUID()
        serverID = dto.id
        self.userID = userID
        url = dto.url.absoluteString
        title = dto.title
        bookmarkDescription = dto.description
        tags = dto.tags
        isArchived = dto.isArchived
        faviconDomain = Bookmark.faviconDomain(for: dto.url)
        serverCreatedAt = dto.createdAt
        serverUpdatedAt = dto.updatedAt
        waybackURL = dto.waybackURL?.absoluteString
        pendingSyncAt = nil
        locallyDeletedAt = nil
        isLocalOnly = false
        wantsMetadataFetch = false
    }

    /// Builds a brand-new record from an offline create. It carries a temporary `serverID` and is
    /// flagged `isLocalOnly` + `pendingSyncAt` until the push assigns a real server ID.
    init(localCreate input: CreateBookmarkInput, now: Date, userID: String) {
        let trimmedTitle = input.title?.trimmingCharacters(in: .whitespacesAndNewlines)

        id = UUID()
        serverID = UUID()
        self.userID = userID
        url = input.url.absoluteString
        title = (trimmedTitle?.isEmpty == false ? trimmedTitle : nil) ?? input.url.absoluteString
        bookmarkDescription = input.description
        tags = input.tags
        isArchived = false
        faviconDomain = Bookmark.faviconDomain(for: input.url)
        serverCreatedAt = now
        serverUpdatedAt = now
        waybackURL = nil
        pendingSyncAt = now
        locallyDeletedAt = nil
        isLocalOnly = true
        wantsMetadataFetch = input.fetchMetadata
    }

    #if DEBUG
        /// Builds a record from a domain `Bookmark` for seeding the in-memory preview store.
        init(previewBookmark bookmark: Bookmark) {
            id = UUID()
            serverID = bookmark.id
            userID = "preview"
            url = bookmark.url.absoluteString
            title = bookmark.title
            bookmarkDescription = bookmark.description
            tags = bookmark.tags
            isArchived = bookmark.isArchived
            faviconDomain = Bookmark.faviconDomain(for: bookmark.url)
            serverCreatedAt = bookmark.createdAt
            serverUpdatedAt = bookmark.updatedAt
            waybackURL = bookmark.waybackURL?.absoluteString
            pendingSyncAt = nil
            locallyDeletedAt = nil
            isLocalOnly = false
        }
    #endif

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
        faviconDomain = Bookmark.faviconDomain(for: dto.url)
        serverCreatedAt = dto.createdAt
        serverUpdatedAt = dto.updatedAt
        waybackURL = dto.waybackURL?.absoluteString
        pendingSyncAt = nil
        locallyDeletedAt = nil
        isLocalOnly = false
        wantsMetadataFetch = false
        syncError = nil
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
        waybackURL = local.waybackURL.flatMap { URL(string: $0) }
        isPendingSync = local.pendingSyncAt != nil
        hasSyncError = local.syncError != nil
    }
}
