// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that creates the single-row `site_settings` table. The default row itself is seeded
/// lazily by `SiteSettingsService.current(on:)` (called from `configure.swift` right after every
/// migration has run), not here: saving a live `SiteSettings` model at this migration's historical
/// schema would insert into columns that later `Add*` migrations haven't created yet.
struct CreateSiteSettings: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("site_settings")
            .id()
            .field("accent_theme", .string, .required)
            .field("about_text", .string)
            .field("footer_custom_label", .string)
            .field("footer_custom_url", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("site_settings").delete()
    }
}
