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

/// Pure presentation helpers that shape a `Bookmark` for the web frontend: the row context and the
/// list-page filter/pagination URLs. No request or database access.
enum BookmarkPresenter {

    static func row(from bookmark: Bookmark) throws -> AppBookmarkRow {
        try AppBookmarkRow(
            id: bookmark.requireID().uuidString,
            url: bookmark.url,
            title: bookmark.title,
            description: bookmark.description,
            faviconDomain: DomainExtractor.domain(from: bookmark.url),
            tags: bookmark.tags.map { TagLink(name: $0, display: TagPresenter.display($0)) },
            isArchived: bookmark.isArchived,
            createdAt: DateFormatter.webDateTime.string(from: bookmark.createdAt ?? Date())
        )
    }

    static func listURL(_ query: BookmarkListQuery, page: Int) -> String {
        var components = URLComponents()
        components.path = "/app"
        var items: [URLQueryItem] = []
        if let q = query.q?.nonEmpty { items.append(.init(name: "q", value: q)) }
        if let tag = query.tag?.nonEmpty { items.append(.init(name: "tag", value: tag)) }
        if query.archived == true { items.append(.init(name: "archived", value: "true")) }
        if page > 1 { items.append(.init(name: "page", value: String(page))) }
        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? "/app"
    }

    static func archiveToggleURL(_ query: BookmarkListQuery, showArchived: Bool) -> String {
        var components = URLComponents()
        components.path = "/app"
        var items: [URLQueryItem] = []
        if let q = query.q?.nonEmpty { items.append(.init(name: "q", value: q)) }

        if let tag = query.tag?.nonEmpty { items.append(.init(name: "tag", value: tag)) }

        if showArchived { items.append(.init(name: "archived", value: "true")) }

        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? "/app"
    }
}
