// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

/// The Share Extension's bookmark store: create, fetch metadata, delete.
///
/// A deliberately smaller counterpart to the app's `BookmarkRepository` — it carries no list or
/// pagination state because the extension only ever saves one bookmark (and may undo it). It
/// conforms to `BookmarkCreating` so the shared `AddBookmarkView` can drive it.
@MainActor
final class ExtensionBookmarkRepository: BookmarkCreating {

    // MARK: Properties

    private let session: ExtensionSession

    // MARK: Lifecycle

    init(session: ExtensionSession) {
        self.session = session
    }

    // MARK: Functions

    func create(_ input: CreateBookmarkInput) async throws -> Bookmark {
        let client = try await session.authenticatedClient()
        let request = BookmarkRequestFactory.makeCreateRequest(
            CreateBookmarkRequest(
                url: input.url.absoluteString,
                title: input.title,
                description: input.description,
                tags: input.tags.isEmpty ? nil : input.tags,
                fetchMetadata: input.fetchMetadata,
                isReadLater: input.isReadLater
            )
        )
        let dto = try await client.run(request).value

        return Bookmark(dto: dto)
    }

    func fetchMetadata(for url: URL) async -> PageMetadata {
        await ClientMetadataFetcher.fetch(for: url)
    }

    func deleteBookmark(id: UUID) async throws {
        let client = try await session.authenticatedClient()
        _ = try await client.run(BookmarkRequestFactory.makeDeleteRequest(id: id))
    }
}
