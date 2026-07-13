// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Testing
import VaporTesting
@testable import App

/// Verifies audit-log hooks on the admin web dashboard and app web frontend, plus the
/// `/admin/audit` viewer page itself.
@Suite("Audit log — web surfaces")
struct AuditLogWebTests {

    // MARK: - Admin web login / logout

    @Test("admin web login success and failure are both audited")
    func adminWebLoginAudited() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)

            // When — failure
            try await app.testing().test(
                .POST, "admin/login",
                beforeRequest: { req in
                    try req.content.encode(
                        LoginForm(username: "root", password: "wrong-password!", totpCode: nil),
                        as: .urlEncodedForm
                    )
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                }
            )

            // When — success
            _ = try await adminWebSession(app)

            // Then
            let rows = try await AuditLog.query(on: app.db).all()
            #expect(
                rows.contains { $0.action == "login_failure" && $0.actorUsername == "root" },
                "It should record the failed admin web login"
            )
            #expect(
                rows.contains { $0.action == "login_success" && $0.actorUsername == "root" },
                "It should record the successful admin web login"
            )
        }
    }

    @Test("admin web logout is audited")
    func adminWebLogoutAudited() async throws {
        try await withTestApp { app in
            // Given
            let cookie = try await adminWebSession(app)

            // When
            try await app.testing().test(.POST, "admin/logout", headers: cookie) { res async throws in
                #expect(res.status == .seeOther, "It should redirect after logout")
            }

            // Then
            let rows = try await AuditLog.query(on: app.db).filter(\.$action == "logout").all()
            #expect(rows.count == 1, "It should write exactly one logout row")
            #expect(rows.first?.actorUsername == "root", "It should resolve the actor from the session")
        }
    }

    // MARK: - App web login / logout

    @Test("app web login success and failure are both audited")
    func appWebLoginAudited() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")

            // When — failure
            try await app.testing().test(
                .POST, "app/login",
                beforeRequest: { req in
                    try req.content.encode(
                        LoginForm(username: "otavio", password: "wrong-password!", totpCode: nil),
                        as: .urlEncodedForm
                    )
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                }
            )

            // When — success
            _ = try await appWebSession(app)

            // Then
            let rows = try await AuditLog.query(on: app.db).all()
            #expect(
                rows.contains { $0.action == "login_failure" && $0.actorUsername == "otavio" },
                "It should record the failed app web login"
            )
            #expect(
                rows.contains { $0.action == "login_success" && $0.actorUsername == "otavio" },
                "It should record the successful app web login"
            )
        }
    }

    @Test("app web logout is audited")
    func appWebLogoutAudited() async throws {
        try await withTestApp { app in
            // Given
            let cookie = try await appWebSession(app)

            // When
            try await app.testing().test(.POST, "app/logout", headers: cookie) { res async throws in
                #expect(res.status == .seeOther, "It should redirect after logout")
            }

            // Then
            let rows = try await AuditLog.query(on: app.db).filter(\.$action == "logout").all()
            #expect(rows.count == 1, "It should write exactly one logout row")
            #expect(rows.first?.actorUsername == "otavio", "It should resolve the actor from the session")
        }
    }

    // MARK: - Admin web user actions

    @Test("admin web suspend/unsuspend/resetPassword/resetTOTP/deleteUser each write the expected row")
    func webUserActionsAudited() async throws {
        try await withTestApp { app in
            // Given
            let cookie = try await adminWebSession(app)
            let alice = try await app.makeUser(
                username: "alice", password: "alice-password-123",
                isTOTPEnabled: true, totpSecret: "AAAAAAAAAAAAAAAA"
            )
            let aliceID = try alice.requireID()

            func expectRedirect(_ res: TestingHTTPResponse) async throws {
                #expect(res.status == .seeOther)
            }

            // When — suspend
            try await app.testing().test(
                .POST, "admin/users/\(aliceID)/suspend", headers: cookie, afterResponse: expectRedirect
            )
            // When — unsuspend
            try await app.testing().test(
                .POST, "admin/users/\(aliceID)/unsuspend", headers: cookie, afterResponse: expectRedirect
            )
            // When — reset password
            try await app.testing().test(
                .POST, "admin/users/\(aliceID)/reset-password",
                headers: cookie,
                beforeRequest: { req in
                    try req.content.encode(ResetPasswordForm(password: "brand-new-password-456"), as: .urlEncodedForm)
                },
                afterResponse: expectRedirect
            )
            // When — reset TOTP (2FA is enabled, so this is a genuine reset)
            try await app.testing().test(
                .POST, "admin/users/\(aliceID)/reset-totp", headers: cookie, afterResponse: expectRedirect
            )
            // When — delete
            try await app.testing().test(
                .POST, "admin/users/\(aliceID)/delete", headers: cookie, afterResponse: expectRedirect
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).all()
            let actions = Set(rows.map(\.action))
            #expect(actions.contains("user_suspended"), "It should record the suspend action")
            #expect(actions.contains("user_unsuspended"), "It should record the unsuspend action")
            #expect(actions.contains("password_reset"), "It should record the password reset")
            #expect(actions.contains("totp_reset"), "It should record the TOTP reset")
            #expect(actions.contains("user_deleted"), "It should record the delete action")
        }
    }

    @Test("admin web resetTOTP on a user without 2FA does not write a totp_reset row")
    func webResetTOTPNoOpNotAudited() async throws {
        try await withTestApp { app in
            // Given
            let cookie = try await adminWebSession(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            let aliceID = try alice.requireID()

            // When
            try await app.testing().test(
                .POST, "admin/users/\(aliceID)/reset-totp", headers: cookie
            ) { res async throws in
                #expect(res.status == .seeOther)
            }

            // Then
            let actions = try await AuditLog.query(on: app.db).all().map(\.action)
            #expect(!actions.contains("totp_reset"), "It should not record a reset that never happened")
        }
    }

    @Test("admin web suspend/unsuspend on an already-matching state does not write a duplicate row")
    func webSuspendUnsuspendNoOpNotAudited() async throws {
        try await withTestApp { app in
            // Given
            let cookie = try await adminWebSession(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            let aliceID = try alice.requireID()

            // When — unsuspend a user who is already active
            try await app.testing().test(
                .POST, "admin/users/\(aliceID)/unsuspend", headers: cookie
            ) { res async throws in
                #expect(res.status == .seeOther)
            }

            // Then
            let actions = try await AuditLog.query(on: app.db).all().map(\.action)
            #expect(!actions.contains("user_unsuspended"), "It should not record a state change that never happened")
        }
    }

    @Test("admin web createUser writes a user_created row")
    func webCreateUserAudited() async throws {
        try await withTestApp { app in
            // Given
            let cookie = try await adminWebSession(app)

            // When
            try await app.testing().test(
                .POST, "admin/users/new",
                headers: cookie,
                beforeRequest: { req in
                    try req.content.encode(
                        CreateUserForm(username: "carol", password: "carol-password-123"),
                        as: .urlEncodedForm
                    )
                },
                afterResponse: { res async throws in #expect(res.status == .seeOther) }
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).filter(\.$action == "user_created").all()
            #expect(rows.count == 1, "It should write exactly one user_created row")
        }
    }

    @Test("admin web saveAppearance writes an appearance_updated row")
    func webAppearanceAudited() async throws {
        try await withTestApp { app in
            // Given
            let cookie = try await adminWebSession(app)

            // When
            try await app.testing().test(
                .POST, "admin/appearance",
                headers: cookie,
                beforeRequest: { req in
                    try req.content.encode(
                        AppearanceForm(
                            accentTheme: "forest",
                            aboutText: nil,
                            footerLink0Label: nil, footerLink0URL: nil,
                            footerLink1Label: nil, footerLink1URL: nil,
                            footerLink2Label: nil, footerLink2URL: nil,
                            footerLink3Label: nil, footerLink3URL: nil
                        ),
                        as: .urlEncodedForm
                    )
                },
                afterResponse: { res async throws in #expect(res.status == .seeOther) }
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).filter(\.$action == "appearance_updated").all()
            #expect(rows.count == 1, "It should write exactly one appearance_updated row")
        }
    }

    // MARK: - Viewer page

    @Test("GET /admin/audit renders the 50 most recent rows in descending time order")
    func auditPageRendersRecentRows() async throws {
        try await withTestApp { app in
            // Given
            let cookie = try await adminWebSession(app)
            await AuditLogger.record(action: "login_success", actor: "first", on: app.db)
            await AuditLogger.record(action: "login_success", actor: "second", on: app.db)

            // When
            try await app.testing().test(.GET, "admin/audit", headers: cookie) { res async throws in
                // Then
                #expect(res.status == .ok, "It should return 200 OK")
                let body = res.body.string
                #expect(body.contains("first"), "It should show the first actor")
                #expect(body.contains("second"), "It should show the second actor")
                let firstIndex = body.range(of: "first")!.lowerBound
                let secondIndex = body.range(of: "second")!.lowerBound
                #expect(secondIndex < firstIndex, "It should show the most recent event first")
            }
        }
    }

    @Test("GET /admin/audit shows '(unknown)' for rows with a nil actor")
    func auditPageShowsUnknownActor() async throws {
        try await withTestApp { app in
            // Given
            let cookie = try await adminWebSession(app)
            await AuditLogger.record(action: "logout", actor: nil, on: app.db)

            // When
            try await app.testing().test(.GET, "admin/audit", headers: cookie) { res async throws in
                // Then
                #expect(res.status == .ok, "It should return 200 OK")
                #expect(res.body.string.contains("(unknown)"), "It should show (unknown) for a nil actor")
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
        username: String = "otavio",
        password: String = "correct-horse-battery"
    ) async throws -> HTTPHeaders {
        if try await User.query(on: app.db).filter(\.$username == username).first() == nil {
            try await app.makeUser(username: username, password: password)
        }

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
