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
import MicroClient
import Testing
@testable import StashKit

// MARK: - BookmarkRequestFactoryTests

/// Verifies the paths, methods, and query items produced by `BookmarkRequestFactory`.
@Suite("BookmarkRequestFactory — paths and query items")
struct BookmarkRequestFactoryTests {

    // MARK: Properties

    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    // MARK: Functions

    @Test("builds a GET list request carrying the query's URL items")
    func listRequest() {
        // Given
        let query = BookmarkListQuery(searchQuery: "swift", tag: "ios", archived: true, page: 2, perPage: 30)

        // When
        let request = BookmarkRequestFactory.makeListRequest(query: query)

        // Then
        #expect(request.path == "/api/v1/bookmarks", "It should target the bookmarks collection")
        #expect(request.method == .get, "It should use GET")
        #expect(
            request.queryItems.contains(URLQueryItem(name: "q", value: "swift")),
            "It should carry the search query"
        )
        #expect(request.queryItems.contains(URLQueryItem(name: "tag", value: "ios")), "It should carry the tag filter")
        #expect(
            request.queryItems.contains(URLQueryItem(name: "archived", value: "true")),
            "It should carry the archived flag"
        )
        #expect(request.queryItems.contains(URLQueryItem(name: "page", value: "2")), "It should carry the page")
        #expect(request.queryItems.contains(URLQueryItem(name: "per", value: "30")), "It should carry the page size")
    }

    @Test("builds a GET request for a single bookmark by id")
    func getRequest() {
        // When
        let request = BookmarkRequestFactory.makeGetRequest(id: id)

        // Then
        #expect(request.path == "/api/v1/bookmarks/\(id.uuidString)", "It should target the bookmark by id")
        #expect(request.method == .get, "It should use GET")
    }

    @Test("builds a DELETE request for a single bookmark by id")
    func deleteRequest() {
        // When
        let request = BookmarkRequestFactory.makeDeleteRequest(id: id)

        // Then
        #expect(request.path == "/api/v1/bookmarks/\(id.uuidString)", "It should target the bookmark by id")
        #expect(request.method == .delete, "It should use DELETE")
    }

    @Test("builds a GET changes request with the keyset cursor and an ISO-8601 since")
    func changesRequest() {
        // Given
        let since = Date(timeIntervalSince1970: 1_700_000_000)

        // When
        let request = BookmarkRequestFactory.makeChangesRequest(
            since: since,
            afterUpdatedAt: "2023-11-14T22:13:21.500Z",
            afterId: id,
            perPage: 200
        )

        // Then
        #expect(request.path == "/api/v1/bookmarks/changes", "It should target the changes endpoint")
        #expect(request.method == .get, "It should use GET")
        #expect(
            !request.queryItems.contains { $0.name == "page" },
            "It should not carry an offset page parameter"
        )
        #expect(request.queryItems.contains(URLQueryItem(name: "per", value: "200")), "It should carry the page size")
        #expect(
            request.queryItems.contains(URLQueryItem(name: "since", value: "2023-11-14T22:13:20Z")),
            "It should carry the since timestamp as an ISO-8601 string"
        )
        #expect(
            request.queryItems.contains(URLQueryItem(name: "afterUpdatedAt", value: "2023-11-14T22:13:21.500Z")),
            "It should carry the keyset timestamp token verbatim"
        )
        #expect(
            request.queryItems.contains(URLQueryItem(name: "afterId", value: id.uuidString)),
            "It should carry the keyset id"
        )
    }

    @Test("omits since and keyset items on the first full-sync page")
    func changesRequestWithoutSince() {
        // When
        let request = BookmarkRequestFactory.makeChangesRequest(
            since: nil,
            afterUpdatedAt: nil,
            afterId: nil,
            perPage: 100
        )

        // Then
        #expect(
            !request.queryItems.contains { $0.name == "since" },
            "It should omit the since item for an initial full sync"
        )
        #expect(
            !request.queryItems.contains { $0.name == "afterUpdatedAt" || $0.name == "afterId" },
            "It should omit the keyset cursor on the first page"
        )
    }

    @Test("builds a GET deleted request carrying an ISO-8601 since")
    func deletedRequest() {
        // Given
        let since = Date(timeIntervalSince1970: 1_700_000_000)

        // When
        let request = BookmarkRequestFactory.makeDeletedRequest(since: since)

        // Then
        #expect(request.path == "/api/v1/bookmarks/deleted", "It should target the deleted endpoint")
        #expect(request.method == .get, "It should use GET")
        #expect(
            request.queryItems.contains(URLQueryItem(name: "since", value: "2023-11-14T22:13:20Z")),
            "It should carry the since timestamp as an ISO-8601 string"
        )
    }

    @Test("builds a GET deleted request with no query items when no since is given")
    func deletedRequestWithoutSince() {
        // When
        let request = BookmarkRequestFactory.makeDeletedRequest(since: nil)

        // Then
        #expect(request.queryItems.isEmpty, "It should send no query items for an initial full sync")
    }
}
