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

// MARK: - TOTPEnrolmentDTO

/// Returned after completing 2FA setup.
public struct TOTPEnrolmentDTO: Codable, Sendable {

    public let recoveryCodes: [String]
}
