// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - LoginRequest

/// Request body for logging in.
public struct LoginRequest: Encodable, Sendable {

    // MARK: Properties

    public let username: String
    public let password: String

    // MARK: Lifecycle

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

// MARK: - TOTPRequest

/// Request body for submitting a TOTP code.
public struct TOTPRequest: Encodable, Sendable {

    // MARK: Properties

    public let tempToken: String
    public let totpCode: String

    // MARK: Lifecycle

    public init(tempToken: String, totpCode: String) {
        self.tempToken = tempToken
        self.totpCode = totpCode
    }
}

// MARK: - RecoveryCodeRequest

/// Request body for submitting a recovery code.
public struct RecoveryCodeRequest: Encodable, Sendable {

    // MARK: Properties

    public let tempToken: String
    public let recoveryCode: String

    // MARK: Lifecycle

    public init(tempToken: String, recoveryCode: String) {
        self.tempToken = tempToken
        self.recoveryCode = recoveryCode
    }
}

// MARK: - RefreshRequest

/// Request body for refreshing tokens.
public struct RefreshRequest: Encodable, Sendable {

    // MARK: Properties

    public let refreshToken: String

    // MARK: Lifecycle

    public init(refreshToken: String) {
        self.refreshToken = refreshToken
    }
}

// MARK: - TOTPVerifyRequest

/// Request body for verifying the first TOTP code during 2FA setup.
public struct TOTPVerifyRequest: Encodable, Sendable {

    // MARK: Properties

    public let totpCode: String

    // MARK: Lifecycle

    public init(totpCode: String) {
        self.totpCode = totpCode
    }
}

// MARK: - TOTPDisableRequest

/// Request body for disabling 2FA, which requires the current TOTP code.
public struct TOTPDisableRequest: Encodable, Sendable {

    // MARK: Properties

    public let totpCode: String

    // MARK: Lifecycle

    public init(totpCode: String) {
        self.totpCode = totpCode
    }
}
