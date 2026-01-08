import Crypto
import Fluent
import JWT
import Vapor

/// Issues access/refresh token pairs and handles refresh-token hashing & rotation. PRD §8.1.
enum TokenService {
    /// Refresh token lifetime: 90 days.
    static let refreshTokenLifetime: TimeInterval = 90 * 24 * 60 * 60

    /// SHA-256 hex of a raw refresh token. Tokens are only ever persisted hashed (PRD §7.3).
    static func hash(_ rawToken: String) -> String {
        let digest = SHA256.hash(data: Data(rawToken.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Generate a 256-bit opaque refresh token (hex).
    private static func generateRawRefreshToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Mint a signed access token + a freshly-persisted refresh token for the given user.
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
}
