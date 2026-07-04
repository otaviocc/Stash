// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - BookmarkCreating

/// A store that can create a bookmark and fetch page metadata.
///
/// The shared `AddBookmarkView` depends on this narrow protocol rather than a concrete repository,
/// so the same form serves the main app's `BookmarkRepository` and the Share Extension's
/// `ExtensionBookmarkRepository` without either knowing about the other.
@MainActor
protocol BookmarkCreating: AnyObject {

    func create(
        _ input: CreateBookmarkInput
    ) async throws -> Bookmark

    func fetchMetadata(
        for url: URL
    ) async -> PageMetadata
}

// MARK: - TagAutocompleting

/// A store that loads the user's tags and offers local prefix autocomplete.
///
/// Like `BookmarkCreating`, this lets the shared `AddBookmarkView` drive its tag suggestions from
/// either the app's `TagRepository` or the extension's `ExtensionTagRepository`.
@MainActor
protocol TagAutocompleting: AnyObject {

    // MARK: Computed Properties

    var tags: [Tag] { get }

    /// The hierarchical tag tree derived from `tags`, used by the tag picker. The app caches it on
    /// `TagRepository`; the extension derives it on the fly.
    var tagHierarchy: [TagNode] { get }

    // MARK: Functions

    func load() async throws

    func autocompleteTags(
        prefix: String
    ) -> [Tag]
}
