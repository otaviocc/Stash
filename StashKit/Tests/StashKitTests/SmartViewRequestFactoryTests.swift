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

// MARK: - SmartViewRequestFactoryTests

/// Verifies the paths, methods, and query items produced by `SmartViewRequestFactory`.
@Suite("SmartViewRequestFactory — paths and query items")
struct SmartViewRequestFactoryTests {

    // MARK: Properties

    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    // MARK: Functions

    @Test("builds a GET list request for the collection")
    func listRequest() {
        let request = SmartViewRequestFactory.makeListRequest()

        #expect(request.path == "/api/v1/smart-views", "It should target the smart-views collection")
        #expect(request.method == .get, "It should use GET")
    }

    @Test("builds a POST create request carrying the body")
    func createRequest() {
        let body = SmartViewRequest(
            name: "YouTube Reviews",
            conditions: [SmartViewConditionDTO(type: "urlContains", value: "youtube")],
            matchMode: "any"
        )

        let request = SmartViewRequestFactory.makeCreateRequest(body)

        #expect(request.path == "/api/v1/smart-views", "It should target the smart-views collection")
        #expect(request.method == .post, "It should use POST")
        #expect(request.body?.name == "YouTube Reviews", "It should carry the submitted name")
        #expect(request.body?.matchMode == "any", "It should carry the match mode")
    }

    @Test("builds GET and PUT requests for a single smart view by id")
    func getAndUpdateRequests() {
        let get = SmartViewRequestFactory.makeGetRequest(id: id)
        #expect(get.path == "/api/v1/smart-views/\(id.uuidString)", "It should target the smart view by id")
        #expect(get.method == .get, "It should use GET")

        let body = SmartViewRequest(name: "Renamed", conditions: [SmartViewConditionDTO(type: "tag", value: "swift")])
        let update = SmartViewRequestFactory.makeUpdateRequest(id: id, body: body)
        #expect(update.path == "/api/v1/smart-views/\(id.uuidString)", "It should target the smart view by id")
        #expect(update.method == .put, "It should use PUT")
    }

    @Test("builds a DELETE request for a single smart view by id")
    func deleteRequest() {
        let request = SmartViewRequestFactory.makeDeleteRequest(id: id)

        #expect(request.path == "/api/v1/smart-views/\(id.uuidString)", "It should target the smart view by id")
        #expect(request.method == .delete, "It should use DELETE")
    }

    @Test("SmartViewDTO decoding defaults matchMode to 'all' when the field is absent")
    func decodesMissingMatchMode() throws {
        let json = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "name": "Legacy",
            "conditions": [{ "type": "tag", "value": "swift" }],
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let dto = try decoder.decode(SmartViewDTO.self, from: Data(json.utf8))

        #expect(dto.matchMode == "all", "It should default matchMode to 'all' for a response that omits it")
        #expect(dto.name == "Legacy", "It should still decode the other fields")
    }

    @Test("builds a paginated bookmarks request for a smart view")
    func bookmarksRequest() {
        let request = SmartViewRequestFactory.makeBookmarksRequest(id: id, page: 2, perPage: 30)

        #expect(
            request.path == "/api/v1/smart-views/\(id.uuidString)/bookmarks",
            "It should target the smart view's bookmarks"
        )
        #expect(request.method == .get, "It should use GET")
        #expect(request.queryItems.contains(URLQueryItem(name: "page", value: "2")), "It should carry the page")
        #expect(request.queryItems.contains(URLQueryItem(name: "per", value: "30")), "It should carry the page size")
    }
}
