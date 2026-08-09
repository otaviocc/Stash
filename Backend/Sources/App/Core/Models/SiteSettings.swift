// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

// MARK: - SiteSettings

/// Instance-wide customization settings. A single-row table (never deleted): the admin's
/// chosen accent theme, an optional "About" message, and up to four editable footer links.
/// See the "Site Settings & Admin Customization" entry in `Docs/decisions-backend.md`.
final class SiteSettings: Model, @unchecked Sendable {

    // MARK: Static Properties

    static let schema = "site_settings"

    static let defaultLinks: [FooterLink] = [
        .init(label: "GitHub", url: "https://github.com/otaviocc/Stash"),
        .init(label: "Mastodon", url: "https://social.lol/@otaviocc"),
        .init(label: "Ko-fi", url: "https://ko-fi.com/otaviocc"),
        .init(label: "", url: "")
    ]

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

    @Field(key: "footer_links")
    var footerLinksRaw: String

    @Field(key: "internet_archive_enabled")
    var internetArchiveEnabled: Bool

    @Field(key: "update_check_enabled")
    var updateCheckEnabled: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    // MARK: Computed Properties

    /// Decoded footer links, falling back to defaults if the JSON is corrupt.
    var footerLinks: [FooterLink] {
        get {
            guard let data = footerLinksRaw.data(using: .utf8),
                  let links = try? JSONDecoder().decode([FooterLink].self, from: data),
                  !links.isEmpty
            else {
                return Self.defaultLinks
            }

            return links
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8)
            {
                footerLinksRaw = str
            }
        }
    }

    // MARK: Lifecycle

    init() {}

    init(
        id: UUID? = nil,
        accentTheme: String,
        aboutText: String? = nil,
        footerLinks: [FooterLink]? = nil,
        internetArchiveEnabled: Bool = true,
        updateCheckEnabled: Bool = true
    ) {
        self.id = id
        self.accentTheme = accentTheme
        self.aboutText = aboutText
        if let links = footerLinks,
           let data = try? JSONEncoder().encode(links),
           let str = String(data: data, encoding: .utf8)
        {
            footerLinksRaw = str
        } else {
            footerLinksRaw = (try? JSONEncoder().encode(Self.defaultLinks))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
        self.internetArchiveEnabled = internetArchiveEnabled
        self.updateCheckEnabled = updateCheckEnabled
    }

    // MARK: Functions

    /// If the old `footer_custom_label` / `footer_custom_url` columns hold a value and the
    /// fourth slot in `footerLinks` is still empty, merge the old data into slot four and return
    /// `true` so the caller can persist the change.
    @discardableResult
    func migrateCustomLinkIfNeeded() -> Bool {
        guard let label = footerCustomLabel, !label.isEmpty,
              let url = footerCustomURL, !url.isEmpty
        else {
            return false
        }

        var links = footerLinks
        guard links.count == 4, links[3].isEmpty else { return false }

        links[3] = FooterLink(label: label, url: url)
        footerLinks = links
        return true
    }
}
