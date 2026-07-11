// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the admin dashboard hub (`GET /admin`): the KPI stat strip, the navigation card grid
/// linking to every other admin page, and the recent-activity feed.
@Suite("Admin dashboard — hub")
struct DashboardTests {

    @Test("the dashboard shows the KPI strip with correct user/bookmark counts")
    func dashboardShowsKPIStrip() async throws {
        try await withTestApp { app in
            // Given — one active, one suspended, so a swapped split is detectable
            let headers = try await app.adminWebSession()
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeBookmark(for: alice, url: "https://one.example.com")
            try await app.makeBookmark(for: alice, url: "https://two.example.com")
            try await app.makeUser(username: "bob", password: "bob-password-123", isActive: false)

            // When
            try await app.testing().test(.GET, "admin", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the dashboard")
                let body = res.body.string
                #expect(
                    body.contains("<div class=\"num\">3</div>"),
                    "It should show 3 total users (root, alice, bob)"
                )
                #expect(
                    body.contains("Users (2 active, 1 suspended)"),
                    "It should show the active/suspended split"
                )
                #expect(
                    body.contains("<div class=\"num\">2</div>"),
                    "It should show 2 total bookmarks"
                )
            }
        }
    }

    @Test("the dashboard shows a navigation card for every other admin page")
    func dashboardShowsNavigationCards() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(.GET, "admin", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the dashboard")
                let body = res.body.string
                for href in [
                    "/admin/users", "/admin/users/new", "/admin/appearance", "/admin/audit",
                    "/admin/sessions", "/admin/health", "/admin/maintenance", "/admin/favicons",
                    "/admin/internet-archive", "/admin/logs"
                ] {
                    #expect(body.contains("href=\"\(href)\""), "It should link to \(href)")
                }
            }
        }
    }

    @Test("the dashboard shows live details for the Favicons and Internet Archive cards")
    func dashboardShowsLiveCardDetails() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            let user = try await app.makeUser()
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            bookmark.waybackStatus = .pending
            try await bookmark.save(on: app.db)

            // When
            try await app.testing().test(.GET, "admin", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the dashboard")
                let body = res.body.string
                #expect(body.contains("1 queued"), "It should show the pending Internet Archive count")
                #expect(body.contains("0 cached · 0 pending"), "It should show the favicon cache counts")
            }
        }
    }

    @Test("the Internet Archive card shows Disabled when the instance switch is off")
    func dashboardShowsArchiveDisabled() async throws {
        try await withTestApp { app in
            // Given
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.internetArchiveEnabled = false
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(.GET, "admin", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the dashboard")
                #expect(res.body.string.contains("Disabled"), "It should show the archive card as disabled")
            }
        }
    }

    @Test("the dashboard shows recent audit activity, most recent first")
    func dashboardShowsRecentActivity() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            await AuditLogger.record(
                action: "internet_archive_toggled",
                actor: "root",
                detail: "internet_archive_enabled set to false",
                ip: nil,
                on: app.db
            )

            // When
            try await app.testing().test(.GET, "admin", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the dashboard")
                #expect(
                    res.body.string.contains("internet_archive_toggled"),
                    "It should show the recent audit action"
                )
            }
        }
    }

    @Test("the admin dashboard requires an admin session")
    func dashboardRequiresAuth() async throws {
        try await withTestApp { app in
            // When
            try await app.testing().test(.GET, "admin") { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect rather than render the page")
                #expect(
                    res.headers.first(name: .location) == "/admin/login",
                    "It should redirect to the admin login page"
                )
            }
        }
    }

    @Test("the top nav is trimmed to Dashboard, Users, and App")
    func navIsTrimmed() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(.GET, "admin", headers: headers) { res async throws in
                // Then — the nav itself should no longer link to the other admin pages directly;
                // they're only reachable via the dashboard's own card grid (checked above), so this
                // guards against the trimmed nav silently growing back.
                #expect(res.status == .ok, "It should render the dashboard")
                let nav = try #require(
                    res.body.string.range(of: "<nav>").map { navStart in
                        String(res.body.string[navStart.lowerBound...].prefix(400))
                    }
                )
                #expect(nav.contains("/admin\">Dashboard"), "It should still link to Dashboard")
                #expect(nav.contains("/admin/users\">Users"), "It should still link to Users")
                #expect(nav.contains("/app\">App"), "It should still link to App")
                #expect(!nav.contains("New user"), "It should no longer list New user in the nav")
                #expect(!nav.contains("Internet Archive"), "It should no longer list Internet Archive in the nav")
            }
        }
    }
}
