// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import MicroClient

// MARK: - MetadataRequestFactory

/// Factory for metadata-related API requests.
public enum MetadataRequestFactory {

    public static func makeFetchRequest(
        url: URL
    ) -> NetworkRequest<MetadataRequest, PageMetadataDTO> {
        .init(
            path: "/api/v1/metadata",
            method: .post,
            body: MetadataRequest(url: url.absoluteString)
        )
    }
}
