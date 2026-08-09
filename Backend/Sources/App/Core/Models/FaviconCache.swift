// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

// MARK: - FaviconStatus

/// The lifecycle state of a cached favicon. `pending` while a fetch is in flight, `cached` once an
/// image is stored, `failed` when every fetch attempt was exhausted without a usable image.
enum FaviconStatus: String, Codable {

    case pending
    case cached
    case failed
}

// MARK: - FaviconCache

/// A favicon cached once per domain and shared across every user and bookmark on that domain.
/// Fetched at the point a domain is first encountered and only re-fetched on an explicit manual
/// refresh. See the "Favicon Caching" entry in `Docs/decisions-backend.md`.
final class FaviconCache: Model, @unchecked Sendable {

    // MARK: Static Properties

    static let schema = "favicon_cache"
    static let maxImageBytes = 100 * 1024

    // MARK: Properties

    @ID(key: .id)
    var id: UUID?

    @Field(key: "domain")
    var domain: String

    @OptionalField(key: "image_data")
    var imageData: Data?

    @OptionalField(key: "content_type")
    var contentType: String?

    @OptionalField(key: "source_url")
    var sourceURL: String?

    @Field(key: "status")
    var status: FaviconStatus

    @OptionalField(key: "fetched_at")
    var fetchedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    // MARK: Lifecycle

    init() {}

    init(
        id: UUID? = nil,
        domain: String,
        imageData: Data? = nil,
        contentType: String? = nil,
        sourceURL: String? = nil,
        status: FaviconStatus = .pending,
        fetchedAt: Date? = nil
    ) {
        self.id = id
        self.domain = domain
        self.imageData = imageData
        self.contentType = contentType
        self.sourceURL = sourceURL
        self.status = status
        self.fetchedAt = fetchedAt
    }
}
