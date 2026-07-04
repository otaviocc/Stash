// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import SQLKit

/// Migration that creates the `deleted_bookmarks` tombstone table.
struct CreateDeletedBookmarks: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("deleted_bookmarks")
            .id()
            .field("user_id", .uuid, .required)
            .field("bookmark_id", .uuid, .required)
            .field("deleted_at", .datetime)
            .create()

        try await (database as? SQLDatabase)?.create(index: "deleted_bookmarks_user_deleted_at")
            .on("deleted_bookmarks")
            .column("user_id")
            .column("deleted_at")
            .run()
    }

    func revert(on database: Database) async throws {
        try await (database as? SQLDatabase)?.drop(index: "deleted_bookmarks_user_deleted_at").run()
        try await database.schema("deleted_bookmarks").delete()
    }
}
