// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that creates the `bookmarks` table.
struct CreateBookmark: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("bookmarks")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("url", .string, .required)
            .field("title", .string, .required)
            .field("description", .string)
            .field("favicon_url", .string)
            .field("tags", .array(of: .string), .required)
            .field("tags_search", .string, .required)
            .field("is_archived", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id", "url")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("bookmarks").delete()
    }
}
