// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - CreateUserRequest

/// Request body for creating a user (admin only).
public struct CreateUserRequest: Encodable, Sendable {

    // MARK: Properties

    public let username: String
    public let password: String

    // MARK: Lifecycle

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

// MARK: - ChangePasswordRequest

/// Request body for changing the current user's own password (`PUT /api/v1/me/password`).
public struct ChangePasswordRequest: Encodable, Sendable {

    // MARK: Properties

    public let currentPassword: String
    public let newPassword: String

    // MARK: Lifecycle

    public init(currentPassword: String, newPassword: String) {
        self.currentPassword = currentPassword
        self.newPassword = newPassword
    }
}

// MARK: - UpdateUserRequest

/// Request body for updating a user (admin only).
public struct UpdateUserRequest: Encodable, Sendable {

    // MARK: Properties

    public let isActive: Bool?
    public let password: String?

    // MARK: Lifecycle

    public init(isActive: Bool? = nil, password: String? = nil) {
        self.isActive = isActive
        self.password = password
    }
}
