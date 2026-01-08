import Fluent
import Vapor

/// A Stash account. See PRD §7.1.
final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    /// Unique, always stored lowercased.
    @Field(key: "username")
    var username: String

    /// Bcrypt hash, cost factor 12.
    @Field(key: "password_hash")
    var passwordHash: String

    /// Base32-encoded TOTP secret. Stored once setup begins, but `isTOTPEnabled`
    /// stays false until the user verifies the first code.
    @OptionalField(key: "totp_secret")
    var totpSecret: String?

    @Field(key: "is_totp_enabled")
    var isTOTPEnabled: Bool

    @Field(key: "role")
    var role: UserRole

    /// False = suspended; the account cannot log in.
    @Field(key: "is_active")
    var isActive: Bool

    /// Denormalised bookmark count; maintained from M2 onward.
    @Field(key: "bookmark_count")
    var bookmarkCount: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Children(for: \.$user)
    var refreshTokens: [RefreshToken]

    @Children(for: \.$user)
    var recoveryCodes: [RecoveryCode]

    init() {}

    init(
        id: UUID? = nil,
        username: String,
        passwordHash: String,
        role: UserRole = .user,
        isActive: Bool = true,
        isTOTPEnabled: Bool = false,
        totpSecret: String? = nil,
        bookmarkCount: Int = 0
    ) {
        self.id = id
        self.username = username.lowercased()
        self.passwordHash = passwordHash
        self.role = role
        self.isActive = isActive
        self.isTOTPEnabled = isTOTPEnabled
        self.totpSecret = totpSecret
        self.bookmarkCount = bookmarkCount
    }
}

extension User: Authenticatable {}

extension User {
    /// The public-facing projection of a user (PRD §13 `User`).
    func asResponse() throws -> UserResponse {
        try UserResponse(
            id: requireID(),
            username: username,
            role: role,
            isActive: isActive,
            isTOTPEnabled: isTOTPEnabled,
            bookmarkCount: bookmarkCount,
            createdAt: createdAt ?? Date()
        )
    }
}
