// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

// MARK: - FooterContext

/// Context passed to every page template for footer rendering. The GitHub, Mastodon, and Ko-fi
/// links are hardcoded directly in `_footer.leaf`, not passed here, so they cannot
/// be accidentally omitted.
struct FooterContext: Content {

    let customLabel: String?
    let customURL: String?
    let version: String
}

// MARK: - SiteChrome

/// The instance-wide chrome injected into every page render under the `chrome` key: the resolved
/// accent colours (light/dark), the optional "About this instance" message, and the footer.
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
    let footerCustomLabel: String
    let footerCustomURL: String
    let error: String?
    let message: String?
    let chrome: SiteChrome
}

// MARK: - AppearanceForm

/// `POST /admin/appearance` form — the chosen accent theme, the optional about message, and the
/// optional custom footer link.
struct AppearanceForm: Content {

    let accentTheme: String
    let aboutText: String?
    let footerCustomLabel: String?
    let footerCustomURL: String?
}
