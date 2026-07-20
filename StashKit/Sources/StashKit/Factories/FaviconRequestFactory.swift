// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import MicroClient

// MARK: - FaviconRequestFactory

/// Factory for favicon-related API requests.
public enum FaviconRequestFactory {

    public static func makeRefreshRequest(
        domain: String
    ) -> NetworkRequest<VoidRequest, VoidResponse> {
        .init(
            path: "/api/v1/favicons/\(domain)/refresh",
            method: .post
        )
    }
}
