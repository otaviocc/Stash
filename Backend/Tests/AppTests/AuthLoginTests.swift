// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Testing
import VaporTesting
@testable import App

/// Verifies the authentication flow: login, token refresh, and logout.
@Suite("Auth — login, refresh, logout")
struct AuthLoginTests {

    @Test("login with correct credentials (no 2FA) returns a token pair")
    func loginSuccess() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "otavio", password: "correct-horse-battery"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .ok, "It should return 200 OK")
                    let pair = try res.content.decode(TokenPair.self)
                    #expect(!pair.accessToken.isEmpty, "It should return a non-empty access token")
                    #expect(!pair.refreshToken.isEmpty, "It should return a non-empty refresh token")
                }
            )
        }
    }

    @Test("username is matched case-insensitively")
    func loginCaseInsensitive() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "OTAVIO", password: "correct-horse-battery"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .ok, "It should match the username case-insensitively and log in")
                }
            )
        }
    }

    @Test("wrong password is rejected with invalid_credentials")
    func loginWrongPassword() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "otavio", password: "wrong-password!"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "invalid_credentials", "It should return the invalid_credentials error code")
                }
            )
        }
    }

    @Test("unknown username is rejected with invalid_credentials")
    func loginUnknownUser() async throws {
        try await withTestApp { app in
            // Given — no setup required

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "ghost", password: "whatever-long-pw"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "invalid_credentials", "It should return the invalid_credentials error code")
                }
            )
        }
    }

    @Test("suspended account cannot log in")
    func loginSuspended() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery", isActive: false)

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "otavio", password: "correct-horse-battery"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "account_suspended", "It should return the account_suspended error code")
                }
            )
        }
    }

    @Test("refresh rotates the token: old token is invalidated, new pair issued")
    func refreshRotation() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            var rotated: TokenPair?
            try await app.testing().test(
                .POST, "api/v1/auth/refresh",
                beforeRequest: { req in
                    try req.content.encode(RefreshRequest(refreshToken: pair.refreshToken))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .ok, "It should return 200 OK")
                    rotated = try res.content.decode(TokenPair.self)
                    #expect(rotated?.refreshToken != pair.refreshToken, "It should issue a new refresh token")
                }
            )

            try await app.testing().test(
                .POST, "api/v1/auth/refresh",
                beforeRequest: { req in
                    try req.content.encode(RefreshRequest(refreshToken: pair.refreshToken))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized, "It should reject the original refresh token after rotation")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "token_invalid", "It should return the token_invalid error code")
                }
            )

            try await app.testing().test(
                .POST, "api/v1/auth/refresh",
                beforeRequest: { req in
                    try req.content.encode(RefreshRequest(refreshToken: rotated!.refreshToken))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok, "It should accept the rotated refresh token")
                }
            )
        }
    }

    @Test("logout deletes the refresh token and returns 204")
    func logout() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/logout",
                beforeRequest: { req in
                    try req.content.encode(LogoutRequest(refreshToken: pair.refreshToken))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .noContent, "It should return 204 No Content")
                }
            )

            try await app.testing().test(
                .POST, "api/v1/auth/refresh",
                beforeRequest: { req in
                    try req.content.encode(RefreshRequest(refreshToken: pair.refreshToken))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized, "It should reject the logged-out refresh token")
                }
            )
        }
    }

    // MARK: - Audit log

    @Test("successful JSON API login writes a login_success row")
    func jsonLoginSuccessAudited() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")

            // When
            _ = try await app.login(username: "otavio", password: "correct-horse-battery")

            // Then
            let rows = try await AuditLog.query(on: app.db).all()
            #expect(rows.count == 1, "It should write exactly one row")
            #expect(rows.first?.action == "login_success", "It should record a login_success event")
            #expect(rows.first?.actorUsername == "otavio", "It should record the logged-in username")
        }
    }

    @Test("failed JSON API login (wrong password) writes a login_failure row")
    func jsonLoginFailureAudited() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "otavio", password: "wrong-password!"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                }
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).all()
            #expect(rows.count == 1, "It should write exactly one row")
            #expect(rows.first?.action == "login_failure", "It should record a login_failure event")
            #expect(rows.first?.actorUsername == "otavio", "It should record the attempted username")
        }
    }

    @Test("failed JSON API login (unknown username) writes a login_failure row with the attempted username")
    func jsonLoginUnknownUserAudited() async throws {
        try await withTestApp { app in
            // Given — no setup required

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "ghost", password: "whatever-long-pw"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                }
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).all()
            #expect(rows.count == 1, "It should write exactly one row")
            #expect(rows.first?.action == "login_failure", "It should record a login_failure event")
            #expect(rows.first?.actorUsername == "ghost", "It should record the attempted username")
        }
    }

    @Test("JSON API logout writes a logout row with the correct actor")
    func jsonLogoutAudited() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .POST, "api/v1/auth/logout",
                beforeRequest: { req in
                    try req.content.encode(LogoutRequest(refreshToken: pair.refreshToken))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .noContent, "It should return 204 No Content")
                }
            )

            // Then
            let allRows = try await AuditLog.query(on: app.db).all()
            let rows = allRows.filter { $0.action == "logout" }
            #expect(rows.count == 1, "It should write exactly one logout row")
            #expect(rows.first?.actorUsername == "otavio", "It should resolve the actor from the refresh token")
            #expect(rows.first?.detail == "api logout", "It should record which surface the logout came from")
        }
    }
}
