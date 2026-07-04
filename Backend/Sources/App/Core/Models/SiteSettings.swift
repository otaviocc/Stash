// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

// MARK: - SiteSettings

/// Instance-wide customization settings. A single-row table (never deleted): the admin's
/// chosen accent theme, an optional "About" message, and an optional custom footer link.
/// See the Site Settings & Admin Customisation section of `DECISIONS.md`.
final class SiteSettings: Model, @unchecked Sendable {

    // MARK: Static Properties

    static let schema = "site_settings"

    // MARK: Properties

    @ID(key: .id)
    var id: UUID?

    @Field(key: "accent_theme")
    var accentTheme: String

    @OptionalField(key: "about_text")
    var aboutText: String?

    @OptionalField(key: "footer_custom_label")
    var footerCustomLabel: String?

    @OptionalField(key: "footer_custom_url")
    var footerCustomURL: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    // MARK: Lifecycle

    init() {}

    init(
        id: UUID? = nil,
        accentTheme: String,
        aboutText: String? = nil,
        footerCustomLabel: String? = nil,
        footerCustomURL: String? = nil
    ) {
        self.id = id
        self.accentTheme = accentTheme
        self.aboutText = aboutText
        self.footerCustomLabel = footerCustomLabel
        self.footerCustomURL = footerCustomURL
    }
}
