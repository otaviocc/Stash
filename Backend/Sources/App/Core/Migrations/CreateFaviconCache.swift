// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that creates the `favicon_cache` table, keyed uniquely by domain.
struct CreateFaviconCache: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("favicon_cache")
            .id()
            .field("domain", .string, .required)
            .field("image_data", .data)
            .field("content_type", .string)
            .field("source_url", .string)
            .field("status", .string, .required)
            .field("fetched_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "domain")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("favicon_cache").delete()
    }
}
