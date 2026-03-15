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

// MARK: - SmartViewRequestFactory

/// Factory for Smart View API requests.
public enum SmartViewRequestFactory {

    public static func makeListRequest() -> NetworkRequest<VoidRequest, [SmartViewDTO]> {
        .init(
            path: "/api/v1/smart-views",
            method: .get
        )
    }

    public static func makeCreateRequest(
        _ body: SmartViewRequest
    ) -> NetworkRequest<SmartViewRequest, SmartViewDTO> {
        .init(
            path: "/api/v1/smart-views",
            method: .post,
            body: body
        )
    }

    public static func makeGetRequest(
        id: UUID
    ) -> NetworkRequest<VoidRequest, SmartViewDTO> {
        .init(
            path: "/api/v1/smart-views/\(id.uuidString)",
            method: .get
        )
    }

    public static func makeUpdateRequest(
        id: UUID,
        body: SmartViewRequest
    ) -> NetworkRequest<SmartViewRequest, SmartViewDTO> {
        .init(
            path: "/api/v1/smart-views/\(id.uuidString)",
            method: .put,
            body: body
        )
    }

    public static func makeDeleteRequest(
        id: UUID
    ) -> NetworkRequest<VoidRequest, VoidResponse> {
        .init(
            path: "/api/v1/smart-views/\(id.uuidString)",
            method: .delete
        )
    }

    public static func makeBookmarksRequest(
        id: UUID,
        page: Int,
        perPage: Int
    ) -> NetworkRequest<VoidRequest, BookmarkPageDTO> {
        .init(
            path: "/api/v1/smart-views/\(id.uuidString)/bookmarks",
            method: .get,
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per", value: String(perPage))
            ]
        )
    }
}
