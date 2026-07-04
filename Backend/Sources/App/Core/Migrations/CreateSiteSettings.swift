// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that creates the single-row `site_settings` table and seeds the default row
/// (accent theme `ocean`, all other fields `nil`).
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

        try await SiteSettings(accentTheme: AccentTheme.default.id).save(on: database)
    }

    func revert(on database: Database) async throws {
        try await database.schema("site_settings").delete()
    }
}
