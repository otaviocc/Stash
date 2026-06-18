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

    /// A throwaway bcrypt hash to verify against when the username is unknown, so login timing doesn't
    /// reveal whether an account exists (PRD §8.5). Shared by the JSON API and both web logins.
    static let dummyPasswordHash =
        "$2b$12$C6UzMDM.H6dfI/f/IKcEeO2x0jXJ8nKqK8h0V2vQ1nC3l6mFqKQ4u"

    // MARK: Properties

    @ID(key: .id)
    var id: UUID?

    @Field(key: "username")
    var username: String

    @Field(key: "password_hash")
    var passwordHash: String

    @OptionalField(key: "totp_secret")
    var totpSecret: String?

    @Field(key: "is_totp_enabled")
    var isTOTPEnabled: Bool

    @Field(key: "role")
    var role: UserRole

    @Field(key: "is_active")
    var isActive: Bool

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

    /// Tears down two-factor auth: deletes the recovery codes, clears the TOTP secret, disables
    /// TOTP, persists, and revokes every refresh token so other sessions are signed out (PRD §8.4).
    /// The single owner of this multi-model invariant, shared by self-service disable and admin reset.
    func disableTOTP(on db: any Database) async throws {
        try await $recoveryCodes.query(on: db).delete()
        totpSecret = nil
        isTOTPEnabled = false
        try await save(on: db)
        try await $refreshTokens.query(on: db).delete()
    }
}
