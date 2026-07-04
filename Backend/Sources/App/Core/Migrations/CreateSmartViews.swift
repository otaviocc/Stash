// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that creates the `smart_views` table. `conditions` is a single JSON column holding
/// the array of `{ type, value }` condition objects.
struct CreateSmartViews: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("smart_views")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("name", .string, .required)
            .field("conditions", .json, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("smart_views").delete()
    }
}
