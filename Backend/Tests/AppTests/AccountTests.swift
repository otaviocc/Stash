// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Testing
import VaporTesting
@testable import App

/// Verifies the current-user profile endpoint and password-change flow.
@Suite("Account — /me and password change")
struct AccountTests {

    @Test("GET /me returns the current user profile")
    func me() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery", role: .admin)
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .GET, "api/v1/me",
                headers: ["Authorization": "Bearer \(pair.accessToken)"]
            ) { res async throws in
                // Then
                #expect(res.status == .ok, "It should return 200 OK")
                let user = try res.content.decode(UserResponse.self)
                #expect(user.username == "otavio", "It should return the authenticated user's username")
                #expect(user.role == .admin, "It should return the user's role")
                #expect(user.isTOTPEnabled == false, "It should report that TOTP is not enabled")
            }
        }
    }

    @Test("password change requires the correct current password")
    func changePasswordWrongCurrent() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .PUT, "api/v1/me/password",
                headers: ["Authorization": "Bearer \(pair.accessToken)"],
                beforeRequest: { req in
                    try req.content.encode(ChangePasswordRequest(
                        currentPassword: "wrong-current-pw",
                        newPassword: "a-brand-new-password"
                    ))
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

    @Test("new password under 12 characters fails validation")
    func changePasswordTooShort() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .PUT, "api/v1/me/password",
                headers: ["Authorization": "Bearer \(pair.accessToken)"],
                beforeRequest: { req in
                    try req.content.encode(ChangePasswordRequest(
                        currentPassword: "correct-horse-battery",
                        newPassword: "short"
                    ))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unprocessableEntity, "It should return 422 Unprocessable Entity")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "validation_failed", "It should return the validation_failed error code")
                }
            )
        }
    }

    @Test("password change succeeds, then the new password works for login")
    func changePasswordSuccess() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            // When
            try await app.testing().test(
                .PUT, "api/v1/me/password",
                headers: ["Authorization": "Bearer \(pair.accessToken)"],
                beforeRequest: { req in
                    try req.content.encode(ChangePasswordRequest(
                        currentPassword: "correct-horse-battery",
                        newPassword: "a-brand-new-password"
                    ))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .noContent, "It should return 204 No Content")
                }
            )

            _ = try await app.login(username: "otavio", password: "a-brand-new-password")
        }
    }
}
