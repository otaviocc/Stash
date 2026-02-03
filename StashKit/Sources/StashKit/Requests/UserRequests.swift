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
