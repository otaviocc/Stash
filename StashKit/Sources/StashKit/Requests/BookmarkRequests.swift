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

// MARK: - CreateBookmarkRequest

/// Request body for creating a bookmark.
public struct CreateBookmarkRequest: Encodable, Sendable {

    // MARK: Properties

    public let url: String
    public let title: String?
    public let description: String?
    public let tags: [String]?
    public let fetchMetadata: Bool?

    // MARK: Lifecycle

    public init(
        url: String,
        title: String? = nil,
        description: String? = nil,
        tags: [String]? = nil,
        fetchMetadata: Bool? = nil
    ) {
        self.url = url
        self.title = title
        self.description = description
        self.tags = tags
        self.fetchMetadata = fetchMetadata
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

    // MARK: Lifecycle

    public init(
        url: String? = nil,
        title: String? = nil,
        description: String? = nil,
        tags: [String]? = nil,
        isArchived: Bool? = nil
    ) {
        self.url = url
        self.title = title
        self.description = description
        self.tags = tags
        self.isArchived = isArchived
    }
}
