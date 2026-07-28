// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the Internet Archive (Wayback Machine) submission feature: the bookmark/site/user
/// model defaults, the create-flow auto-submit gating, the manual submit endpoints (API and web),
/// the user settings toggle, and the admin dashboard page.
@Suite("Wayback — Internet Archive submission")
struct WaybackTests {

    // MARK: - Model defaults

    @Test("a new bookmark defaults to no Wayback submission")
    func bookmarkDefaults() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()

            // When
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")

            // Then
            #expect(bookmark.waybackStatus == .none, "It should default to not submitted")
            #expect(bookmark.waybackURL == nil, "It should have no snapshot URL by default")
            #expect(bookmark.waybackArchivedAt == nil, "It should have no archived date by default")
        }
    }

    @Test("Internet Archive submissions are enabled instance-wide by default")
    func instanceEnabledByDefault() async throws {
        try await withTestApp { app in
            // Given / When
            let settings = try await SiteSettingsService.current(on: app.db)

            // Then
            #expect(settings.internetArchiveEnabled, "It should default to enabled")
            #expect(WaybackSubmitter.isInstanceEnabled(on: app), "It should read as enabled from the cache too")
        }
    }

    @Test("a new user defaults to auto-submitting new bookmarks")
    func userDefaultsToAutoSubmit() async throws {
        try await withTestApp { app in
            // Given / When
            let user = try await app.makeUser()

            // Then
            #expect(user.archiveNewBookmarks, "It should default to sending new bookmarks to the archive")
        }
    }

    // MARK: - Create flow (API)

    @Test("creating a bookmark via the API auto-submits when both the instance and user allow it")
    func apiCreateAutoSubmits() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            var bookmarkID: UUID?
            try await app.testing().test(
                .POST, "api/v1/bookmarks",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(CreateBookmarkInput(
                        url: "https://example.com", title: nil, description: nil,
                        tags: nil, fetchMetadata: false, isArchived: nil, isReadLater: nil
                    ))
                },
                afterResponse: { res async throws in
                    let decoded = try res.content.decode(BookmarkResponse.self)
                    bookmarkID = decoded.id
                    #expect(
                        decoded.waybackStatus == "pending",
                        "It should report the bookmark as queued in the create response"
                    )
                }
            )

            let id = try #require(bookmarkID)
            let bookmark = try #require(try await Bookmark.find(id, on: app.db))
            #expect(bookmark.waybackStatus == .pending, "It should queue the bookmark for submission")
        }
    }

    @Test("creating a bookmark does not auto-submit when the instance switch is off")
    func apiCreateSkipsWhenInstanceDisabled() async throws {
        try await withTestApp { app in
            // Given
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.internetArchiveEnabled = false
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            var bookmarkID: UUID?
            try await app.testing().test(
                .POST, "api/v1/bookmarks",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(CreateBookmarkInput(
                        url: "https://example.com", title: nil, description: nil,
                        tags: nil, fetchMetadata: false, isArchived: nil, isReadLater: nil
                    ))
                },
                afterResponse: { res async throws in
                    bookmarkID = try res.content.decode(BookmarkResponse.self).id
                }
            )

            let id = try #require(bookmarkID)
            let bookmark = try #require(try await Bookmark.find(id, on: app.db))
            #expect(bookmark.waybackStatus == .none, "It should not queue the bookmark when disabled instance-wide")
        }
    }

    @Test("creating a bookmark does not auto-submit when the user's preference is off")
    func apiCreateSkipsWhenUserOptedOut() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            user.archiveNewBookmarks = false
            try await user.save(on: app.db)
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            var bookmarkID: UUID?
            try await app.testing().test(
                .POST, "api/v1/bookmarks",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(CreateBookmarkInput(
                        url: "https://example.com", title: nil, description: nil,
                        tags: nil, fetchMetadata: false, isArchived: nil, isReadLater: nil
                    ))
                },
                afterResponse: { res async throws in
                    bookmarkID = try res.content.decode(BookmarkResponse.self).id
                }
            )

            let id = try #require(bookmarkID)
            let bookmark = try #require(try await Bookmark.find(id, on: app.db))
            #expect(bookmark.waybackStatus == .none, "It should not queue the bookmark when the user opted out")
        }
    }

    // MARK: - submit() outcomes

    @Test("a 200 response is archived and captures the snapshot URL from Content-Location")
    func submitSucceeds() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(
                contains: "web.archive.org/save/",
                status: .ok,
                contentType: nil,
                bytes: nil,
                headers: ["Content-Location": "/web/20260101000000/https://example.com"]
            )

            // When
            let outcome = await WaybackSubmitter.submit(bookmark: bookmark, on: app.db, client: client)

            // Then
            #expect(outcome == .archived, "It should report the submission as archived")
            #expect(bookmark.waybackStatus == .archived, "It should mark the bookmark archived")
            #expect(
                bookmark.waybackURL == "https://web.archive.org/web/20260101000000/https://example.com",
                "It should capture the absolute snapshot URL from Content-Location"
            )
            #expect(bookmark.waybackArchivedAt != nil, "It should record when the snapshot was captured")
            #expect(bookmark.waybackRetryCount == 0, "It should leave the retry count at 0 on success")
        }
    }

    @Test("a 429 response is treated as retryable, not a terminal failure")
    func submitRateLimited() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            bookmark.waybackStatus = .pending
            try await bookmark.save(on: app.db)
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(contains: "web.archive.org/save/", status: .tooManyRequests, contentType: nil, bytes: nil)

            // When
            let outcome = await WaybackSubmitter.submit(bookmark: bookmark, on: app.db, client: client)

            // Then
            #expect(outcome == .rateLimited, "It should report the submission as rate-limited")
            #expect(bookmark.waybackStatus == .pending, "It should leave the bookmark pending for the next retry")
            #expect(bookmark.waybackRetryCount == 1, "It should increment the retry count")
        }
    }

    @Test("a bookmark gives up after maxRateLimitRetries consecutive 429s, freeing the queue")
    func submitGivesUpAfterMaxRateLimitRetries() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            bookmark.waybackStatus = .pending
            try await bookmark.save(on: app.db)
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(contains: "web.archive.org/save/", status: .tooManyRequests, contentType: nil, bytes: nil)

            // When / Then — every attempt before the cap stays pending and keeps counting
            for expectedCount in 1..<WaybackSubmitter.maxRateLimitRetries {
                let outcome = await WaybackSubmitter.submit(bookmark: bookmark, on: app.db, client: client)
                #expect(outcome == .rateLimited, "Attempt \(expectedCount) should still be rate-limited, not terminal")
                #expect(bookmark.waybackStatus == .pending, "It should stay pending before the cap is reached")
                #expect(bookmark.waybackRetryCount == expectedCount, "It should count attempt \(expectedCount)")
            }

            // When — the attempt that reaches the cap gives up
            let finalOutcome = await WaybackSubmitter.submit(bookmark: bookmark, on: app.db, client: client)

            // Then
            #expect(finalOutcome == .failed, "It should report the submission as failed once the cap is reached")
            #expect(bookmark.waybackStatus == .failed, "It should give up and mark the bookmark failed")
            #expect(bookmark.waybackRetryCount == 0, "It should reset the retry count so a manual retry starts fresh")
        }
    }

    @Test("an unexpected response status is a terminal failure")
    func submitUnexpectedStatusFails() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(contains: "web.archive.org/save/", status: .internalServerError, contentType: nil, bytes: nil)

            // When
            let outcome = await WaybackSubmitter.submit(bookmark: bookmark, on: app.db, client: client)

            // Then
            #expect(outcome == .failed, "It should report the submission as failed")
            #expect(bookmark.waybackStatus == .failed, "It should mark the bookmark failed")
            #expect(bookmark.waybackRetryCount == 0, "It should leave the retry count at 0")
        }
    }

    // MARK: - Queue status text

    @Test("the disabled state overrides everything else, regardless of the queue's own state")
    func queueStatusTextDisabledOverridesState() {
        let statuses: [WaybackWorker.QueueState] = [
            .idle,
            .submitting(url: "https://example.com"),
            .waitingNormalPace,
            .waitingAfterRateLimit(url: "https://example.com", attempt: 1, maxAttempts: 3)
        ]
        for state in statuses {
            let text = AdminWebController.queueStatusText(enabled: false, pendingCount: 5, state: state)
            #expect(
                text == "Disabled — no submissions will run.",
                "It should report disabled regardless of the queue's own state (\(state))"
            )
        }
    }

    @Test("idle with nothing queued reads as idle")
    func queueStatusTextIdleEmpty() {
        let text = AdminWebController.queueStatusText(enabled: true, pendingCount: 0, state: .idle)
        #expect(text == "Idle — nothing queued.", "It should report idle when there is nothing pending")
    }

    @Test("idle with bookmarks still pending reads as paused, not idle")
    func queueStatusTextIdleWithPending() {
        let text = AdminWebController.queueStatusText(enabled: true, pendingCount: 3, state: .idle)
        #expect(
            text == "Paused — 3 bookmarks queued, waiting to start.",
            "It should report paused, pluralized, when the drain loop isn't running but work is queued"
        )
    }

    @Test("idle with exactly one bookmark pending uses the singular")
    func queueStatusTextIdleWithOnePending() {
        let text = AdminWebController.queueStatusText(enabled: true, pendingCount: 1, state: .idle)
        #expect(
            text == "Paused — 1 bookmark queued, waiting to start.",
            "It should use the singular for a count of 1"
        )
    }

    @Test("submitting reports the URL currently being sent")
    func queueStatusTextSubmitting() {
        let text = AdminWebController.queueStatusText(
            enabled: true,
            pendingCount: 1,
            state: .submitting(url: "https://example.com")
        )
        #expect(text == "Submitting now: https://example.com", "It should name the URL in flight")
    }

    @Test("waiting at the normal pace reports the fixed delay")
    func queueStatusTextWaitingNormalPace() {
        let text = AdminWebController.queueStatusText(enabled: true, pendingCount: 2, state: .waitingNormalPace)
        #expect(
            text == "Running — next submission in about 30 seconds.",
            "It should report the normal between-submission pace"
        )
    }

    @Test("waiting after a rate limit reports the URL, backoff, and attempt count")
    func queueStatusTextWaitingAfterRateLimit() {
        let text = AdminWebController.queueStatusText(
            enabled: true,
            pendingCount: 1,
            state: .waitingAfterRateLimit(url: "https://amazon.com", attempt: 1, maxAttempts: 3)
        )
        #expect(
            text == "Rate-limited — retrying https://amazon.com in about 5 minutes (attempt 2 of 3).",
            "It should report the upcoming attempt number (attempt + 1), not the one just made"
        )
    }

    // MARK: - Drain stops when disabled

    @Test("the drain loop stops immediately when the instance switch is off, leaving pending bookmarks untouched")
    func drainStopsWhenDisabled() async throws {
        try await withTestApp { app in
            // Given — bookmarks queued, but the instance switch off before the worker ever runs
            let user = try await app.makeUser()
            let first = try await app.makeBookmark(for: user, url: "https://one.example.com")
            first.waybackStatus = .pending
            try await first.save(on: app.db)
            let second = try await app.makeBookmark(for: user, url: "https://two.example.com")
            second.waybackStatus = .pending
            try await second.save(on: app.db)

            let settings = try await SiteSettingsService.current(on: app.db)
            settings.internetArchiveEnabled = false
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)

            let client = MockClient(eventLoop: app.eventLoopGroup.any())
            client.stub(
                contains: "web.archive.org/save/",
                status: .ok,
                contentType: nil,
                bytes: nil,
                headers: ["Content-Location": "/web/20260101000000/https://example.com"]
            )
            let worker = WaybackWorker(app: app, client: client)

            // When
            await worker.kick()
            try await Task.sleep(for: .milliseconds(50))

            // Then
            let reloadedFirst = try #require(try await Bookmark.find(first.requireID(), on: app.db))
            #expect(reloadedFirst.waybackStatus == .pending, "It should leave the first bookmark untouched")
            let reloadedSecond = try #require(try await Bookmark.find(second.requireID(), on: app.db))
            #expect(reloadedSecond.waybackStatus == .pending, "It should leave the second bookmark untouched")
            #expect(client.requestedURLs.isEmpty, "It should never have submitted anything")
            let state = await worker.currentState()
            #expect(state == .idle, "It should have returned to idle rather than stay mid-submission")
        }
    }

    // MARK: - Manual submit (API)

    @Test("POST /bookmarks/:id/wayback queues the bookmark regardless of the user's auto-submit preference")
    func apiManualSubmitQueues() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            user.archiveNewBookmarks = false
            try await user.save(on: app.db)
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/bookmarks/\(bookmark.requireID())/wayback",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(res.status == .accepted, "It should return 202 Accepted")
            }

            let reloaded = try #require(try await Bookmark.find(bookmark.requireID(), on: app.db))
            #expect(
                reloaded.waybackStatus == .pending,
                "It should queue the bookmark regardless of the user's preference"
            )
        }
    }

    @Test("POST /bookmarks/:id/wayback is refused with 409 when disabled instance-wide")
    func apiManualSubmitRefusedWhenDisabled() async throws {
        try await withTestApp { app in
            // Given
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.internetArchiveEnabled = false
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)
            let user = try await app.makeUser()
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/bookmarks/\(bookmark.requireID())/wayback",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(res.status == .conflict, "It should refuse with 409 when the instance switch is off")
                let error = try res.content.decode(TestError.self)
                #expect(error.code == "internet_archive_disabled", "It should report the specific error code")
            }

            let reloaded = try #require(try await Bookmark.find(bookmark.requireID(), on: app.db))
            #expect(reloaded.waybackStatus == .none, "It should leave the bookmark unqueued")

            // When — a nonexistent bookmark, still with the switch off
            try await app.testing().test(
                .POST, "api/v1/bookmarks/\(UUID())/wayback",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then — existence/ownership is checked before the instance gate
                #expect(res.status == .notFound, "It should 404 for an unknown bookmark even while disabled")
            }
        }
    }

    @Test("POST /bookmarks/:id/wayback for another user's bookmark returns 404")
    func apiManualSubmitScopedToUser() async throws {
        try await withTestApp { app in
            // Given
            let owner = try await app.makeUser(username: "owner", password: "owner-password-123")
            let bookmark = try await app.makeBookmark(for: owner, url: "https://example.com")
            try await app.makeUser(username: "intruder", password: "intruder-password-123")
            let pair = try await app.login(username: "intruder", password: "intruder-password-123")

            // When
            try await app.testing().test(
                .POST, "api/v1/bookmarks/\(bookmark.requireID())/wayback",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(res.status == .notFound, "It should not let a user submit another user's bookmark")
            }
        }
    }

    // MARK: - Manual submit (web)

    @Test("the web save-to-wayback route queues the bookmark and redirects with the wayback_started flash")
    func webSaveToWaybackQueues() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let bookmarkID = try bookmark.requireID()

            // When
            try await app.testing().test(
                .POST, "app/bookmarks/\(bookmarkID)/save-to-wayback",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect after queueing")
                #expect(
                    res.headers.first(name: .location) == "/app/bookmarks/\(bookmarkID)?ok=wayback_started",
                    "It should PRG back to the detail page with the wayback flash"
                )
            }

            let reloaded = try #require(try await Bookmark.find(bookmarkID, on: app.db))
            #expect(reloaded.waybackStatus == .pending, "It should queue the bookmark")
        }
    }

    @Test("the web save-to-wayback route doesn't queue and shows an error flash when disabled instance-wide")
    func webSaveToWaybackNoOpWhenDisabled() async throws {
        try await withTestApp { app in
            // Given
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.internetArchiveEnabled = false
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)
            let headers = try await app.appWebSession()
            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            let bookmark = try await app.makeBookmark(for: user, url: "https://example.com")
            let bookmarkID = try bookmark.requireID()

            // When
            try await app.testing().test(
                .POST, "app/bookmarks/\(bookmarkID)/save-to-wayback",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should still redirect")
                #expect(
                    res.headers
                        .first(name: .location) == "/app/bookmarks/\(bookmarkID)?error=internet_archive_disabled",
                    "It should redirect with an error flash explaining why nothing happened"
                )
            }

            let reloaded = try #require(try await Bookmark.find(bookmarkID, on: app.db))
            #expect(reloaded.waybackStatus == .none, "It should not queue the bookmark when disabled")
        }
    }

    // MARK: - User settings toggle

    @Test("the archive preference toggle updates the user and redirects with the archive_pref flash")
    func settingsTogglePreference() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.appWebSession()

            // When — turning it off (no "enabled" field submitted)
            try await app.testing().test(
                .POST, "app/settings/archive-pref",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(["_unused": "1"], as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .seeOther, "It should redirect after saving")
                    #expect(
                        res.headers.first(name: .location) == "/app/settings?ok=archive_pref",
                        "It should PRG to the settings page"
                    )
                }
            )

            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            #expect(!user.archiveNewBookmarks, "It should turn the preference off when the checkbox is unchecked")
        }
    }

    @Test("unchecking the sole archive-pref checkbox sends a genuinely empty body, which still succeeds")
    func settingsTogglePreferenceWithTrulyEmptyBody() async throws {
        try await withTestApp { app in
            // Given
            var headers = try await app.appWebSession()
            headers.replaceOrAdd(name: .contentType, value: "application/x-www-form-urlencoded")

            // When — a real browser sends zero bytes when the form's only field is unchecked
            try await app.testing().test(
                .POST, "app/settings/archive-pref",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect after saving, not 422")
                #expect(
                    res.headers.first(name: .location) == "/app/settings?ok=archive_pref",
                    "It should PRG to the settings page"
                )
            }

            let user = try #require(try await User.query(on: app.db).filter(\.$username == "otavio").first())
            #expect(!user.archiveNewBookmarks, "It should turn the preference off when the checkbox is unchecked")
        }
    }

    // MARK: - Admin dashboard

    @Test("the admin Internet Archive page shows counts per status")
    func adminPageCounts() async throws {
        try await withTestApp { app in
            // Given — a distinct count per status, so a swapped or miscounted status is detectable
            let headers = try await app.adminWebSession()
            let user = try await app.makeUser(username: "alice", password: "alice-password-123")

            func makeBookmarks(_ status: WaybackStatus, count: Int) async throws {
                for index in 0..<count {
                    let bookmark = try await app.makeBookmark(
                        for: user,
                        url: "https://\(status.rawValue)\(index).example.com"
                    )
                    bookmark.waybackStatus = status
                    try await bookmark.save(on: app.db)
                }
            }

            try await makeBookmarks(.none, count: 2)
            try await makeBookmarks(.archived, count: 1)
            try await makeBookmarks(.pending, count: 3)
            try await makeBookmarks(.failed, count: 4)

            // When
            try await app.testing().test(.GET, "admin/internet-archive", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the page")
                let body = res.body.string
                #expect(
                    body.contains("<div class=\"num\">10</div>\n            <div class=\"label\">Total</div>"),
                    "It should show 10 total"
                )
                #expect(
                    body.contains("<div class=\"num\">1</div>\n            <div class=\"label\">Archived</div>"),
                    "It should show 1 archived"
                )
                #expect(
                    body.contains("<div class=\"num\">3</div>\n            <div class=\"label\">Queued</div>"),
                    "It should show 3 queued (pending)"
                )
                #expect(
                    body.contains("<div class=\"num\">4</div>\n            <div class=\"label\">Failed</div>"),
                    "It should show 4 failed"
                )
                #expect(
                    body.contains("<div class=\"num\">2</div>\n            <div class=\"label\">Not submitted</div>"),
                    "It should show 2 not submitted"
                )
            }
        }
    }

    @Test("toggling the instance switch off disables submissions and redirects with the ia_saved flash")
    func adminToggleDisables() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(
                .POST, "admin/internet-archive/toggle",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(["_unused": "1"], as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .seeOther, "It should redirect after saving")
                    #expect(
                        res.headers.first(name: .location) == "/admin/internet-archive?ok=ia_saved",
                        "It should PRG to the page with the saved flash"
                    )
                }
            )

            let settings = try await SiteSettingsService.current(on: app.db)
            #expect(!settings.internetArchiveEnabled, "It should turn the switch off when unchecked")
            let cached = app.storage[SiteSettingsCacheKey.self]?.current
            #expect(cached?.internetArchiveEnabled == false, "It should refresh the app-level cache")

            let rows = try await AuditLog.query(on: app.db).filter(\.$action == "internet_archive_toggled").all()
            #expect(rows.count == 1, "It should audit-log its own distinct action, not appearance_updated")
        }
    }

    @Test("unchecking the sole checkbox sends a genuinely empty body, which still succeeds")
    func adminToggleDisablesWithTrulyEmptyBody() async throws {
        try await withTestApp { app in
            // Given
            var headers = try await app.adminWebSession()
            headers.replaceOrAdd(name: .contentType, value: "application/x-www-form-urlencoded")

            // When — a real browser sends zero bytes when the form's only field is unchecked
            try await app.testing().test(
                .POST, "admin/internet-archive/toggle",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect after saving, not 422")
                #expect(
                    res.headers.first(name: .location) == "/admin/internet-archive?ok=ia_saved",
                    "It should PRG to the page with the saved flash"
                )
            }

            let settings = try await SiteSettingsService.current(on: app.db)
            #expect(!settings.internetArchiveEnabled, "It should turn the switch off when unchecked")
        }
    }

    @Test("retry-failed and queue-all are refused when disabled instance-wide")
    func adminBulkActionsRefusedWhenDisabled() async throws {
        try await withTestApp { app in
            // Given
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.internetArchiveEnabled = false
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)
            let headers = try await app.adminWebSession()
            let user = try await app.makeUser(username: "alice", password: "alice-password-123")
            let failed = try await app.makeBookmark(for: user, url: "https://failed.example.com")
            failed.waybackStatus = .failed
            try await failed.save(on: app.db)
            let notSubmitted = try await app.makeBookmark(for: user, url: "https://none.example.com")

            // When / Then
            try await app.testing()
                .test(.POST, "admin/internet-archive/retry-failed", headers: headers) { res async throws in
                    #expect(res.status == .seeOther, "It should still redirect")
                    #expect(
                        res.headers.first(name: .location) == "/admin/internet-archive?error=internet_archive_disabled",
                        "It should refuse with an error flash instead of re-queueing"
                    )
                }
            try await app.testing()
                .test(.POST, "admin/internet-archive/queue-all", headers: headers) { res async throws in
                    #expect(res.status == .seeOther, "It should still redirect")
                    #expect(
                        res.headers.first(name: .location) == "/admin/internet-archive?error=internet_archive_disabled",
                        "It should refuse with an error flash instead of queueing"
                    )
                }

            let reloadedFailed = try #require(try await Bookmark.find(failed.requireID(), on: app.db))
            #expect(reloadedFailed.waybackStatus == .failed, "It should leave the failed bookmark unqueued")
            let reloadedNone = try #require(try await Bookmark.find(notSubmitted.requireID(), on: app.db))
            #expect(reloadedNone.waybackStatus == .none, "It should leave the not-submitted bookmark unqueued")
        }
    }

    @Test("retrying failed submissions re-queues only failed bookmarks")
    func adminRetryFailed() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            let user = try await app.makeUser(username: "alice", password: "alice-password-123")
            let failed = try await app.makeBookmark(for: user, url: "https://failed.example.com")
            failed.waybackStatus = .failed
            try await failed.save(on: app.db)
            let archived = try await app.makeBookmark(for: user, url: "https://archived.example.com")
            archived.waybackStatus = .archived
            try await archived.save(on: app.db)

            // When
            try await app.testing()
                .test(.POST, "admin/internet-archive/retry-failed", headers: headers) { res async throws in
                    // Then
                    #expect(res.status == .seeOther, "It should redirect after re-queueing")
                    #expect(
                        res.headers.first(name: .location) == "/admin/internet-archive?ok=ia_retrying",
                        "It should PRG with the retrying flash"
                    )
                }

            let reloadedFailed = try #require(try await Bookmark.find(failed.requireID(), on: app.db))
            #expect(reloadedFailed.waybackStatus == .pending, "It should re-queue the failed bookmark")
            let reloadedArchived = try #require(try await Bookmark.find(archived.requireID(), on: app.db))
            #expect(reloadedArchived.waybackStatus == .archived, "It should leave already-archived bookmarks alone")
        }
    }

    @Test("queuing all bookmarks submits every not-submitted or failed bookmark, leaving archived/pending alone")
    func adminQueueAll() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()
            let user = try await app.makeUser(username: "alice", password: "alice-password-123")
            let notSubmitted = try await app.makeBookmark(for: user, url: "https://none.example.com")
            let failed = try await app.makeBookmark(for: user, url: "https://failed.example.com")
            failed.waybackStatus = .failed
            try await failed.save(on: app.db)
            let archived = try await app.makeBookmark(for: user, url: "https://archived.example.com")
            archived.waybackStatus = .archived
            try await archived.save(on: app.db)

            // When
            try await app.testing()
                .test(.POST, "admin/internet-archive/queue-all", headers: headers) { res async throws in
                    // Then
                    #expect(res.status == .seeOther, "It should redirect after queueing")
                    #expect(
                        res.headers.first(name: .location) == "/admin/internet-archive?ok=ia_queued",
                        "It should PRG with the queued flash"
                    )
                }

            let reloadedNone = try #require(try await Bookmark.find(notSubmitted.requireID(), on: app.db))
            #expect(reloadedNone.waybackStatus == .pending, "It should queue the not-yet-submitted bookmark")
            let reloadedFailed = try #require(try await Bookmark.find(failed.requireID(), on: app.db))
            #expect(reloadedFailed.waybackStatus == .pending, "It should re-queue the failed bookmark")
            let reloadedArchived = try #require(try await Bookmark.find(archived.requireID(), on: app.db))
            #expect(reloadedArchived.waybackStatus == .archived, "It should leave the already-archived bookmark alone")
        }
    }

    @Test("the admin Internet Archive page shows the disabled status text when the switch is off")
    func adminPageShowsDisabledStatus() async throws {
        try await withTestApp { app in
            // Given
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.internetArchiveEnabled = false
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(.GET, "admin/internet-archive", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the page")
                #expect(
                    res.body.string.contains("Disabled — no submissions will run."),
                    "It should show the disabled queue status"
                )
            }
        }
    }

    @Test("the admin Internet Archive page shows the idle status text when enabled with nothing queued")
    func adminPageShowsIdleStatus() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()

            // When
            try await app.testing().test(.GET, "admin/internet-archive", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the page")
                #expect(
                    res.body.string.contains("Idle — nothing queued."),
                    "It should show the idle queue status when there's nothing pending and nothing running"
                )
            }
        }
    }

    @Test("resuming the queue is refused when disabled instance-wide")
    func adminResumeRefusedWhenDisabled() async throws {
        try await withTestApp { app in
            // Given
            let settings = try await SiteSettingsService.current(on: app.db)
            settings.internetArchiveEnabled = false
            try await settings.save(on: app.db)
            SiteSettingsService.refreshCache(with: settings, on: app)
            let headers = try await app.adminWebSession()

            // When / Then
            try await app.testing().test(.POST, "admin/internet-archive/resume", headers: headers) { res async throws in
                #expect(res.status == .seeOther, "It should still redirect")
                #expect(
                    res.headers.first(name: .location) == "/admin/internet-archive?error=internet_archive_disabled",
                    "It should refuse with an error flash instead of nudging the queue"
                )
            }
        }
    }

    @Test("resuming the queue redirects with the ia_resumed flash when enabled")
    func adminResumeSucceedsWhenEnabled() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await app.adminWebSession()

            // When / Then
            try await app.testing().test(.POST, "admin/internet-archive/resume", headers: headers) { res async throws in
                #expect(res.status == .seeOther, "It should redirect after nudging the queue")
                #expect(
                    res.headers.first(name: .location) == "/admin/internet-archive?ok=ia_resumed",
                    "It should PRG with the resumed flash"
                )
            }
        }
    }

    @Test("the admin Internet Archive page requires an admin session")
    func adminPageRequiresAuth() async throws {
        try await withTestApp { app in
            // When
            try await app.testing().test(.GET, "admin/internet-archive") { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect rather than render the page")
                #expect(
                    res.headers.first(name: .location) == "/admin/login",
                    "It should redirect to the admin login page"
                )
            }
        }
    }
}
