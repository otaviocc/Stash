// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import MicroClient

// MARK: - UserRequestFactory

/// Factory for current-user API requests (PRD §9.2).
public enum UserRequestFactory {

    public static func makeMeRequest() -> NetworkRequest<VoidRequest, UserDTO> {
        .init(
            path: "/api/v1/me",
            method: .get
        )
    }

    public static func makeChangePasswordRequest(
        _ body: ChangePasswordRequest
    ) -> NetworkRequest<ChangePasswordRequest, VoidResponse> {
        .init(
            path: "/api/v1/me/password",
            method: .put,
            body: body
        )
    }
}
