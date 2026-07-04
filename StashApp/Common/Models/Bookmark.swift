// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import CoreTransferable
import Foundation
import StashKit
import UniformTypeIdentifiers

// MARK: - Bookmark

/// A bookmark belonging to the current user.
struct Bookmark: Identifiable, Hashable, Codable {

    // MARK: Properties

    let id: UUID
    let url: URL
    let title: String
    let description: String?
    let faviconURL: URL?
    let tags: [String]
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date

    /// True when this bookmark has a local change still waiting to be pushed to the server. Surfaced
    /// from the local store's sync metadata (`pendingSyncAt`); always `false` for a server-sourced
    /// bookmark. Drives the pending indicator in the list and detail views.
    var isPendingSync = false

    /// True when this bookmark's push failed permanently (`syncError != nil`). Always `false` for a
    /// server-sourced bookmark. Drives the failed-sync variant of the indicator.
    var hasSyncError = false

    // MARK: Computed Properties

    /// The URL's host, suitable for a compact subtitle in a list row.
    var hostname: String {
        url.host() ?? url.absoluteString
    }

    /// Cache key for Stash's favicon endpoint. Must match the backend's DomainExtractor:
    /// lowercased host, leading `www.` stripped, explicit port kept.
    var faviconDomain: String? {
        Self.faviconDomain(for: url)
    }

    // MARK: Static Functions

    /// The favicon cache key for a URL — the canonical derivation reused wherever a bookmark's
    /// domain key is needed (e.g. the local store). Must match the backend's DomainExtractor:
    /// lowercased host, leading `www.` stripped, explicit port kept.
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
}

// MARK: - UTType + stashBookmark

extension UTType {

    /// The drag-and-drop payload type for a `Bookmark`, used when dragging a bookmark row onto a tag
    /// in the iPad/macOS sidebar. A dedicated type keeps the drop destination from accepting arbitrary
    /// JSON; intra-app drags need no Info.plist declaration.
    static let stashBookmark = UTType(exportedAs: "\(AppGroup.bundleBase).bookmark")
}

// MARK: - Bookmark + Transferable

extension Bookmark: Transferable {

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .stashBookmark)
    }
}

// MARK: - Bookmark + DTO

extension Bookmark {

    init(
        dto: BookmarkDTO
    ) {
        id = dto.id
        url = dto.url
        title = dto.title.isEmpty ? dto.url.absoluteString : dto.title
        description = dto.description
        faviconURL = dto.faviconURL
        tags = dto.tags
        isArchived = dto.isArchived
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
    }
}
