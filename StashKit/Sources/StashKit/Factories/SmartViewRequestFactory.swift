// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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
