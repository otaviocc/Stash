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

import Crypto
import Fluent
import JWT
import Vapor

/// Issues access/refresh token pairs and handles refresh-token hashing & rotation. PRD §8.1.
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
