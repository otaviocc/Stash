// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - TagRenameRequest

/// Request body for renaming a tag.
public struct TagRenameRequest: Encodable, Sendable {

    // MARK: Properties

    public let from: String
    public let to: String

    // MARK: Lifecycle

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}
