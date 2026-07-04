// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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

    /// Requests bookmarks (archived included) updated after `since`, for offline sync, using keyset
    /// pagination. The first page passes `afterUpdatedAt`/`afterId` as `nil`; each subsequent page
    /// echoes the previous response's `nextAfterUpdatedAt`/`nextAfterId`. Omitting `since` returns
    /// every bookmark — the initial full sync. `afterUpdatedAt` is the opaque token from the response,
    /// passed back verbatim.
    public static func makeChangesRequest(
        since: Date?,
        afterUpdatedAt: String?,
        afterId: UUID?,
        perPage: Int
    ) -> NetworkRequest<VoidRequest, ChangesPageDTO> {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "per", value: String(perPage))
        ]

        if let since {
            queryItems.append(URLQueryItem(name: "since", value: iso8601String(from: since)))
        }

        if let afterUpdatedAt, let afterId {
            queryItems.append(URLQueryItem(name: "afterUpdatedAt", value: afterUpdatedAt))
            queryItems.append(URLQueryItem(name: "afterId", value: afterId.uuidString))
        }

        return .init(
            path: "/api/v1/bookmarks/changes",
            method: .get,
            queryItems: queryItems
        )
    }

    /// Requests tombstones for bookmarks hard-deleted after `since`, for offline sync.
    /// Omitting `since` returns every tombstone — the initial full sync.
    public static func makeDeletedRequest(
        since: Date?
    ) -> NetworkRequest<VoidRequest, [DeletedBookmarkDTO]> {
        var queryItems: [URLQueryItem] = []

        if let since {
            queryItems.append(URLQueryItem(name: "since", value: iso8601String(from: since)))
        }

        return .init(
            path: "/api/v1/bookmarks/deleted",
            method: .get,
            queryItems: queryItems
        )
    }

    // MARK: Private

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
