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

import JWT
import Vapor

// MARK: - AccessTokenPayload

/// Short-lived access token (15 minutes). PRD §8.1.
struct AccessTokenPayload: JWTPayload {

    // MARK: Nested Types

    enum CodingKeys: String, CodingKey {

        case subject = "sub"
        case expiration = "exp"
        case scope
        case role
    }

    // MARK: Static Properties

    static let scopeValue = "access"

    // MARK: Properties

    var subject: SubjectClaim
    var expiration: ExpirationClaim
    var scope: String
    var role: String

    // MARK: Computed Properties

    var userID: UUID? {
        UUID(uuidString: subject.value)
    }

    // MARK: Lifecycle

    init(user: User, lifetime: TimeInterval = 15 * 60) throws {
        subject = try SubjectClaim(value: user.requireID().uuidString)
        expiration = ExpirationClaim(value: Date().addingTimeInterval(lifetime))
        scope = AccessTokenPayload.scopeValue
        role = user.role.rawValue
    }

    // MARK: Functions

    func verify(using signer: JWTSigner) throws {
        try expiration.verifyNotExpired()
        guard scope == AccessTokenPayload.scopeValue else {
            throw JWTError.claimVerificationFailure(name: "scope", reason: "not an access token")
        }
    }
}

// MARK: - TempTokenPayload

/// Limited-scope temporary token issued between password login and the 2FA step (5 minutes). PRD §8.2.
struct TempTokenPayload: JWTPayload {

    // MARK: Nested Types

    enum CodingKeys: String, CodingKey {

        case subject = "sub"
        case expiration = "exp"
        case scope
    }

    // MARK: Static Properties

    static let scopeValue = "2fa"

    // MARK: Properties

    var subject: SubjectClaim
    var expiration: ExpirationClaim
    var scope: String

    // MARK: Computed Properties

    var userID: UUID? {
        UUID(uuidString: subject.value)
    }

    // MARK: Lifecycle

    init(user: User, lifetime: TimeInterval = 5 * 60) throws {
        subject = try SubjectClaim(value: user.requireID().uuidString)
        expiration = ExpirationClaim(value: Date().addingTimeInterval(lifetime))
        scope = TempTokenPayload.scopeValue
    }

    // MARK: Functions

    func verify(using signer: JWTSigner) throws {
        try expiration.verifyNotExpired()
        guard scope == TempTokenPayload.scopeValue else {
            throw JWTError.claimVerificationFailure(name: "scope", reason: "not a 2FA temp token")
        }
    }
}
