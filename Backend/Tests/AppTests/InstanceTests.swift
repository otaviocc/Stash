// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Testing
import VaporTesting
@testable import App

/// Verifies the public `GET /api/v1/instance` endpoint.
@Suite("Instance: public accent endpoint")
struct InstanceTests {

    @Test("returns the default accent theme with no authentication")
    func returnsDefaultAccent() async throws {
        try await withTestApp { app in
            // Given: no auth, default settings

            // When
            try await app.testing().test(.GET, "api/v1/instance") { res async throws in
                // Then
                #expect(res.status == .ok, "It should return 200 OK without authentication")
                let body = try res.content.decode(InstanceResponse.self)
                #expect(body.accent.theme == AccentTheme.default.id, "It should default to the ocean theme")
                #expect(body.accent.light == AccentTheme.default.light, "It should return the default light hex")
                #expect(body.accent.dark == AccentTheme.default.dark, "It should return the default dark hex")
            }
        }
    }

    @Test("reflects a changed accent theme from the cache, without a database hit")
    func reflectsChangedTheme() async throws {
        try await withTestApp { app in
            // Given
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.accentTheme = "sunny"
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)

            // When
            try await app.testing().test(.GET, "api/v1/instance") { res async throws in
                // Then
                #expect(res.status == .ok, "It should return 200 OK")
                let body = try res.content.decode(InstanceResponse.self)
                let sunny = AccentTheme.theme(for: "sunny")
                #expect(body.accent.theme == "sunny", "It should reflect the updated theme id")
                #expect(body.accent.light == sunny.light, "It should reflect the updated light hex")
                #expect(body.accent.dark == sunny.dark, "It should reflect the updated dark hex")
            }
        }
    }
}
