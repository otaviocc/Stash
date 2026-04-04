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

import Foundation
import StashKit

// MARK: - Bookmark

/// A bookmark belonging to the current user.
struct Bookmark: Identifiable, Hashable {

    // MARK: Properties

    let id: UUID
    let url: URL
    let title: String
    let description: String?
    let faviconURL: URL?
    let tags: [String]
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date

    // MARK: Computed Properties

    /// The URL's host, suitable for a compact subtitle in a list row.
    var hostname: String {
        url.host() ?? url.absoluteString
    }

    /// Cache key for Stash's favicon endpoint. Must match the backend's DomainExtractor:
    /// lowercased host, leading `www.` stripped, explicit port kept.
    var faviconDomain: String? {
        guard var host = url.host()?.lowercased(), !host.isEmpty else { return nil }

        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
            guard !host.isEmpty else { return nil }
        }

        if let port = url.port {
            return "\(host):\(port)"
        }

        return host
    }
}

// MARK: - Bookmark + DTO

extension Bookmark {

    init(
        dto: BookmarkDTO
    ) {
        id = dto.id
        url = dto.url
        title = dto.title.isEmpty ? dto.url.absoluteString : dto.title
        description = dto.description
        faviconURL = dto.faviconURL
        tags = dto.tags
        isArchived = dto.isArchived
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
    }
}
