// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - TagDTO

/// A tag and its usage count for the current user.
public struct TagDTO: Codable, Sendable {

    public let name: String
    public let count: Int
}

// MARK: - TagRenameResultDTO

/// The result of renaming a tag.
public struct TagRenameResultDTO: Codable, Sendable {

    public let from: String
    public let to: String
    public let affectedBookmarks: Int
}

// MARK: - TagDeleteResultDTO

/// The result of deleting a tag.
public struct TagDeleteResultDTO: Codable, Sendable {

    public let tag: String
    public let affectedBookmarks: Int
}
