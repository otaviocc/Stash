// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that adds the instance-wide Internet Archive switch to `site_settings`. The `true`
/// default keeps the feature on for existing instances, matching the documented default.
struct AddSiteSettingsInternetArchive: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("site_settings")
            .field("internet_archive_enabled", .bool, .required, .sql(.default(true)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("site_settings")
            .deleteField("internet_archive_enabled")
            .update()
    }
}
