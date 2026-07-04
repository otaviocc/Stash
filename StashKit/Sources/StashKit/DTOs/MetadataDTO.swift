// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - PageMetadataDTO

/// Page metadata fetched for a URL without saving a bookmark.
public struct PageMetadataDTO: Codable, Sendable {

    public let title: String?
    public let description: String?
    public let faviconURL: URL?
}
