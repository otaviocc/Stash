// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that adds the "read later" flag to `bookmarks`. The `false` default backfills
/// existing rows. Independent of `is_archived`; neither flag clears the other.
struct AddBookmarkReadLater: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("bookmarks")
            .field("is_read_later", .bool, .required, .sql(.default(false)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("bookmarks")
            .deleteField("is_read_later")
            .update()
    }
}
