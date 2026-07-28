// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import StashKit

// MARK: - BookmarkListQueryTests

/// Verifies that `BookmarkListQuery` maps to the API's URL query item names and values.
@Suite("BookmarkListQuery — URL query items")
struct BookmarkListQueryTests {

    @Test("maps every field to its API query item name")
    func mapsEveryField() {
        // Given
        let query = BookmarkListQuery(
            searchQuery: "swift",
            tag: "ios",
            archived: true,
            page: 3,
            perPage: 50
        )

        // When
        let items = query.queryItems

        // Then
        #expect(items.contains(URLQueryItem(name: "q", value: "swift")), "It should map searchQuery to q")
        #expect(items.contains(URLQueryItem(name: "tag", value: "ios")), "It should map tag to tag")
        #expect(items.contains(URLQueryItem(name: "archived", value: "true")), "It should map archived to true")
        #expect(items.contains(URLQueryItem(name: "page", value: "3")), "It should map page to page")
        #expect(items.contains(URLQueryItem(name: "per", value: "50")), "It should map perPage to per")
    }

    @Test("omits q and tag when they are nil but always sends archived, page, and per")
    func omitsNilFilters() {
        // Given
        let query = BookmarkListQuery()

        // When
        let items = query.queryItems

        // Then
        #expect(!items.contains { $0.name == "q" }, "It should omit q when searchQuery is nil")
        #expect(!items.contains { $0.name == "tag" }, "It should omit tag when tag is nil")
        #expect(items.contains(URLQueryItem(name: "archived", value: "false")), "It should default archived to false")
        #expect(items.contains(URLQueryItem(name: "page", value: "1")), "It should default page to 1")
        #expect(items.contains(URLQueryItem(name: "per", value: "20")), "It should default per to 20")
    }

    @Test("sends the __untagged__ sentinel as the tag value for the untagged filter")
    func untaggedSentinel() {
        // Given
        let query = BookmarkListQuery(tag: BookmarkListQuery.untaggedTag)

        // When
        let items = query.queryItems

        // Then
        #expect(BookmarkListQuery.untaggedTag == "__untagged__", "It should expose the documented untagged sentinel")
        #expect(
            items.contains(URLQueryItem(name: "tag", value: "__untagged__")),
            "It should pass __untagged__ through as the tag query value"
        )
    }

    @Test("sends the __read_later__ sentinel as the tag value for the read-later filter")
    func readLaterSentinel() {
        // Given
        let query = BookmarkListQuery(tag: BookmarkListQuery.readLaterTag)

        // When
        let items = query.queryItems

        // Then
        #expect(
            BookmarkListQuery.readLaterTag == "__read_later__",
            "It should expose the documented read-later sentinel"
        )
        #expect(
            items.contains(URLQueryItem(name: "tag", value: "__read_later__")),
            "It should pass __read_later__ through as the tag query value"
        )
    }
}
