// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Vapor

/// A single-use 2FA recovery code. See PRD §7.4 and §8.4.
///
/// Eight codes are generated at 2FA enrollment. Only the bcrypt hash is stored.
final class RecoveryCode: Model, @unchecked Sendable {

    // MARK: Static Properties

    static let schema = "recovery_codes"

    // MARK: Properties

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "code_hash")
    var codeHash: String

    @OptionalField(key: "used_at")
    var usedAt: Date?

    // MARK: Lifecycle

    init() {}

    init(id: UUID? = nil, userID: User.IDValue, codeHash: String, usedAt: Date? = nil) {
        self.id = id
        $user.id = userID
        self.codeHash = codeHash
        self.usedAt = usedAt
    }
}
