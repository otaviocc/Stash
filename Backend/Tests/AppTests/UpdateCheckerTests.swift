// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies `UpdateChecker`'s pure semver comparison, its app-level cache, and the admin
/// dashboard/health surfacing (Instance management — update checker).
@Suite("Update checker")
struct UpdateCheckerTests {

    // MARK: - compareSemver

    @Test("a newer release reports an update available")
    func newerVersionAvailable() {
        #expect(UpdateChecker.compareSemver(current: "1.0.0", latest: "1.1.0"), "It should detect a minor bump")
        #expect(UpdateChecker.compareSemver(current: "1.0.0", latest: "2.0.0"), "It should detect a major bump")
        #expect(UpdateChecker.compareSemver(current: "1.0.0", latest: "1.0.1"), "It should detect a patch bump")
    }

    @Test("the same version reports no update available")
    func sameVersionNoUpdate() {
        #expect(
            !UpdateChecker.compareSemver(current: "1.2.0", latest: "1.2.0"),
            "It should report no update when versions match"
        )
    }

    @Test("an older or equal latest version reports no update available")
    func olderLatestNoUpdate() {
        #expect(
            !UpdateChecker.compareSemver(current: "2.0.0", latest: "1.9.9"),
            "It should never report an update when latest is behind current"
        )
    }

    @Test("a v-prefixed tag is tolerated")
    func vPrefixTolerated() {
        #expect(
            UpdateChecker.compareSemver(current: "v1.0.0", latest: "v1.1.0"),
            "It should strip a leading v from both versions"
        )
    }

    @Test("a dev build never reports an update available")
    func devBuildNeverUpdates() {
        #expect(
            !UpdateChecker.compareSemver(current: "dev", latest: "99.0.0"),
            "It should never nag a from-source dev build"
        )
    }

    @Test("an unparseable latest version never reports an update available")
    func unparseableLatestNoUpdate() {
        #expect(
            !UpdateChecker.compareSemver(current: "1.0.0", latest: "not-a-version"),
            "It should treat a malformed tag as no update, not a false positive"
        )
    }

    @Test("a qualified patch component is unparseable rather than silently truncated")
    func qualifiedPatchUnparseable() {
        #expect(
            !UpdateChecker.compareSemver(current: "1.2.3", latest: "1.2.3rc"),
            "It should not truncate '3rc' down to patch 3 and treat it as equal to a real 1.2.3"
        )
        #expect(
            !UpdateChecker.compareSemver(current: "1.2.3rc", latest: "1.2.4"),
            "It should also treat a qualified current version as unparseable, not just latest"
        )
    }

    // MARK: - Cache seeding & dashboard/health rendering

    @Test("the dashboard shows an update banner when the cache reports one available")
    func dashboardShowsUpdateBanner() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            app.storage[UpdateStatusCacheKey.self]?.update(UpdateStatus(
                currentVersion: "dev",
                latestVersion: "9.9.9",
                updateAvailable: true,
                releaseURL: "https://github.com/otaviocc/Stash/releases/tag/v9.9.9",
                lastCheckedAt: Date(),
                checkFailed: false
            ))

            // When
            try await app.testing().test(.GET, "admin", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the dashboard")
                let body = res.body.string
                #expect(body.contains("An update is available"), "It should show the update banner")
                #expect(body.contains("9.9.9"), "It should mention the latest version")
            }
        }
    }

    @Test("the dashboard shows no update banner when the cache reports none available")
    func dashboardHidesUpdateBannerWhenUpToDate() async throws {
        try await withTestApp { app in
            // Given — the freshly-booted cache defaults to "unknown" (no update available)
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(.GET, "admin", headers: headers) { res async throws in
                // Then
                #expect(!res.body.string.contains("An update is available"), "It should not show a banner")
            }
        }
    }

    @Test("the health page shows the update status card")
    func healthPageShowsUpdateCard() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            app.storage[UpdateStatusCacheKey.self]?.update(UpdateStatus(
                currentVersion: "dev",
                latestVersion: "5.0.0",
                updateAvailable: true,
                releaseURL: "https://github.com/otaviocc/Stash/releases/tag/v5.0.0",
                lastCheckedAt: Date(),
                checkFailed: false
            ))

            // When
            try await app.testing().test(.GET, "admin/health", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the health page")
                let body = res.body.string
                #expect(body.contains("Updates"), "It should show the Updates card")
                #expect(body.contains("5.0.0"), "It should show the latest version")
                #expect(body.contains("docker compose pull"), "It should show the upgrade instructions")
            }
        }
    }

    // MARK: - POST /admin/health/check-updates

    @Test("check-updates redirects with the skipped flash when suppressed under testing")
    func checkUpdatesRedirectsWhenSkipped() async throws {
        try await withTestApp { app in
            // Given — forceCheck is always suppressed under .testing, so this never actually runs
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(.POST, "admin/health/check-updates", headers: headers) { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect after the check")
                #expect(
                    res.headers.first(name: .location) == "/admin/health?ok=update_check_skipped",
                    "It should PRG to the health page with the skipped flash, not claim success"
                )
            }
        }
    }

    @Test("the skipped flash renders a distinct banner from a real check")
    func skippedFlashRendersDistinctBanner() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(
                .GET, "admin/health?ok=update_check_skipped", headers: headers
            ) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the health page")
                #expect(
                    res.body.string.contains("Update check skipped"),
                    "It should show the skipped banner, not the success banner"
                )
            }
        }
    }

    @Test("the Check now button is hidden once update checking is disabled")
    func checkNowButtonHiddenWhenDisabled() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.updateCheckEnabled = false
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)

            // When
            try await app.testing().test(.GET, "admin/health", headers: headers) { res async throws in
                // Then
                #expect(
                    !res.body.string.contains("Check now"),
                    "It should hide the Check now button once checking is disabled, so it can't be clicked to no effect"
                )
            }
        }
    }

    // MARK: - POST /admin/health/toggle-updates

    @Test("toggling update checking off persists the setting and refreshes the cache")
    func toggleUpdatesOff() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(
                .POST, "admin/health/toggle-updates",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(["_unused": "1"], as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .seeOther, "It should redirect after saving")
                    #expect(
                        res.headers.first(name: .location) == "/admin/health?ok=updates_disabled",
                        "It should PRG with the disabled flash"
                    )
                }
            )

            let settings = try await SiteSettingsService.current(on: app.db)
            #expect(!settings.updateCheckEnabled, "It should persist the disabled setting")
            #expect(
                app.storage[SiteSettingsCacheKey.self]?.current.updateCheckEnabled == false,
                "It should refresh the app-level cache"
            )
        }
    }

    @Test("refreshIfStale is a no-op when update checking is disabled")
    func refreshIfStaleNoOpWhenDisabled() async throws {
        try await withTestApp { app in
            // Given
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.updateCheckEnabled = false
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)
            let before = app.storage[UpdateStatusCacheKey.self]?.current.lastCheckedAt

            // When
            UpdateChecker.refreshIfStale(on: app)

            // Then — a real check would set lastCheckedAt; disabled, nothing changes
            #expect(
                app.storage[UpdateStatusCacheKey.self]?.current.lastCheckedAt == before,
                "It should not attempt a check when disabled"
            )
        }
    }

    // MARK: - GET /admin/health auth guard

    @Test("the health page's update controls require an admin session")
    func healthUpdateActionsRequireAuth() async throws {
        try await withTestApp { app in
            // When
            try await app.testing().test(.POST, "admin/health/check-updates") { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect rather than perform the check")
                #expect(
                    res.headers.first(name: .location) == "/admin/login",
                    "It should redirect to the admin login page"
                )
            }
        }
    }
}
