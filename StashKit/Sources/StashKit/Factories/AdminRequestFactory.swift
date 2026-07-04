// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import MicroClient

// MARK: - AdminRequestFactory

/// Factory for admin user management API requests.
public enum AdminRequestFactory {

    public static func makeUsersRequest() -> NetworkRequest<VoidRequest, [UserDTO]> {
        .init(
            path: "/api/v1/admin/users",
            method: .get
        )
    }

    public static func makeCreateUserRequest(
        _ body: CreateUserRequest
    ) -> NetworkRequest<CreateUserRequest, UserDTO> {
        .init(
            path: "/api/v1/admin/users",
            method: .post,
            body: body
        )
    }

    public static func makeUpdateUserRequest(
        id: UUID,
        body: UpdateUserRequest
    ) -> NetworkRequest<UpdateUserRequest, UserDTO> {
        .init(
            path: "/api/v1/admin/users/\(id.uuidString)",
            method: .put,
            body: body
        )
    }

    public static func makeDeleteUserRequest(
        id: UUID
    ) -> NetworkRequest<VoidRequest, VoidResponse> {
        .init(
            path: "/api/v1/admin/users/\(id.uuidString)",
            method: .delete
        )
    }

    public static func makeResetTOTPRequest(
        id: UUID
    ) -> NetworkRequest<VoidRequest, VoidResponse> {
        .init(
            path: "/api/v1/admin/users/\(id.uuidString)/reset-totp",
            method: .post
        )
    }

    public static func makeStatsRequest() -> NetworkRequest<VoidRequest, AdminStatsDTO> {
        .init(
            path: "/api/v1/admin/stats",
            method: .get
        )
    }
}
