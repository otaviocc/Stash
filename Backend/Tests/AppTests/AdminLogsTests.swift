// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Logging
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the `/admin/logs` viewer page (Feature #8: System Logs).
@Suite("Admin logs viewer")
struct AdminLogsTests {

    @Test("GET /admin/logs renders successfully for an authenticated admin")
    func renderLogsPage() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminWebSession(app)

            // When
            try await app.testing().test(.GET, "admin/logs", headers: headers) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the logs page")
            }
        }
    }

    @Test("GET /admin/logs?level=error only shows error-and-above entries")
    func filterByLevel() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminWebSession(app)
            sharedLogBuffer.append(.init(timestamp: Date(), level: .info, label: "App", message: "info-marker"))
            sharedLogBuffer.append(.init(timestamp: Date(), level: .error, label: "App", message: "error-marker"))

            // When
            try await app.testing().test(.GET, "admin/logs?level=error", headers: headers) { res async throws in
                let body = res.body.string

                // Then
                #expect(body.contains("error-marker"), "It should show error-level entries")
                #expect(!body.contains("info-marker"), "It should hide entries below the selected level")
            }
        }
    }

    @Test("GET /admin/logs?level=critical (not offered by the dropdown) is treated as no filter")
    func unofferedLevelIsNotFiltered() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminWebSession(app)
            sharedLogBuffer.append(.init(timestamp: Date(), level: .info, label: "App", message: "info-marker"))
            sharedLogBuffer.append(.init(timestamp: Date(), level: .critical, label: "App", message: "critical-marker"))

            // When
            try await app.testing().test(.GET, "admin/logs?level=critical", headers: headers) { res async throws in
                let body = res.body.string

                // Then
                #expect(body.contains("info-marker"), "It should not filter by a level the dropdown doesn't offer")
                #expect(body.contains("critical-marker"), "It should still show the unfiltered entries")
                #expect(
                    body.contains(#"<option value="" selected>All levels</option>"#),
                    "It should render 'All levels' as selected, matching the actual (unfiltered) result"
                )
            }
        }
    }

    @Test("GET /admin/logs is rejected for unauthenticated requests")
    func requiresAdminSession() async throws {
        try await withTestApp { app in
            // Given: no setup required

            // When
            try await app.testing().test(.GET, "admin/logs") { res async throws in
                // Then
                #expect(res.status == .seeOther, "It should redirect unauthenticated requests to the login page")
            }
        }
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
