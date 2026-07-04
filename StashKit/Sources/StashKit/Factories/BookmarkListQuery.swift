// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - BookmarkListQuery

/// Query parameters for the bookmark list endpoint.
public struct BookmarkListQuery: Sendable {

    // MARK: Static Properties

    /// The sentinel `tag` value that filters for bookmarks with no tags.
    public static let untaggedTag = "__untagged__"

    /// The sentinel `tag` value that filters for bookmarks created since the start of today.
    public static let todayTag = "__today__"

    /// The sentinel `tag` value that filters for bookmarks created since the most recent Monday.
    public static let thisWeekTag = "__this_week__"

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
