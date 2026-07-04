// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that creates the `recovery_codes` table.
struct CreateRecoveryCode: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("recovery_codes")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("code_hash", .string, .required)
            .field("used_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("recovery_codes").delete()
    }
}
