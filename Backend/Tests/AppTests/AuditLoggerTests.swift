// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Testing
import VaporTesting
@testable import App

/// Verifies `AuditLogger`'s best-effort, non-throwing write contract.
@Suite("AuditLogger")
struct AuditLoggerTests {

    @Test("record() saves a row with all fields populated")
    func recordSavesRow() async throws {
        try await withTestApp { app in
            // Given: no setup required

            // When
            await AuditLogger.record(
                action: "login_success",
                actor: "otavio",
                detail: "some detail",
                ip: "203.0.113.5",
                on: app.db
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).all()
            #expect(rows.count == 1, "It should save exactly one row")
            #expect(rows.first?.action == "login_success", "It should persist the action")
            #expect(rows.first?.actorUsername == "otavio", "It should persist the actor")
            #expect(rows.first?.detail == "some detail", "It should persist the detail")
            #expect(rows.first?.ip == "203.0.113.5", "It should persist the IP")
        }
    }

    @Test("record() saves a row with nil actor and nil detail")
    func recordSavesRowWithNilFields() async throws {
        try await withTestApp { app in
            // Given: no setup required

            // When
            await AuditLogger.record(action: "logout", actor: nil, on: app.db)

            // Then
            let rows = try await AuditLog.query(on: app.db).all()
            #expect(rows.count == 1, "It should save exactly one row")
            #expect(rows.first?.actorUsername == nil, "It should persist a nil actor")
            #expect(rows.first?.detail == nil, "It should persist a nil detail")
        }
    }

    @Test("clientIP(from:) prefers the left-most X-Forwarded-For entry")
    func clientIPPrefersForwardedFor() async throws {
        try await withTestApp { app in
            // Given
            let req = Request(application: app, on: app.eventLoopGroup.next())
            req.headers.replaceOrAdd(name: "X-Forwarded-For", value: "198.51.100.7, 10.0.0.1")

            // When
            let ip = AuditLogger.clientIP(from: req)

            // Then
            #expect(ip == "198.51.100.7", "It should use the left-most X-Forwarded-For entry")
        }
    }
}
