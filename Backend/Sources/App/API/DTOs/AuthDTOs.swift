// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

// MARK: - LoginRequest

/// `POST /auth/login` body.
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

/// `POST /auth/totp` body: completes a 2FA login with a TOTP code.
struct TOTPRequest: Content {

    let tempToken: String
    let totpCode: String
}

// MARK: - RecoveryRequest

/// `POST /auth/recovery` body: completes a 2FA login with a recovery code.
struct RecoveryRequest: Content {

    let tempToken: String
    let recoveryCode: String
}

// MARK: - RefreshRequest

/// `POST /auth/refresh` body.
struct RefreshRequest: Content {

    let refreshToken: String
}

// MARK: - LogoutRequest

/// `POST /auth/logout` body.
struct LogoutRequest: Content {

    let refreshToken: String
}

// MARK: - VerifySetupRequest

/// Body for verifying the first TOTP code during 2FA setup.
struct VerifySetupRequest: Content {

    let totpCode: String
}

// MARK: - DisableTOTPRequest

/// `POST /auth/totp/disable` body: self-service 2FA disable requires the current TOTP code.
struct DisableTOTPRequest: Content {

    let totpCode: String
}

// MARK: - ChangePasswordRequest

/// `POST /auth/change-password` body.
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

/// Successful authentication result (Docs/product-auth.md §8.2).
struct TokenPair: Content {

    let accessToken: String
    let refreshToken: String
}

// MARK: - TwoFactorRequired

/// Login result when 2FA is enabled (Docs/product-auth.md §8.2).
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

/// Response when starting 2FA setup: the secret and its `otpauth://` URI.
struct TOTPSetupResponse: Content {

    let secret: String
    let otpauthURI: String
}

// MARK: - RecoveryCodesResponse

/// Response containing the freshly generated 2FA recovery codes.
struct RecoveryCodesResponse: Content {

    let recoveryCodes: [String]
}

// MARK: - UserResponse

/// Public user projection (Docs/product-api.md §9.2 `User`).
struct UserResponse: Content {

    let id: UUID
    let username: String
    let role: UserRole
    let isActive: Bool
    let isTOTPEnabled: Bool
    let bookmarkCount: Int
    let archiveNewBookmarks: Bool
    let createdAt: Date
}

// MARK: - HealthResponse

/// `GET /health` response.
struct HealthResponse: Content {

    let status: String
}
