// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import MicroClient

// MARK: - TagRequestFactory

/// Factory for tag-related API requests.
public enum TagRequestFactory {

    public static func makeListRequest() -> NetworkRequest<VoidRequest, [TagDTO]> {
        .init(
            path: "/api/v1/tags",
            method: .get
        )
    }

    public static func makeRenameRequest(
        _ body: TagRenameRequest
    ) -> NetworkRequest<TagRenameRequest, TagRenameResultDTO> {
        .init(
            path: "/api/v1/tags/rename",
            method: .post,
            body: body
        )
    }

    public static func makeDeleteRequest(
        tag: String
    ) -> NetworkRequest<VoidRequest, TagDeleteResultDTO> {
        .init(
            path: "/api/v1/tags/\(tag)",
            method: .delete
        )
    }
}
