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
            let headers = try await app.adminWebSession()
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.accentTheme = "forest"
            settings.aboutText = "Maintained by Alice."
            settings.footerLinks = [
                .init(label: "GitHub", url: "https://github.com/otaviocc/Stash"),
                .init(label: "Mastodon", url: "https://social.lol/@otaviocc"),
                .init(label: "Ko-fi", url: "https://ko-fi.com/otaviocc"),
                .init(label: "Our intranet", url: "https://intranet.example.com")
            ]
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
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(
                .POST, "admin/appearance",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(AppearanceForm(
                        accentTheme: "aurora",
                        aboutText: "Hello team.",
                        footerLink0Label: "GitHub",
                        footerLink0URL: "https://github.com/otaviocc/Stash",
                        footerLink1Label: "Mastodon",
                        footerLink1URL: "https://social.lol/@otaviocc",
                        footerLink2Label: "Ko-fi",
                        footerLink2URL: "https://ko-fi.com/otaviocc",
                        footerLink3Label: "Docs",
                        footerLink3URL: "https://docs.example.com"
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
            #expect(settings.footerLinks[3].label == "Docs", "It should persist the custom footer label")
            #expect(
                settings.footerLinks[3].url == "https://docs.example.com",
                "It should persist the custom footer URL"
            )

            let cached = app.storage[SiteSettingsCacheKey.self]?.current
            #expect(cached?.accentTheme == "aurora", "It should refresh the app-level cache")
        }
    }

    @Test("an unknown theme identifier is rejected with 422 and nothing is saved")
    func unknownThemeRejected() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(
                .POST, "admin/appearance",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(AppearanceForm(
                        accentTheme: "neon",
                        aboutText: nil,
                        footerLink0Label: nil, footerLink0URL: nil,
                        footerLink1Label: nil, footerLink1URL: nil,
                        footerLink2Label: nil, footerLink2URL: nil,
                        footerLink3Label: nil, footerLink3URL: nil
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
            let headers = try await app.adminWebSession()
            let tooLong = String(repeating: "a", count: 281)

            // When
            try await app.testing().test(
                .POST, "admin/appearance",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(AppearanceForm(
                        accentTheme: "ocean",
                        aboutText: tooLong,
                        footerLink0Label: nil, footerLink0URL: nil,
                        footerLink1Label: nil, footerLink1URL: nil,
                        footerLink2Label: nil, footerLink2URL: nil,
                        footerLink3Label: nil, footerLink3URL: nil
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

    @Test("a footer URL that is not https is rejected")
    func nonHTTPSURLRejected() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(
                .POST, "admin/appearance",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(AppearanceForm(
                        accentTheme: "ocean",
                        aboutText: nil,
                        footerLink0Label: "Site",
                        footerLink0URL: "http://insecure.example.com",
                        footerLink1Label: nil, footerLink1URL: nil,
                        footerLink2Label: nil, footerLink2URL: nil,
                        footerLink3Label: nil, footerLink3URL: nil
                    ), as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unprocessableEntity, "It should reject a non-https URL")
                }
            )

            let settings = try await SiteSettingsService.current(on: app.db)
            #expect(
                settings.footerLinks[0].url == "https://github.com/otaviocc/Stash",
                "It should not save the insecure URL"
            )
        }
    }

    // MARK: - Footer rendering

    @Test("the footer custom link is shown when both label and URL are set")
    func footerLinkShown() async throws {
        try await withTestApp { app in
            // Given
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.footerLinks = [
                .init(label: "GitHub", url: "https://github.com/otaviocc/Stash"),
                .init(label: "Mastodon", url: "https://social.lol/@otaviocc"),
                .init(label: "Ko-fi", url: "https://ko-fi.com/otaviocc"),
                .init(label: "Our website", url: "https://example.com")
            ]
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(.GET, "admin", headers: headers) { res async throws in
                // Then
                let body = res.body.string
                #expect(body.contains("https://example.com"), "It should render the custom footer URL")
                #expect(body.contains("Our website"), "It should render the custom footer label")
            }
        }
    }

    @Test("the footer custom link is hidden when its label is empty")
    func footerLinkHidden() async throws {
        try await withTestApp { app in
            // Given — the 4th slot has an empty label
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.footerLinks = [
                .init(label: "GitHub", url: "https://github.com/otaviocc/Stash"),
                .init(label: "Mastodon", url: "https://social.lol/@otaviocc"),
                .init(label: "Ko-fi", url: "https://ko-fi.com/otaviocc"),
                .init(label: "", url: "")
            ]
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(.GET, "admin", headers: headers) { res async throws in
                // Then
                let body = res.body.string
                #expect(body.contains("Ko-fi"), "It should still render the fixed footer links")
            }
        }
    }

    // MARK: - GET /admin/health

    @Test("the health page renders with version, DB status, uptime, disk usage, and counts")
    func healthPageRenders() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
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

    // MARK: - GET /admin/maintenance & POST /admin/db/optimize

    @Test("the maintenance page renders with the optimize button")
    func maintenancePageRenders() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(.GET, "admin/maintenance", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the maintenance page")
                #expect(
                    res.body.string.contains("Run database optimize"),
                    "It should show the optimize button"
                )
            }
        }
    }

    @Test("running database optimize runs VACUUM and redirects with a success banner")
    func optimizeDatabaseSucceeds() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            var location: String?

            // When
            try await app.testing().test(.POST, "admin/db/optimize", headers: headers) { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect after running VACUUM")
                location = res.headers.first(name: .location)
                #expect(
                    location?.hasPrefix("/admin/maintenance?ok=db_optimized&ms=") == true,
                    "It should PRG to the maintenance page with the elapsed time"
                )
            }

            let redirectTarget = try #require(location)
            try await app.testing().test(.GET, redirectTarget, headers: headers) { res async throws in
                #expect(
                    res.body.string.contains("Database optimize complete"),
                    "It should show the success banner"
                )
            }
        }
    }

    // MARK: - GET /admin/favicons

    @Test("the favicons page renders stats for an empty cache")
    func faviconsPageEmpty() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(.GET, "admin/favicons", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the favicons page")
                let body = res.body.string
                #expect(body.contains(">0<"), "It should show a zero total count")
            }
        }
    }

    @Test("the favicons page shows correct counts per status and total bytes")
    func faviconsPageCounts() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            try await FaviconCache(domain: "a.com", imageData: Data([0x1, 0x2]), status: .cached).save(on: app.db)
            try await FaviconCache(domain: "b.com", imageData: Data([0x1, 0x2, 0x3]), status: .cached).save(on: app.db)
            try await FaviconCache(domain: "c.com", status: .pending).save(on: app.db)
            try await FaviconCache(domain: "d.com", status: .failed).save(on: app.db)

            // When
            try await app.testing().test(.GET, "admin/favicons", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the favicons page")
                let body = res.body.string
                #expect(body.contains(">4<"), "It should show 4 total")
                #expect(body.contains(">2<"), "It should show 2 cached")
                #expect(body.contains(">1<"), "It should show 1 pending and 1 failed")
                #expect(body.contains("5 B"), "It should show the summed byte total (2 + 3) in human-readable form")
            }
        }
    }

    // MARK: - POST /admin/favicons/clear

    @Test("clearing the favicon cache deletes all rows and redirects with the correct flash")
    func clearFaviconsRedirects() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            try await FaviconCache(domain: "a.com", status: .cached).save(on: app.db)
            try await FaviconCache(domain: "b.com", status: .cached).save(on: app.db)

            // When
            try await app.testing().test(.POST, "admin/favicons/clear", headers: headers) { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect after clearing")
                #expect(
                    res.headers.first(name: .location) == "/admin/favicons?ok=favicons_cleared",
                    "It should PRG to the favicons page with the cleared flash"
                )
            }

            let remaining = try await FaviconCache.query(on: app.db).count()
            #expect(remaining == 0, "It should delete every row")
        }
    }

    // MARK: - POST /admin/favicons/rescan

    @Test("rescanning redirects with the rescanning flash message and deletes existing rows")
    func rescanFaviconsRedirects() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            try await FaviconCache(domain: "a.com", status: .cached).save(on: app.db)

            // When
            try await app.testing().test(.POST, "admin/favicons/rescan", headers: headers) { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect after starting the rescan")
                #expect(
                    res.headers.first(name: .location) == "/admin/favicons?ok=favicons_rescanning",
                    "It should PRG to the favicons page with the rescanning flash"
                )
            }

            let remaining = try await FaviconCache.query(on: app.db).count()
            #expect(remaining == 0, "It should delete every row's delete-half synchronously, even in tests")
        }
    }

    @Test("the favicons page requires an admin session — unauthenticated requests redirect to login")
    func faviconsPageRequiresAuth() async throws {
        try await withTestApp { app in
            // When
            try await app.testing().test(.GET, "admin/favicons") { res async throws in
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
}
