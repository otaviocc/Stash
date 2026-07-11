// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that adds the Wayback Machine rate-limit retry counter to `bookmarks`. The `0` default
/// backfills existing rows. See `WaybackSubmitter.submit(...)` for how it's used.
struct AddBookmarkWaybackRetryCount: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("bookmarks")
            .field("wayback_retry_count", .int, .required, .sql(.default(0)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("bookmarks")
            .deleteField("wayback_retry_count")
            .update()
    }
}
