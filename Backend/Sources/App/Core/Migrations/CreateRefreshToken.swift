// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that creates the `refresh_tokens` table.
struct CreateRefreshToken: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("refresh_tokens")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("refresh_tokens").delete()
    }
}
