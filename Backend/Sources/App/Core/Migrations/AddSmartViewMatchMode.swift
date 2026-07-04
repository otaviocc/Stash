// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that adds the `match_mode` column to `smart_views`. The `"all"` default backfills
/// existing rows so they keep their original AND behavior.
struct AddSmartViewMatchMode: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("smart_views")
            .field("match_mode", .string, .required, .sql(.default("all")))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("smart_views")
            .deleteField("match_mode")
            .update()
    }
}
