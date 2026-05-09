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

// MARK: - BookmarkListQuery

/// Query parameters for the bookmark list endpoint.
public struct BookmarkListQuery: Sendable {

    // MARK: Static Properties

    /// The sentinel `tag` value that filters for bookmarks with no tags.
    public static let untaggedTag = "__untagged__"

    // MARK: Properties

    public let searchQuery: String?
    public let tag: String?
    public let archived: Bool
    public let page: Int
    public let perPage: Int

    // MARK: Computed Properties

    /// The query parameters mapped to the API's URL query item names
    /// (`q`, `tag`, `archived`, `page`, `per`).
    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []

        if let searchQuery {
            items.append(URLQueryItem(name: "q", value: searchQuery))
        }

        if let tag {
            items.append(URLQueryItem(name: "tag", value: tag))
        }

        items.append(URLQueryItem(name: "archived", value: archived ? "true" : "false"))
        items.append(URLQueryItem(name: "page", value: String(page)))
        items.append(URLQueryItem(name: "per", value: String(perPage)))

        return items
    }

    // MARK: Lifecycle

    public init(
        searchQuery: String? = nil,
        tag: String? = nil,
        archived: Bool = false,
        page: Int = 1,
        perPage: Int = 20
    ) {
        self.searchQuery = searchQuery
        self.tag = tag
        self.archived = archived
        self.page = page
        self.perPage = perPage
    }
}
