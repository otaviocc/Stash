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

import Vapor

// MARK: - LoginRequest

struct LoginRequest: Content, Validatable {

    // MARK: Properties

    let username: String
    let password: String

    // MARK: Static Functions

    static func validations(_ validations: inout Validations) {
        validations.add("username", as: String.self, is: !.empty)
        validations.add("password", as: String.self, is: !.empty)
    }
}

// MARK: - TOTPRequest

struct TOTPRequest: Content {

    let tempToken: String
    let totpCode: String
}

// MARK: - RecoveryRequest

struct RecoveryRequest: Content {

    let tempToken: String
    let recoveryCode: String
}

// MARK: - RefreshRequest

struct RefreshRequest: Content {

    let refreshToken: String
}

// MARK: - LogoutRequest

struct LogoutRequest: Content {

    let refreshToken: String
}

// MARK: - VerifySetupRequest

struct VerifySetupRequest: Content {

    let totpCode: String
}

// MARK: - ChangePasswordRequest

struct ChangePasswordRequest: Content, Validatable {

    // MARK: Properties

    let currentPassword: String
    let newPassword: String

    // MARK: Static Functions

    static func validations(_ validations: inout Validations) {
        validations.add("newPassword", as: String.self, is: .count(12...))
    }
}

// MARK: - TokenPair

/// Successful authentication result (PRD §8.2).
struct TokenPair: Content {

    let accessToken: String
    let refreshToken: String
}

// MARK: - TwoFactorRequired

/// Login result when 2FA is enabled (PRD §8.2).
struct TwoFactorRequired: Content {

    // MARK: Properties

    let requires2FA: Bool
    let tempToken: String

    // MARK: Lifecycle

    init(tempToken: String) {
        requires2FA = true
        self.tempToken = tempToken
    }
}

// MARK: - TOTPSetupResponse

struct TOTPSetupResponse: Content {

    let secret: String
    let otpauthURI: String
}

// MARK: - RecoveryCodesResponse

struct RecoveryCodesResponse: Content {

    let recoveryCodes: [String]
}

// MARK: - UserResponse

/// Public user projection (PRD §13 `User`).
struct UserResponse: Content {

    let id: UUID
    let username: String
    let role: UserRole
    let isActive: Bool
    let isTOTPEnabled: Bool
    let bookmarkCount: Int
    let createdAt: Date
}

// MARK: - HealthResponse

struct HealthResponse: Content {

    let status: String
}
