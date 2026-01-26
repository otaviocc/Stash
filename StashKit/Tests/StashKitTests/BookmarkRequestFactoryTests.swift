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
}
