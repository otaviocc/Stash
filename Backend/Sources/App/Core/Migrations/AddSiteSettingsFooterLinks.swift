// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Migration that adds the `footer_links` JSON column to `site_settings`, replacing the old
/// `footer_custom_label` / `footer_custom_url` pair with an array of up to four editable links.
/// The default value seeds the three well-known links plus one empty custom slot. Any existing
/// custom link data is migrated lazily by the model on first read.
struct AddSiteSettingsFooterLinks: AsyncMigration {

    func prepare(on database: Database) async throws {
        let defaultJSON = """
        [{"label":"GitHub","url":"https://github.com/otaviocc/Stash"},\
        {"label":"Mastodon","url":"https://social.lol/@otaviocc"},\
        {"label":"Ko-fi","url":"https://ko-fi.com/otaviocc"},\
        {"label":"","url":""}]
        """

        try await database.schema("site_settings")
            .field("footer_links", .string, .required, .sql(.default(defaultJSON)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("site_settings")
            .deleteField("footer_links")
            .update()
    }
}
