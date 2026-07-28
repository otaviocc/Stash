// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - CreateBookmarkRequest

/// Request body for creating a bookmark.
public struct CreateBookmarkRequest: Encodable, Sendable {

    // MARK: Properties

    public let url: String
    public let title: String?
    public let description: String?
    public let tags: [String]?
    public let fetchMetadata: Bool?
    public let isArchived: Bool?
    public let isReadLater: Bool?

    // MARK: Lifecycle

    public init(
        url: String,
        title: String? = nil,
        description: String? = nil,
        tags: [String]? = nil,
        fetchMetadata: Bool? = nil,
        isArchived: Bool? = nil,
        isReadLater: Bool? = nil
    ) {
        self.url = url
        self.title = title
        self.description = description
        self.tags = tags
        self.fetchMetadata = fetchMetadata
        self.isArchived = isArchived
        self.isReadLater = isReadLater
    }
}

// MARK: - UpdateBookmarkRequest

/// Request body for updating a bookmark.
public struct UpdateBookmarkRequest: Encodable, Sendable {

    // MARK: Properties

    public let url: String?
    public let title: String?
    public let description: String?
    public let tags: [String]?
    public let isArchived: Bool?
    public let isReadLater: Bool?

    // MARK: Lifecycle

    public init(
        url: String? = nil,
        title: String? = nil,
        description: String? = nil,
        tags: [String]? = nil,
        isArchived: Bool? = nil,
        isReadLater: Bool? = nil
    ) {
        self.url = url
        self.title = title
        self.description = description
        self.tags = tags
        self.isArchived = isArchived
        self.isReadLater = isReadLater
    }
}
