// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that adds Wayback Machine submission state to `bookmarks`. The `"none"` default
/// backfills existing rows as not-yet-submitted. Each column is added in its own `ALTER TABLE`
/// (a separate `.update()` call), since SQLite — unlike Postgres — only supports one `ADD COLUMN`
/// per statement; batching them into a single chained `.update()` fails there with a syntax error.
struct AddBookmarkWayback: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("bookmarks")
            .field("wayback_status", .string, .required, .sql(.default("none")))
            .update()
        try await database.schema("bookmarks")
            .field("wayback_url", .string)
            .update()
        try await database.schema("bookmarks")
            .field("wayback_archived_at", .datetime)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("bookmarks")
            .deleteField("wayback_status")
            .update()
        try await database.schema("bookmarks")
            .deleteField("wayback_url")
            .update()
        try await database.schema("bookmarks")
            .deleteField("wayback_archived_at")
            .update()
    }
}
