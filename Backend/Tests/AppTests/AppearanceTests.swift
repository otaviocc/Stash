// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the site settings model, the admin appearance page, footer rendering, and the
/// version file (Site Settings & Admin Customisation).
@Suite("Appearance — site settings & admin customisation")
struct AppearanceTests {

    // MARK: - Site settings row

    @Test("the default site settings row is created on first boot")
    func defaultRowSeeded() async throws {
        try await withTestApp { app in
            // Given — a freshly booted app

            // When
            let all = try await SiteSettings.query(on: app.db).all()

            // Then
            #expect(all.count == 1, "It should create exactly one settings row")
            #expect(all.first?.accentTheme == "ocean", "It should default the accent theme to ocean")
            #expect(all.first?.aboutText == nil, "It should leave the about text empty by default")
        }
    }

    @Test("the settings service recreates the row if it is somehow missing")
    func serviceRecreatesRow() async throws {
        try await withTestApp { app in
            // Given
            try await SiteSettings.query(on: app.db).delete()
            #expect(try await SiteSettings.query(on: app.db).count() == 0, "It should start with no row")

            // When
            let settings = try await SiteSettingsService.current(on: app.db)

            // Then
            #expect(settings.accentTheme == "ocean", "It should recreate the default row")
            #expect(try await SiteSettings.query(on: app.db).count() == 1, "It should leave exactly one row")
        }
    }

    // MARK: - GET /admin/appearance

