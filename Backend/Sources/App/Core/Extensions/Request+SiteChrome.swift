// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

extension Request {

    /// Builds the per-page chrome (footer + accent theme + about text) from the app-level settings
    /// cache. Never hits the database and never throws: a missing cache falls back to defaults so a
    /// page render is never blocked by a missing footer config.
    func siteChrome() -> SiteChrome {
        let snapshot = application.storage[SiteSettingsCacheKey.self]?.current ?? .default
        let version = application.storage[AppVersionKey.self] ?? "dev"
        let theme = AccentTheme.theme(for: snapshot.accentTheme)

        return SiteChrome(
            footer: FooterContext(
                customLabel: snapshot.footerCustomLabel.flatMap(\.nonEmpty),
                customURL: snapshot.footerCustomURL.flatMap(\.nonEmpty),
                version: version
            ),
            aboutText: snapshot.aboutText.flatMap(\.nonEmpty),
            accentLight: theme.light,
            accentDark: theme.dark
        )
    }
}
