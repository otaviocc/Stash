// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Crypto
import Fluent
import JWT
import Vapor

/// Issues access/refresh token pairs and hashes refresh tokens for storage. Rotation itself
/// (deleting the old token and issuing a new pair) is the auth controller's job, not this
/// enum's. Docs/product-auth.md §8.1.
enum TokenService {

    // MARK: Static Properties

    static let refreshTokenLifetime: TimeInterval = 90 * 24 * 60 * 60

    // MARK: Static Functions

    static func hash(_ rawToken: String) -> String {
        let digest = SHA256.hash(data: Data(rawToken.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func issuePair(for user: User, on req: Request) async throws -> TokenPair {
        let accessToken = try req.jwt.sign(AccessTokenPayload(user: user))

        let rawRefresh = generateRawRefreshToken()
        let record = try RefreshToken(
            userID: user.requireID(),
            tokenHash: hash(rawRefresh),
            expiresAt: Date().addingTimeInterval(refreshTokenLifetime)
        )
        try await record.save(on: req.db)

        return TokenPair(accessToken: accessToken, refreshToken: rawRefresh)
    }

    private static func generateRawRefreshToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices {
            bytes[i] = UInt8.random(in: .min ... .max)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
