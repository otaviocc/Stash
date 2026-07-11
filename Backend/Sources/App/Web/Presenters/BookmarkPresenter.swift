// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

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
            waybackURL: bookmark.waybackURL,
            waybackStatus: bookmark.waybackStatus.rawValue,
            createdAt: DateFormatter.webDateTime.string(from: bookmark.createdAt ?? Date())
        )
    }

    static func listURL(_ query: BookmarkListQuery, page: Int) -> String {
        url(query, archived: query.archived == true, page: page)
    }

    static func archiveToggleURL(_ query: BookmarkListQuery, showArchived: Bool) -> String {
        url(query, archived: showArchived, page: 1)
    }

    private static func url(_ query: BookmarkListQuery, archived: Bool, page: Int) -> String {
        var components = URLComponents()
        components.path = "/app"
        var items: [URLQueryItem] = []
        if let q = query.q?.nonEmpty {
            items.append(.init(name: "q", value: q))
        }
        if let tag = query.tag?.nonEmpty {
            items.append(.init(name: "tag", value: tag))
        }
        if archived {
            items.append(.init(name: "archived", value: "true"))
        }
        if page > 1 {
            items.append(.init(name: "page", value: String(page)))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.string ?? "/app"
    }
}
