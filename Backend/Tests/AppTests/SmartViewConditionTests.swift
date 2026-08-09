// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the relative-age Smart View conditions, `olderThan` / `newerThan`, covering duration
/// parsing, validation, calendar (not fixed-second) arithmetic, and live query execution.
@Suite("Smart Views: relative date conditions (olderThan / newerThan)")
struct SmartViewConditionTests {

    @Test("olderThan returns only bookmarks created before the cutoff")
    func olderThanFiltersByAge() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let old = try await app.makeBookmark(for: user, url: "https://old.com")
            old.createdAt = Date(timeIntervalSince1970: 0)
            try await old.save(on: app.db)
            try await app.makeBookmark(for: user, url: "https://new.com")
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Stale",
                conditions: [SmartViewConditionPayload(type: "olderThan", value: "30d")]
            )

            // When
            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://old.com"],
                    "It should return only the bookmark older than the cutoff"
                )
            }
        }
    }

    @Test("newerThan returns only bookmarks created after the cutoff")
    func newerThanFiltersByAge() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let old = try await app.makeBookmark(for: user, url: "https://old.com")
            old.createdAt = Date(timeIntervalSince1970: 0)
            try await old.save(on: app.db)
            try await app.makeBookmark(for: user, url: "https://new.com")
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Fresh",
                conditions: [SmartViewConditionPayload(type: "newerThan", value: "7d")]
            )

            // When
            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://new.com"],
                    "It should return only the bookmark newer than the cutoff"
                )
            }
        }
    }

    @Test("olderThan combined with isArchived:false in matchMode all applies both")
    func olderThanCombinedWithArchived() async throws {
        try await withTestApp { app in
            // Given
            let user = try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")
            let oldActive = try await app.makeBookmark(for: user, url: "https://old-active.com", isArchived: false)
            oldActive.createdAt = Date(timeIntervalSince1970: 0)
            try await oldActive.save(on: app.db)
            let oldArchived = try await app.makeBookmark(for: user, url: "https://old-archived.com", isArchived: true)
            oldArchived.createdAt = Date(timeIntervalSince1970: 0)
            try await oldArchived.save(on: app.db)
            try await app.makeBookmark(for: user, url: "https://new-active.com", isArchived: false)
            let view = try await app.makeSmartView(
                token: pair.accessToken,
                name: "Old and active",
                conditions: [
                    SmartViewConditionPayload(type: "olderThan", value: "30d"),
                    SmartViewConditionPayload(type: "isArchived", value: "false")
                ],
                matchMode: "all"
            )

            // When
            try await app.testing().test(
                .GET, "api/v1/smart-views/\(view.id)/bookmarks",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let page = try res.content.decode(Page<BookmarkResponse>.self)
                #expect(
                    page.items.map(\.url) == ["https://old-active.com"],
                    "It should apply both the age and archived conditions"
                )
            }
        }
    }

    @Test("an invalid duration value returns 422", arguments: ["0d", "-7d", "1w", "abc", "", "30"])
    func invalidDurationRejected(value: String) async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/smart-views",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(SmartViewRequestBody(
                        name: "Bad duration",
                        conditions: [SmartViewConditionPayload(type: "olderThan", value: value)]
                    ))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unprocessableEntity, "It should reject the invalid duration '\(value)'")
                    #expect(
                        try res.content.decode(TestError.self).code == "validation_failed",
                        "It should fail validation"
                    )
                }
            )
        }
    }

    @Test("a valid duration value is accepted and stored canonically")
    func validDurationStored() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser()
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/smart-views",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(SmartViewRequestBody(
                        name: "Last year",
                        conditions: [SmartViewConditionPayload(type: "newerThan", value: "1y")]
                    ))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .created, "It should accept a valid duration")
                    let view = try res.content.decode(SmartViewResponse.self)
                    #expect(view.conditions.first?.type == "newerThan", "It should store the condition type")
                    #expect(view.conditions.first?.value == "1y", "It should store the canonical duration value")
                }
            )
        }
    }

    @Test("SmartViewDuration parses valid strings and rejects invalid ones")
    func durationParsing() {
        // Given / When / Then
        #expect(SmartViewDuration(string: "30d")?.canonicalString == "30d", "It should parse days")
        #expect(SmartViewDuration(string: "3m")?.canonicalString == "3m", "It should parse months")
        #expect(SmartViewDuration(string: "1y")?.canonicalString == "1y", "It should parse years")
        #expect(SmartViewDuration(string: "030d")?.canonicalString == "30d", "It should canonicalize leading zeros")
        #expect(SmartViewDuration(string: "0d") == nil, "It should reject zero")
        #expect(SmartViewDuration(string: "-7d") == nil, "It should reject negatives")
        #expect(SmartViewDuration(string: "1w") == nil, "It should reject unknown units")
        #expect(SmartViewDuration(string: "abc") == nil, "It should reject non-numeric input")
        #expect(SmartViewDuration(string: "") == nil, "It should reject an empty string")
        #expect(SmartViewDuration(string: "30") == nil, "It should reject a bare number with no unit")
    }

    @Test("olderThan uses calendar months, not a fixed 30-day multiple")
    func durationUsesCalendarMonths() throws {
        // Given
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let reference = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 31)))

        // When
        let monthCutoff = SmartViewDuration(string: "1m")?.cutoff(from: reference, calendar: calendar)
        let expectedCalendarCutoff = calendar.date(byAdding: .month, value: -1, to: reference)
        let thirtyDaysBefore = calendar.date(byAdding: .day, value: -30, to: reference)

        // Then
        #expect(monthCutoff == expectedCalendarCutoff, "It should subtract one calendar month")
        #expect(monthCutoff != thirtyDaysBefore, "It should not treat a month as a fixed 30 days")
    }
}
