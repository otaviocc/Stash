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
