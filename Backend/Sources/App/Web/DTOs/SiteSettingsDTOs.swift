// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

// MARK: - FooterLink

/// A single label + URL pair displayed in the site footer.
struct FooterLink: Codable, Content, Equatable {

    // MARK: Properties

    let label: String
    let url: String

    // MARK: Computed Properties

    var isEmpty: Bool {
        label.isEmpty && url.isEmpty
    }
}

// MARK: - FooterContext

/// Context passed to every page template for footer rendering. The `links` array contains up to
/// four editable footer links (GitHub, Mastodon, Ko-fi, and one custom slot by default).
struct FooterContext: Content {

    let links: [FooterLink]
    let version: String
}

// MARK: - SiteChrome

/// The instance-wide chrome injected into every page render under the `chrome` key: the resolved
/// accent colors (light/dark), the optional "About this instance" message, and the footer.
struct SiteChrome: Content {

    let footer: FooterContext
    let aboutText: String?
    let accentLight: String
    let accentDark: String
    let internetArchiveEnabled: Bool
}

// MARK: - ThemeOption

/// One selectable accent theme rendered as a coloured circle in the appearance picker.
struct ThemeOption: Content {

    let id: String
    let name: String
    let light: String
    let dark: String
    let isSelected: Bool
}

// MARK: - AppearanceContext

/// View context for the admin appearance page.
struct AppearanceContext: Content {

    let title: String
    let adminUsername: String
    let themes: [ThemeOption]
    let aboutText: String
    let footerLink0Label: String
    let footerLink0URL: String
    let footerLink1Label: String
    let footerLink1URL: String
    let footerLink2Label: String
    let footerLink2URL: String
    let footerLink3Label: String
    let footerLink3URL: String
    let error: String?
    let message: String?
    let chrome: SiteChrome
}

// MARK: - AppearanceForm

/// `POST /admin/appearance` form — the chosen accent theme, the optional about message, and the
/// four editable footer link slots.
struct AppearanceForm: Content {

    let accentTheme: String
    let aboutText: String?
    let footerLink0Label: String?
    let footerLink0URL: String?
    let footerLink1Label: String?
    let footerLink1URL: String?
    let footerLink2Label: String?
    let footerLink2URL: String?
    let footerLink3Label: String?
    let footerLink3URL: String?
}
