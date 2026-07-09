// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the admin active-sessions viewer and revocation endpoints, both the JSON
/// API (`/api/v1/admin/sessions*`) and the web dashboard (`/admin/sessions*`).
@Suite("Active sessions")
struct ActiveSessionsTests {

    // MARK: - JSON API

    @Test("GET /api/v1/admin/sessions returns empty list when no web sessions exist")
    func listSessionsEmpty() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
            let pair = try await app.login(username: "root", password: "admin-password-123")

            // When
            try await app.testing().test(
                .GET, "api/v1/admin/sessions",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let body = try res.content.decode(SessionsListResponse.self)
                #expect(body.total == 0, "It should report zero active web sessions")
                #expect(body.sessions.isEmpty, "It should return an empty session list")
            }
        }
    }

    @Test("GET /api/v1/admin/sessions lists both admin and app web sessions")
    func listSessionsBothTypes() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
            try await app.makeUser(username: "alice", password: "alice-password-123")
            let pair = try await app.login(username: "root", password: "admin-password-123")
            _ = try await adminWebSession(app)
            _ = try await appWebSession(app, username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .GET, "api/v1/admin/sessions",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let body = try res.content.decode(SessionsListResponse.self)
                #expect(body.total == 2, "It should report both live sessions")
                #expect(
                    body.sessions.contains { $0.username == "root" && $0.sessionType == "admin" },
                    "It should include the admin dashboard session"
                )
                #expect(
                    body.sessions.contains { $0.username == "alice" && $0.sessionType == "app" },
                    "It should include the app frontend session"
                )
            }
        }
    }

    @Test("GET /api/v1/admin/sessions filters by username query param")
    func listSessionsWithQueryFilter() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
            try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeUser(username: "bob", password: "bob-password-1234")
            let pair = try await app.login(username: "root", password: "admin-password-123")
            _ = try await appWebSession(app, username: "alice", password: "alice-password-123")
            _ = try await appWebSession(app, username: "bob", password: "bob-password-1234")

            // When
            try await app.testing().test(
                .GET, "api/v1/admin/sessions?q=ali",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                let body = try res.content.decode(SessionsListResponse.self)
                #expect(body.total == 1, "It should only match the filtered username")
                #expect(body.sessions.first?.username == "alice", "It should return alice's session")
            }
        }
    }

    @Test("POST /api/v1/admin/sessions/revoke-all clears all sessions and refresh tokens")
    func revokeAllSessions() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
            try await app.makeUser(username: "alice", password: "alice-password-123")
            let pair = try await app.login(username: "root", password: "admin-password-123")
            _ = try await app.login(username: "alice", password: "alice-password-123")
            _ = try await appWebSession(app, username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .POST, "api/v1/admin/sessions/revoke-all",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                #expect(res.status == .noContent, "It should return 204 No Content")
            }

            // Then
            try await app.testing().test(
                .GET, "api/v1/admin/sessions",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let body = try res.content.decode(SessionsListResponse.self)
                #expect(body.total == 0, "It should clear every live session")
            }
            let tokenCount = try await RefreshToken.query(on: app.db).count()
            #expect(tokenCount == 0, "It should delete every refresh token")
        }
    }

    @Test("POST /api/v1/admin/sessions/revoke-user revokes only the target user's session")
    func revokeSpecificUser() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
            try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeUser(username: "bob", password: "bob-password-1234")
            let pair = try await app.login(username: "root", password: "admin-password-123")
            _ = try await appWebSession(app, username: "alice", password: "alice-password-123")
            _ = try await appWebSession(app, username: "bob", password: "bob-password-1234")

            // When
            try await app.testing().test(
                .POST, "api/v1/admin/sessions/revoke-user",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(RevokeUserSessionsInput(userName: "alice"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .noContent, "It should return 204 No Content")
                }
            )

            // Then
            try await app.testing().test(
                .GET, "api/v1/admin/sessions",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                let body = try res.content.decode(SessionsListResponse.self)
                #expect(body.total == 1, "It should leave bob's session untouched")
                #expect(body.sessions.first?.username == "bob", "It should only leave bob's session")
            }
        }
    }

    @Test("POST /api/v1/admin/sessions/revoke-user for an unknown user returns 404")
    func revokeNonexistentUserNotFound() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
            let pair = try await app.login(username: "root", password: "admin-password-123")

            // When
            try await app.testing().test(
                .POST, "api/v1/admin/sessions/revoke-user",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(RevokeUserSessionsInput(userName: "ghost"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .notFound, "It should return 404 Not Found")
                }
            )
        }
    }

    // MARK: - Web dashboard

    @Test("GET /admin/sessions renders the sessions page")
    func renderSessionsPage() async throws {
        try await withTestApp { app in
            // Given
            let cookie = try await adminWebSession(app)
            try await app.makeUser(username: "alice", password: "alice-password-123")
            _ = try await appWebSession(app, username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(.GET, "admin/sessions", headers: cookie) { res async throws in
                // Then
                #expect(res.status == .ok, "It should render the sessions page")
                let body = res.body.string
                #expect(body.contains("alice"), "It should list alice's session")
                #expect(body.contains("root"), "It should list the admin's own session")
            }
        }
    }

    @Test("POST /admin/sessions/revoke-all shows a flash message and clears the table")
    func webRevokeAllShowsConfirmation() async throws {
        try await withTestApp { app in
            // Given
            let cookie = try await adminWebSession(app)
            try await app.makeUser(username: "alice", password: "alice-password-123")
            _ = try await appWebSession(app, username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .POST, "admin/sessions/revoke-all",
                headers: cookie
            ) { res async throws in
                #expect(res.status == .seeOther, "It should redirect after revoking")
                #expect(
                    res.headers.first(name: .location)?.contains("ok=sessions-revoked-all") == true,
                    "It should redirect with the revoke-all flash flag"
                )
            }

            // Then — the admin's own dashboard session was cleared, so the next request bounces to login
            try await app.testing().test(.GET, "admin/sessions", headers: cookie) { res async throws in
                #expect(res.status == .seeOther, "It should redirect once the admin's own session is revoked")
                #expect(
                    res.headers.first(name: .location) == "/admin/login",
                    "It should redirect to the login page"
                )
            }
        }
    }

    @Test("POST /admin/sessions/revoke-user revokes only that user's session")
    func webRevokeUserSession() async throws {
        try await withTestApp { app in
            // Given
            let cookie = try await adminWebSession(app)
            try await app.makeUser(username: "alice", password: "alice-password-123")
            _ = try await appWebSession(app, username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .POST, "admin/sessions/revoke-user",
                headers: cookie,
                beforeRequest: { req in
                    try req.content.encode(RevokeUserSessionsForm(userName: "alice"), as: .urlEncodedForm)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .seeOther, "It should redirect after revoking")
                    #expect(
                        res.headers.first(name: .location)?.contains("ok=sessions-revoked-user") == true,
                        "It should redirect with the revoke-user flash flag"
                    )
                }
            )

            // Then — the admin's own session is untouched, so the page renders normally without alice
            try await app.testing().test(.GET, "admin/sessions", headers: cookie) { res async throws in
                #expect(res.status == .ok, "It should still render since only alice's session was revoked")
                #expect(!res.body.string.contains("alice"), "It should no longer list alice's session")
            }
        }
    }

    // MARK: - Helpers

    private func adminWebSession(
        _ app: Application,
        username: String = "root",
        password: String = "admin-password-123"
    ) async throws -> HTTPHeaders {
        if try await User.query(on: app.db).filter(\.$username == username).first() == nil {
            try await app.makeUser(username: username, password: password, role: .admin)
        }

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

    private func appWebSession(
        _ app: Application,
        username: String,
        password: String
    ) async throws -> HTTPHeaders {
        var cookie: String?
        try await app.testing().test(
            .POST, "app/login",
            beforeRequest: { req in
                try req.content.encode(
                    LoginForm(username: username, password: password, totpCode: nil),
                    as: .urlEncodedForm
                )
            },
            afterResponse: { res async throws in
                cookie = res.headers.setCookie?["stash_session"]?.string
            }
        )
        guard let cookie else {
            throw Abort(.internalServerError, reason: "app web login did not set a session cookie")
        }

        return ["Cookie": "stash_session=\(cookie)"]
    }
}
