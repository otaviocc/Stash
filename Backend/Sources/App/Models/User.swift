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

import Fluent
import Vapor

// MARK: - User

/// A Stash account. See PRD §7.1.
final class User: Model, Content, @unchecked Sendable {

    // MARK: Static Properties

    static let schema = "users"

    // MARK: Properties

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

    @Children(for: \.$user)
    var bookmarks: [Bookmark]

    // MARK: Lifecycle

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

// MARK: Authenticatable

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