    @Test("the appearance page renders with the current settings pre-filled")
    func appearancePrefilled() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminWebSession(app)
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.accentTheme = "forest"
            settings.aboutText = "Maintained by Alice."
            settings.footerCustomLabel = "Our intranet"
            settings.footerCustomURL = "https://intranet.example.com"
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)

            // When
            try await app.testing().test(.GET, "admin/appearance", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the appearance page")
                let body = res.body.string
                #expect(body.contains("value=\"forest\" checked"), "It should pre-select the saved theme")
                #expect(body.contains("Maintained by Alice."), "It should pre-fill the about text")
                #expect(body.contains("Our intranet"), "It should pre-fill the custom footer label")
                #expect(body.contains("https://intranet.example.com"), "It should pre-fill the custom footer URL")
            }
        }
    }

    // MARK: - POST /admin/appearance

    @Test("saving a valid theme updates the row and refreshes the cache")
    func saveValidTheme() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminWebSession(app)

            // When
            try await app.testing().test(
                .POST, "admin/appearance",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(AppearanceForm(
                        accentTheme: "aurora",
                        aboutText: "Hello team.",
                        footerCustomLabel: "Docs",
                        footerCustomURL: "https://docs.example.com"
                    ), as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .seeOther, "It should redirect after saving")
                    #expect(
                        res.headers.first(name: .location) == "/admin/appearance?ok=saved",
                        "It should PRG to the page"
                    )
                }
            )

            let settings = try await SiteSettingsService.current(on: app.db)
            #expect(settings.accentTheme == "aurora", "It should persist the chosen theme")
            #expect(settings.aboutText == "Hello team.", "It should persist the about text")

            let cached = app.storage[SiteSettingsCacheKey.self]?.current
            #expect(cached?.accentTheme == "aurora", "It should refresh the app-level cache")
        }
    }

    @Test("an unknown theme identifier is rejected with 422 and nothing is saved")
    func unknownThemeRejected() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminWebSession(app)

            // When
            try await app.testing().test(
                .POST, "admin/appearance",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(AppearanceForm(
                        accentTheme: "neon",
                        aboutText: nil,
                        footerCustomLabel: nil,
                        footerCustomURL: nil
                    ), as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unprocessableEntity, "It should reject an unknown theme")
                }
            )

            let settings = try await SiteSettingsService.current(on: app.db)
            #expect(settings.accentTheme == "ocean", "It should leave the theme unchanged")
        }
    }

    @Test("an about message over 280 characters is rejected")
    func aboutTooLong() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminWebSession(app)
            let tooLong = String(repeating: "a", count: 281)

            // When
            try await app.testing().test(
                .POST, "admin/appearance",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(AppearanceForm(
                        accentTheme: "ocean",
                        aboutText: tooLong,
                        footerCustomLabel: nil,
                        footerCustomURL: nil
                    ), as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unprocessableEntity, "It should reject an over-long about message")
                }
            )

            let settings = try await SiteSettingsService.current(on: app.db)
            #expect(settings.aboutText == nil, "It should not save the over-long message")
        }
    }

    @Test("a custom footer URL that is not https is rejected")
    func nonHTTPSURLRejected() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminWebSession(app)

            // When
            try await app.testing().test(
                .POST, "admin/appearance",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(AppearanceForm(
                        accentTheme: "ocean",
                        aboutText: nil,
                        footerCustomLabel: "Site",
                        footerCustomURL: "http://insecure.example.com"
                    ), as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unprocessableEntity, "It should reject a non-https URL")
                }
            )

            let settings = try await SiteSettingsService.current(on: app.db)
            #expect(settings.footerCustomURL == nil, "It should not save the insecure URL")
        }
    }

    // MARK: - Footer rendering

    @Test("the footer custom link is shown when both label and URL are set")
    func footerLinkShown() async throws {
        try await withTestApp { app in
            // Given
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.footerCustomLabel = "Our website"
            settings.footerCustomURL = "https://example.com"
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)
            let headers = try await adminWebSession(app)

            // When
            try await app.testing().test(.GET, "admin", headers: headers) { res async throws in
                // Then
                let body = res.body.string
                #expect(body.contains("https://example.com"), "It should render the custom footer URL")
                #expect(body.contains("Our website"), "It should render the custom footer label")
            }
        }
    }

    @Test("the footer custom link is hidden when either field is empty")
    func footerLinkHidden() async throws {
        try await withTestApp { app in
            // Given — only the label is set, no URL
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.footerCustomLabel = "Our website"
            settings.footerCustomURL = nil
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)
            let headers = try await adminWebSession(app)

            // When
            try await app.testing().test(.GET, "admin", headers: headers) { res async throws in
                // Then
                let body = res.body.string
                #expect(!body.contains("Our website"), "It should not render the custom link without a URL")
                #expect(body.contains("Ko-fi"), "It should still render the fixed footer links")
            }
        }
    }

    // MARK: - GET /admin/health

    @Test("the health page renders with version, DB status, uptime, disk usage, and counts")
    func healthPageRenders() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminWebSession(app)
            try await app.makeUser(username: "alice", password: "alice-password-123", role: .user)

            // When
            try await app.testing().test(.GET, "admin/health", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the health page")
                let body = res.body.string
                #expect(body.contains("dev"), "It should show the fallback version string in tests")
                #expect(body.contains("SQLite"), "It should report SQLite as the driver in the test environment")
                #expect(body.contains("class=\"pill active\""), "It should show an ok status pill for the DB probe")
                #expect(body.contains(">2<"), "It should show the total user count (root + alice)")
            }
        }
    }

    @Test("the health page requires an admin session — unauthenticated requests redirect to login")
    func healthPageRequiresAuth() async throws {
        try await withTestApp { app in
            // When
            try await app.testing().test(.GET, "admin/health") { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect rather than render the page")
                #expect(
                    res.headers.first(name: .location) == "/admin/login",
                    "It should redirect to the admin login page"
                )
            }
        }
    }

    // MARK: - Version file

    @Test("the version string is read from the VERSION file and falls back to dev")
    func versionFile() throws {
        // Given
        let directory = NSTemporaryDirectory() + "stash-version-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }

        // When — no file present
        #expect(AppVersion.read(directory: directory) == "dev", "It should fall back to dev when missing")

        // When — a file is present
        try "2.3.4\n".write(toFile: directory + "/VERSION", atomically: true, encoding: .utf8)
        #expect(AppVersion.read(directory: directory) == "2.3.4", "It should read and trim the version string")
    }

    // MARK: - Helpers

    private func adminWebSession(
        _ app: Application,
        username: String = "root",
        password: String = "admin-password-123"
    ) async throws -> HTTPHeaders {
        try await app.makeUser(username: username, password: password, role: .admin)

        var cookie: String?
        try await app.testing().test(
            .POST, "admin/login",
            beforeRequest: { req in
                try req.content.encode(
                    LoginForm(username: username, password: password, totpCode: nil),
                    as: .urlEncodedForm
                )
            },
            afterResponse: { res async throws in
                cookie = res.headers.setCookie?["stash_admin_session"]?.string
            }
        )
        guard let cookie else {
            throw Abort(.internalServerError, reason: "admin web login did not set a session cookie")
        }

        return ["Cookie": "stash_admin_session=\(cookie)"]
    }
}
