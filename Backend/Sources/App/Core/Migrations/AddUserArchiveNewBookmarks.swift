// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that adds the per-user "send new bookmarks to the Internet Archive" preference to
/// `users`. The `true` default matches the documented default, opting existing accounts in.
struct AddUserArchiveNewBookmarks: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("archive_new_bookmarks", .bool, .required, .sql(.default(true)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .deleteField("archive_new_bookmarks")
            .update()
    }
}
