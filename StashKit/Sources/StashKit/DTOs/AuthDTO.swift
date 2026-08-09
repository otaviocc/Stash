// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - TokenPairDTO

/// A pair of access and refresh tokens returned after authentication.
public struct TokenPairDTO: Codable, Sendable {

    public let accessToken: String
    public let refreshToken: String
}

// MARK: - TOTPChallengeDTO

/// Returned when login succeeds but 2FA verification is still required.
public struct TOTPChallengeDTO: Codable, Sendable {

    public let requires2FA: Bool
    public let tempToken: String
}

// MARK: - TOTPSetupDTO

/// Returned when beginning 2FA setup.
public struct TOTPSetupDTO: Codable, Sendable {

    public let secret: String
    public let otpauthURI: String
}

// MARK: - TOTPEnrollmentDTO

/// Returned after completing 2FA setup.
public struct TOTPEnrollmentDTO: Codable, Sendable {

    public let recoveryCodes: [String]
}
