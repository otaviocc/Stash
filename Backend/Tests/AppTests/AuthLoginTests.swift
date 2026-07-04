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
}
