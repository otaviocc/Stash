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

// MARK: - BookmarkRequestFactory

/// Factory for bookmark-related API requests.
public enum BookmarkRequestFactory {

    public static func makeListRequest(
        query: BookmarkListQuery
    ) -> NetworkRequest<VoidRequest, BookmarkPageDTO> {
        .init(
            path: "/api/v1/bookmarks",
            method: .get,
            queryItems: query.queryItems
        )
    }

    public static func makeGetRequest(
        id: UUID
    ) -> NetworkRequest<VoidRequest, BookmarkDTO> {
        .init(
            path: "/api/v1/bookmarks/\(id.uuidString)",
            method: .get
        )
    }

    public static func makeCreateRequest(
        _ body: CreateBookmarkRequest
    ) -> NetworkRequest<CreateBookmarkRequest, BookmarkDTO> {
        .init(
            path: "/api/v1/bookmarks",
            method: .post,
            body: body
        )
    }

    public static func makeUpdateRequest(
        id: UUID,
        body: UpdateBookmarkRequest
    ) -> NetworkRequest<UpdateBookmarkRequest, BookmarkDTO> {
        .init(
            path: "/api/v1/bookmarks/\(id.uuidString)",
            method: .put,
            body: body
        )
    }

    public static func makeDeleteRequest(
        id: UUID
    ) -> NetworkRequest<VoidRequest, VoidResponse> {
        .init(
            path: "/api/v1/bookmarks/\(id.uuidString)",
            method: .delete
        )
    }
}
