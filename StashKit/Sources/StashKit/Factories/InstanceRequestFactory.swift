// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import MicroClient

// MARK: - InstanceRequestFactory

/// Factory for the public instance-chrome API request.
public enum InstanceRequestFactory {

    public static func makeInstanceRequest() -> NetworkRequest<VoidRequest, InstanceDTO> {
        .init(
            path: "/api/v1/instance",
            method: .get
        )
    }
}
