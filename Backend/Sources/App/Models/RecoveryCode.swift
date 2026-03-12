import Fluent
import Vapor

/// A single-use 2FA recovery code. See PRD §7.4 and §8.4.
///
/// Eight codes are generated at 2FA enrolment. Only the bcrypt hash is stored.
final class RecoveryCode: Model, @unchecked Sendable {
    static let schema = "recovery_codes"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    /// Bcrypt hash of the raw (normalised, dash-free, uppercased) code.
    @Field(key: "code_hash")
    var codeHash: String

    /// Null until redeemed; once set, the code cannot be reused.
    @OptionalField(key: "used_at")
    var usedAt: Date?

    init() {}

    init(id: UUID? = nil, userID: User.IDValue, codeHash: String, usedAt: Date? = nil) {
        self.id = id
        self.$user.id = userID
        self.codeHash = codeHash
        self.usedAt = usedAt
    }
}
