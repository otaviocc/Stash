// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - PageDTO

/// A paginated API response wrapping a list of items.
public struct PageDTO<T: Codable & Sendable>: Codable, Sendable {

    public let items: [T]
    public let metadata: PaginationMetadataDTO
}

// MARK: - PaginationMetadataDTO

/// Pagination metadata from the API.
public struct PaginationMetadataDTO: Codable, Sendable {

    public let page: Int
    public let per: Int
    public let total: Int
}
