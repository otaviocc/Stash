import Testing
import VaporTesting

@testable import App

@Suite("Auth — login, refresh, logout")
struct AuthLoginTests {
    @Test("login with correct credentials (no 2FA) returns a token pair")
    func loginSuccess() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "otavio", password: "correct-horse-battery"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let pair = try res.content.decode(TokenPair.self)
                    #expect(!pair.accessToken.isEmpty)
                    #expect(!pair.refreshToken.isEmpty)
                }
            )
        }
    }

    @Test("username is matched case-insensitively")
    func loginCaseInsensitive() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "OTAVIO", password: "correct-horse-battery"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("wrong password is rejected with invalid_credentials")
    func loginWrongPassword() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "otavio", password: "wrong-password!"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "invalid_credentials")
                }
            )
        }
    }

    @Test("unknown username is rejected with invalid_credentials")
    func loginUnknownUser() async throws {
        try await withTestApp { app in
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "ghost", password: "whatever-long-pw"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "invalid_credentials")
                }
            )
        }
    }

    @Test("suspended account cannot log in")
    func loginSuspended() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery", isActive: false)
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginRequest(username: "otavio", password: "correct-horse-battery"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "account_suspended")
                }
            )
        }
    }

    @Test("refresh rotates the token: old token is invalidated, new pair issued")
    func refreshRotation() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            var rotated: TokenPair?
            try await app.testing().test(
                .POST, "api/v1/auth/refresh",
                beforeRequest: { req in
                    try req.content.encode(RefreshRequest(refreshToken: pair.refreshToken))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    rotated = try res.content.decode(TokenPair.self)
                    #expect(rotated?.refreshToken != pair.refreshToken)
                }
            )

            // The original refresh token must no longer be accepted.
            try await app.testing().test(
                .POST, "api/v1/auth/refresh",
                beforeRequest: { req in
                    try req.content.encode(RefreshRequest(refreshToken: pair.refreshToken))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    let err = try res.content.decode(TestError.self)
                    #expect(err.code == "token_invalid")
                }
            )

            // The rotated token works.
            try await app.testing().test(
                .POST, "api/v1/auth/refresh",
                beforeRequest: { req in
                    try req.content.encode(RefreshRequest(refreshToken: rotated!.refreshToken))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("logout deletes the refresh token and returns 204")
    func logout() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "otavio", password: "correct-horse-battery")
            let pair = try await app.login(username: "otavio", password: "correct-horse-battery")

            try await app.testing().test(
                .POST, "api/v1/auth/logout",
                beforeRequest: { req in
                    try req.content.encode(LogoutRequest(refreshToken: pair.refreshToken))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .noContent)
                }
            )

            // Refresh with the logged-out token is rejected.
            try await app.testing().test(
                .POST, "api/v1/auth/refresh",
                beforeRequest: { req in
                    try req.content.encode(RefreshRequest(refreshToken: pair.refreshToken))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }
}
