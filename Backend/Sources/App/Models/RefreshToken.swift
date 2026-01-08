import Fluent
import Vapor

/// An opaque, rotating refresh token. See PRD §7.3 and §8.1.
///
/// Only the SHA-256 hash of the raw token is persisted. The raw token is shown
/// to the client exactly once, at issuance.
final class RefreshToken: Model, @unchecked Sendable {
    static let schema = "refresh_tokens"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    /// SHA-256 hash (hex) of the raw token.
    @Field(key: "token_hash")
    var tokenHash: String

    /// 90 days from issuance.
    @Field(key: "expires_at")
    var expiresAt: Date

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, userID: User.IDValue, tokenHash: String, expiresAt: Date) {
        self.id = id
        self.$user.id = userID
        self.tokenHash = tokenHash
        self.expiresAt = expiresAt
    }
}
