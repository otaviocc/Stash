// MIT License
//
// Copyright (c) 2026 Otávio C.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

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
/// refresh. See the Favicon Caching section of `DECISIONS.md`.
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
