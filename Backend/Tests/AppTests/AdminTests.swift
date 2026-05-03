// MIT License
//
// Copyright (c) 2026 Otávio C.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Fluent
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the admin endpoints for user management and statistics.
@Suite("Admin — user management & stats")
struct AdminTests {

    // MARK: - Access control

    @Test("non-admin is blocked from /admin/* with 403 and the standard envelope")
    func nonAdminForbidden() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "alice", password: "alice-password-123", role: .user)
            let pair = try await app.login(username: "alice", password: "alice-password-123")

            // When
            for path in ["api/v1/admin/users", "api/v1/admin/stats"] {
                try await app.testing().test(
                    .GET, path,
                    headers: bearer(pair.accessToken)
                ) { res async throws in
                    // Then
                    #expect(res.status == .forbidden, "It should return 403 Forbidden")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.error == true, "It should flag the response as an error")
                    #expect(err.code == "forbidden", "It should return the forbidden error code")
                    #expect(!err.message.isEmpty, "It should include a non-empty error message")
                }
            }
        }
    }

    @Test("unauthenticated requests to /admin/* are rejected with 401")
    func unauthenticatedRejected() async throws {
        try await withTestApp { app in
            // Given — no setup required

            // When
            try await app.testing().test(.GET, "api/v1/admin/users") { res async throws in
                // Then
                #expect(res.status == .unauthorized, "It should return 401 Unauthorized")
                #expect(try res.content.decode(TestError.self).error == true, "It should flag the response as an error")
            }
        }
    }

    // MARK: - List & get

    @Test("admin lists all users")
    func listUsers() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeUser(username: "bob", password: "bob-password-1234")

            // When
            try await app.testing().test(
                .GET,
                "api/v1/admin/users",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.status == .ok, "It should return 200 OK")
                let users = try res.content.decode([UserResponse].self)
                let names = Set(users.map(\.username))
                #expect(names == ["root", "alice", "bob"], "It should list every user account")
            }
        }
    }

    @Test("get single user, and 404 for unknown id")
    func getUser() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .GET, "api/v1/admin/users/\(alice.requireID())",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.status == .ok, "It should return 200 OK for a known user")
                #expect(
                    try res.content.decode(UserResponse.self).username == "alice",
                    "It should return the requested user"
                )
            }

            try await app.testing().test(
                .GET, "api/v1/admin/users/\(UUID())",
                headers: headers
            ) { res async throws in
                #expect(res.status == .notFound, "It should return 404 for an unknown id")
                #expect(
                    try res.content.decode(TestError.self).code == "not_found",
                    "It should return the not_found error code"
                )
            }
        }
    }

    // MARK: - Create

    @Test("create user returns 201 and the new account can log in")
    func createUser() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)

            // When
            try await app.testing().test(
                .POST, "api/v1/admin/users",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(CreateUserInput(username: "Alice", password: "alice-password-123"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .created, "It should return 201 Created")
                    let user = try res.content.decode(UserResponse.self)
                    #expect(user.username == "alice", "It should lowercase the username")
                    #expect(user.role == .user, "It should create the account with the user role")
                    #expect(user.isActive == true, "It should create the account as active")
                    #expect(user.bookmarkCount == 0, "It should start with zero bookmarks")
                }
            )

            _ = try await app.login(username: "alice", password: "alice-password-123")
        }
    }

    @Test("a role field in the create body is ignored — the account is always a user")
    func createUserIgnoresRole() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let body = #"{"username":"carol","password":"carol-password-123","role":"admin"}"#

            // When
            try await app.testing().test(
                .POST, "api/v1/admin/users",
                headers: headers,
                beforeRequest: { req in
                    req.headers.contentType = .json
                    req.body = ByteBuffer(string: body)
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .created, "It should return 201 Created")
                    #expect(
                        try res.content.decode(UserResponse.self).role == .user,
                        "It should ignore the requested role and create a user"
                    )
                }
            )

            let carol = try await User.query(on: app.db).filter(\.$username == "carol").first()
            #expect(carol?.role == .user, "It should persist the account as a user, not an admin")
        }
    }

    @Test("duplicate username returns 409 username_taken")
    func duplicateUsername() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            try await app.makeUser(username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .POST, "api/v1/admin/users",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(CreateUserInput(username: "alice", password: "another-password-123"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .conflict, "It should return 409 Conflict")
                    #expect(
                        try res.content.decode(TestError.self).code == "username_taken",
                        "It should return the username_taken error code"
                    )
                }
            )
        }
    }

    @Test("create user with a too-short password fails validation (422)")
    func createUserShortPassword() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)

            // When
            try await app.testing().test(
                .POST, "api/v1/admin/users",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(CreateUserInput(username: "dave", password: "short"))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unprocessableEntity, "It should return 422 Unprocessable Entity")
                    #expect(
                        try res.content.decode(TestError.self).code == "validation_failed",
                        "It should return the validation_failed error code"
                    )
                }
            )
        }
    }

    // MARK: - Suspend / unsuspend

    @Test("suspending a user sets isActive=false and invalidates their refresh tokens")
    func suspendUser() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            let aliceTokens = try await app.login(username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(alice.requireID())",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(UpdateUserInput(isActive: false, password: nil))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .ok, "It should return 200 OK")
                    #expect(
                        try res.content.decode(UserResponse.self).isActive == false,
                        "It should mark the account as inactive"
                    )
                }
            )

            try await app.testing().test(
                .POST, "api/v1/auth/refresh",
                beforeRequest: { req in
                    try req.content.encode(RefreshRequest(refreshToken: aliceTokens.refreshToken))
                },
                afterResponse: { res async throws in #expect(
                    res.status == .unauthorized,
                    "It should reject the suspended user's existing refresh token"
                ) }
            )

            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in try req.content.encode(LoginRequest(
                    username: "alice",
                    password: "alice-password-123"
                )) },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized, "It should reject login for the suspended user")
                    #expect(
                        try res.content.decode(TestError.self).code == "account_suspended",
                        "It should return the account_suspended error code"
                    )
                }
            )
        }
    }

    @Test("unsuspending a user restores login")
    func unsuspendUser() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123", isActive: false)
            let id = try alice.requireID()

            // When
            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(id)",
                headers: headers,
                beforeRequest: { req in try req.content.encode(UpdateUserInput(isActive: true, password: nil)) },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .ok, "It should return 200 OK")
                    #expect(
                        try res.content.decode(UserResponse.self).isActive == true,
                        "It should mark the account as active"
                    )
                }
            )

            _ = try await app.login(username: "alice", password: "alice-password-123")
        }
    }

    // MARK: - Reset password

    @Test("resetting a password: old fails, new works")
    func resetPassword() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(alice.requireID())",
                headers: headers,
                beforeRequest: { req in try req.content.encode(UpdateUserInput(
                    isActive: nil,
                    password: "brand-new-password-456"
                )) },
                afterResponse: { res async throws in #expect(
                    res.status == .ok,
                    "It should return 200 OK for the password reset"
                ) }
            )

            // Then
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in try req.content.encode(LoginRequest(
                    username: "alice",
                    password: "alice-password-123"
                )) },
                afterResponse: { res async throws in #expect(
                    res.status == .unauthorized,
                    "It should reject login with the old password"
                ) }
            )

            _ = try await app.login(username: "alice", password: "brand-new-password-456")
        }
    }

    @Test("resetting a password invalidates the user's existing refresh tokens")
    func resetPasswordInvalidatesSessions() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            let aliceTokens = try await app.login(username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(alice.requireID())",
                headers: headers,
                beforeRequest: { req in try req.content.encode(UpdateUserInput(
                    isActive: nil,
                    password: "brand-new-password-456"
                )) },
                afterResponse: { res async throws in #expect(
                    res.status == .ok,
                    "It should return 200 OK for the password reset"
                ) }
            )

            // Then
            let remaining = try await RefreshToken.query(on: app.db).filter(\.$user.$id == alice.requireID()).count()
            #expect(remaining == 0, "It should delete all of the user's refresh tokens")

            try await app.testing().test(
                .POST, "api/v1/auth/refresh",
                beforeRequest: { req in
                    try req.content.encode(RefreshRequest(refreshToken: aliceTokens.refreshToken))
                },
                afterResponse: { res async throws in #expect(
                    res.status == .unauthorized,
                    "It should reject the user's previously issued refresh token"
                ) }
            )
        }
    }

    @Test("resetting to a too-short password fails validation (422)")
    func resetPasswordTooShort() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(alice.requireID())",
                headers: headers,
                beforeRequest: { req in try req.content.encode(UpdateUserInput(isActive: nil, password: "short")) },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .unprocessableEntity, "It should return 422 Unprocessable Entity")
                    #expect(
                        try res.content.decode(TestError.self).code == "validation_failed",
                        "It should return the validation_failed error code"
                    )
                }
            )
        }
    }

    // MARK: - Hard delete

    @Test("hard delete removes the user and cascades bookmarks, refresh tokens, recovery codes")
    func hardDelete() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            let aliceID = try alice.requireID()

            try await app.makeBookmark(for: alice, url: "https://a.com")
            try await app.makeBookmark(for: alice, url: "https://b.com")
            _ = try await app.login(username: "alice", password: "alice-password-123")
            try await RecoveryCode(userID: aliceID, codeHash: "hash").save(on: app.db)

            // When
            try await app.testing().test(
                .DELETE, "api/v1/admin/users/\(aliceID)",
                headers: headers
            ) { res async throws in #expect(res.status == .noContent, "It should return 204 No Content") }

            // Then
            #expect(try await User.find(aliceID, on: app.db) == nil, "It should delete the user")
            let bookmarks = try await Bookmark.query(on: app.db).filter(\.$user.$id == aliceID).count()
            let tokens = try await RefreshToken.query(on: app.db).filter(\.$user.$id == aliceID).count()
            let codes = try await RecoveryCode.query(on: app.db).filter(\.$user.$id == aliceID).count()
            #expect(bookmarks == 0, "It should cascade-delete the user's bookmarks")
            #expect(tokens == 0, "It should cascade-delete the user's refresh tokens")
            #expect(codes == 0, "It should cascade-delete the user's recovery codes")
        }
    }

    @Test("delete unknown user returns 404")
    func deleteUnknown() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)

            // When
            try await app.testing().test(
                .DELETE, "api/v1/admin/users/\(UUID())",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.status == .notFound, "It should return 404 for an unknown user")
            }
        }
    }

    @Test("an admin cannot delete their own account (400 cannot_delete_self)")
    func cannotDeleteSelf() async throws {
        try await withTestApp { app in
            // Given
            let admin = try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
            let pair = try await app.login(username: "root", password: "admin-password-123")
            let adminID = try admin.requireID()

            // When
            try await app.testing().test(
                .DELETE, "api/v1/admin/users/\(adminID)",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(res.status == .badRequest, "It should return 400 Bad Request")
                let err = try res.content.decode(TestError.self)
                #expect(err.error == true, "It should flag the response as an error")
                #expect(err.code == "cannot_delete_self", "It should return the cannot_delete_self error code")
                #expect(
                    err.message == "An admin cannot delete their own account.",
                    "It should explain why the deletion was rejected"
                )
            }

            #expect(try await User.find(adminID, on: app.db) != nil, "It should leave the admin account intact")
        }
    }

    // MARK: - Stats

    @Test("stats reports totals and per-user bookmark counts")
    func stats() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            let bob = try await app.makeUser(username: "bob", password: "bob-password-1234")

            try await app.makeBookmark(for: alice, url: "https://a1.com")
            try await app.makeBookmark(for: alice, url: "https://a2.com")
            try await app.makeBookmark(for: alice, url: "https://a3.com")
            try await app.makeBookmark(for: bob, url: "https://b1.com")

            // When
            try await app.testing().test(
                .GET,
                "api/v1/admin/stats",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.status == .ok, "It should return 200 OK")
                let stats = try res.content.decode(AdminStatsResponse.self)
                #expect(stats.totalUsers == 3, "It should count every user")
                #expect(stats.totalBookmarks == 4, "It should count every bookmark")
                let byName = Dictionary(uniqueKeysWithValues: stats.users.map { ($0.username, $0) })
                #expect(byName["alice"]?.bookmarkCount == 3, "It should report alice's bookmark count")
                #expect(byName["bob"]?.bookmarkCount == 1, "It should report bob's bookmark count")
                #expect(byName["root"]?.bookmarkCount == 0, "It should report root's bookmark count")
                #expect(byName["alice"]?.isActive == true, "It should report whether each user is active")
            }
        }
    }

    private func adminHeaders(_ app: Application) async throws -> HTTPHeaders {
        try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
        let pair = try await app.login(username: "root", password: "admin-password-123")
        return bearer(pair.accessToken)
    }
}
