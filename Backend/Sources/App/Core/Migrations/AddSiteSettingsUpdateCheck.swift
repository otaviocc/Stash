// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that adds the instance-wide update-check switch to `site_settings`. The `true` default
/// keeps checking on for existing instances, matching the documented default (see `UpdateChecker`).
struct AddSiteSettingsUpdateCheck: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("site_settings")
            .field("update_check_enabled", .bool, .required, .sql(.default(true)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("site_settings")
            .deleteField("update_check_enabled")
            .update()
    }
}
