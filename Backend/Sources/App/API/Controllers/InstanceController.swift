// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

/// Public, unauthenticated instance chrome (Docs/product-api.md §9.9), currently just the accent theme, so any
/// client (native apps, CLI, the login screen itself) can tint before authenticating. Reads the
/// same app-level cache as the web `siteChrome()`, so it never hits the database.
struct InstanceController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get("instance", use: index)
    }

    func index(req: Request) async throws -> InstanceResponse {
        let snapshot = req.application.storage[SiteSettingsCacheKey.self]?.current ?? .default
        let theme = AccentTheme.theme(for: snapshot.accentTheme)

        return .init(
            accent: .init(theme: theme.id, light: theme.light, dark: theme.dark)
        )
    }
}
