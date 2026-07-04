// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - CreateBookmarkInput

/// The input for creating a new bookmark.
struct CreateBookmarkInput {

    let url: URL
    let title: String?
    let description: String?
    let tags: [String]
    let fetchMetadata: Bool
}

// MARK: - BookmarkQuery

/// The filter applied to the bookmark list.
struct BookmarkQuery: Equatable {

    var searchQuery: String?
    var tag: String?
    var archived = false
}
