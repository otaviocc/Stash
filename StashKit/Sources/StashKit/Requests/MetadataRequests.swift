// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - MetadataRequest

/// Request body for fetching metadata for a URL.
public struct MetadataRequest: Encodable, Sendable {

    // MARK: Properties

    public let url: String

    // MARK: Lifecycle

    public init(url: String) {
        self.url = url
    }
}
