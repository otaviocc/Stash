// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Testing
import Vapor
import VaporTesting
@testable import App

/// Verifies the admin endpoints for user management and statistics.
@Suite("Admin — user management & stats")
struct AdminTests {

    // MARK: - Access control

    @Test(
        "non-admin is blocked from /admin/* with 403 and the standard envelope",
        arguments: ["api/v1/admin/users", "api/v1/admin/stats"]
    )
    func nonAdminForbidden(path: String) async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "alice", password: "alice-password-123", role: .user)
            let pair = try await app.login(username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .GET, path,
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(res.status == .forbidden, "It should return 403 Forbidden for \(path)")
                let err = try res.content.decode(TestError.self)
                #expect(err.error == true, "It should flag the response as an error")
                #expect(err.code == "forbidden", "It should return the forbidden error code")
                #expect(!err.message.isEmpty, "It should include a non-empty error message")
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

    // MARK: - Reset TOTP

    @Test("resetting TOTP disables 2FA, clears recovery codes, and revokes sessions")
    func resetTOTP() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(
                username: "alice", password: "alice-password-123",
                isTOTPEnabled: true, totpSecret: "JBSWY3DPEHPK3PXP"
            )
            let aliceID = try alice.requireID()
            try await RecoveryCode(userID: aliceID, codeHash: "hash").save(on: app.db)
            try await RefreshToken(
                userID: aliceID, tokenHash: "token-hash", expiresAt: Date(timeIntervalSinceNow: 3600)
            ).save(on: app.db)

            // When
            try await app.testing().test(
                .POST, "api/v1/admin/users/\(aliceID)/reset-totp",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.status == .noContent, "It should return 204 No Content")
            }

            let reloaded = try await User.find(aliceID, on: app.db)
            #expect(reloaded?.isTOTPEnabled == false, "It should disable 2FA")
            #expect(reloaded?.totpSecret == nil, "It should clear the TOTP secret")

            let codeCount = try await RecoveryCode.query(on: app.db).filter(\.$user.$id == aliceID).count()
            #expect(codeCount == 0, "It should delete the recovery codes")

            let tokenCount = try await RefreshToken.query(on: app.db).filter(\.$user.$id == aliceID).count()
            #expect(tokenCount == 0, "It should revoke all refresh tokens")
        }
    }

    @Test("resetting TOTP on a user without 2FA is a no-op that leaves their sessions intact")
    func resetTOTPWhenNotEnabled() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            let aliceID = try alice.requireID()
            try await RefreshToken(
                userID: aliceID, tokenHash: "token-hash", expiresAt: Date(timeIntervalSinceNow: 3600)
            ).save(on: app.db)

            // When
            try await app.testing().test(
                .POST, "api/v1/admin/users/\(aliceID)/reset-totp",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.status == .noContent, "It should return 204 No Content")
            }

            let tokenCount = try await RefreshToken.query(on: app.db).filter(\.$user.$id == aliceID).count()
            #expect(tokenCount == 1, "It should not revoke the sessions of a user who had no 2FA")
        }
    }

    @Test("resetting TOTP for an unknown user returns 404")
    func resetTOTPUnknownUser() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)

            // When
            try await app.testing().test(
                .POST, "api/v1/admin/users/\(UUID())/reset-totp",
                headers: headers
            ) { res async throws in
                // Then
                #expect(res.status == .notFound, "It should return 404 Not Found")
                #expect(
                    try res.content.decode(TestError.self).code == "not_found",
                    "It should return the not_found error code"
                )
            }
        }
    }

    @Test("a non-admin cannot reset another user's TOTP")
    func resetTOTPForbiddenForNonAdmin() async throws {
        try await withTestApp { app in
            // Given
            try await app.makeUser(username: "alice", password: "alice-password-123", role: .user)
            let bob = try await app.makeUser(username: "bob", password: "bob-password-1234", role: .user)
            let pair = try await app.login(username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .POST, "api/v1/admin/users/\(bob.requireID())/reset-totp",
                headers: bearer(pair.accessToken)
            ) { res async throws in
                // Then
                #expect(res.status == .forbidden, "It should return 403 Forbidden")
                #expect(
                    try res.content.decode(TestError.self).code == "forbidden",
                    "It should return the forbidden error code"
                )
            }
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

    @Test("an admin cannot suspend their own account (400 cannot_suspend_self)")
    func cannotSuspendSelf() async throws {
        try await withTestApp { app in
            // Given
            let admin = try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
            let pair = try await app.login(username: "root", password: "admin-password-123")
            let adminID = try admin.requireID()

            // When
            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(adminID)",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(UpdateUserInput(isActive: false, password: nil))
                },
                afterResponse: { res async throws in
                    // Then
                    #expect(res.status == .badRequest, "It should return 400 Bad Request")
                    let err = try res.content.decode(TestError.self)
                    #expect(err.error == true, "It should flag the response as an error")
                    #expect(err.code == "cannot_suspend_self", "It should return the cannot_suspend_self error code")
                    #expect(
                        err.message == "An admin cannot suspend their own account.",
                        "It should explain why the suspension was rejected"
                    )
                }
            )

            #expect(
                try await User.find(adminID, on: app.db)?.isActive == true,
                "It should leave the admin account active"
            )
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

    // MARK: - Audit log

    @Test("JSON API createUser writes a user_created row")
    func apiCreateUserAudited() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)

            // When
            try await app.testing().test(
                .POST, "api/v1/admin/users",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(CreateUserInput(username: "alice", password: "alice-password-123"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .created, "It should return 201 Created")
                }
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).filter(\.$action == "user_created").all()
            #expect(rows.count == 1, "It should write exactly one user_created row")
            #expect(rows.first?.actorUsername == "root", "It should record the admin as the actor")
            #expect(rows.first?.detail?.contains("alice") == true, "It should name the created user in the detail")
        }
    }

    @Test("JSON API updateUser with isActive=false writes a user_suspended row")
    func apiSuspendAudited() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(alice.requireID())",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(UpdateUserInput(isActive: false, password: nil))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok, "It should return 200 OK")
                }
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).filter(\.$action == "user_suspended").all()
            #expect(rows.count == 1, "It should write exactly one user_suspended row")
            #expect(rows.first?.actorUsername == "root", "It should record the admin as the actor")
        }
    }

    @Test("JSON API updateUser with isActive=true writes a user_unsuspended row")
    func apiUnsuspendAudited() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123", isActive: false)

            // When
            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(alice.requireID())",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(UpdateUserInput(isActive: true, password: nil))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok, "It should return 200 OK")
                }
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).filter(\.$action == "user_unsuspended").all()
            #expect(rows.count == 1, "It should write exactly one user_unsuspended row")
        }
    }

    @Test("JSON API updateUser with password writes a password_reset row")
    func apiPasswordResetAudited() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(alice.requireID())",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(UpdateUserInput(isActive: nil, password: "brand-new-password-456"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok, "It should return 200 OK")
                }
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).filter(\.$action == "password_reset").all()
            #expect(rows.count == 1, "It should write exactly one password_reset row")
        }
    }

    @Test("JSON API updateUser with both password and isActive writes two rows")
    func apiCombinedUpdateAuditedTwice() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(alice.requireID())",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(UpdateUserInput(isActive: false, password: "brand-new-password-456"))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok, "It should return 200 OK")
                }
            )

            // Then
            let rows = try await AuditLog.query(on: app.db).all()
            #expect(
                rows.contains { $0.action == "password_reset" },
                "It should record a password_reset row"
            )
            #expect(
                rows.contains { $0.action == "user_suspended" },
                "It should also record a user_suspended row"
            )
        }
    }

    @Test("JSON API deleteUser writes a user_deleted row with the deleted username")
    func apiDeleteUserAudited() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")

            // When
            try await app.testing().test(
                .DELETE, "api/v1/admin/users/\(alice.requireID())", headers: headers
            ) { res async throws in
                #expect(res.status == .noContent, "It should return 204 No Content")
            }

            // Then
            let rows = try await AuditLog.query(on: app.db).filter(\.$action == "user_deleted").all()
            #expect(rows.count == 1, "It should write exactly one user_deleted row")
            #expect(rows.first?.detail?.contains("alice") == true, "It should name the deleted user in the detail")
        }
    }

    @Test("JSON API resetTOTP writes a totp_reset row only when a reset actually occurred")
    func apiResetTOTPAuditedOnlyWhenApplicable() async throws {
        try await withTestApp { app in
            // Given
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(
                username: "alice", password: "alice-password-123",
                isTOTPEnabled: true, totpSecret: "JBSWY3DPEHPK3PXP"
            )

            // When — no 2FA to reset
            let bob = try await app.makeUser(username: "bob", password: "bob-password-1234")
            try await app.testing().test(
                .POST, "api/v1/admin/users/\(bob.requireID())/reset-totp", headers: headers
            ) { res async throws in
                #expect(res.status == .noContent, "It should return 204 No Content")
            }

            // Then
            let rowsAfterNoOp = try await AuditLog.query(on: app.db).filter(\.$action == "totp_reset").all()
            #expect(rowsAfterNoOp.isEmpty, "It should not record a totp_reset row when nothing was reset")

            // When — a real reset
            try await app.testing().test(
                .POST, "api/v1/admin/users/\(alice.requireID())/reset-totp", headers: headers
            ) { res async throws in
                #expect(res.status == .noContent, "It should return 204 No Content")
            }

            // Then
            let rows = try await AuditLog.query(on: app.db).filter(\.$action == "totp_reset").all()
            #expect(rows.count == 1, "It should record exactly one totp_reset row")
        }
    }

    @Test("self-suspend and self-delete guard rejections do NOT write an audit row")
    func selfActionGuardsNotAudited() async throws {
        try await withTestApp { app in
            // Given
            let admin = try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
            let pair = try await app.login(username: "root", password: "admin-password-123")
            let adminID = try admin.requireID()

            // When
            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(adminID)",
                headers: bearer(pair.accessToken),
                beforeRequest: { req in
                    try req.content.encode(UpdateUserInput(isActive: false, password: nil))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .badRequest, "It should return 400 Bad Request")
                }
            )

            try await app.testing().test(
                .DELETE, "api/v1/admin/users/\(adminID)", headers: bearer(pair.accessToken)
            ) { res async throws in
                #expect(res.status == .badRequest, "It should return 400 Bad Request")
            }

            // Then
            let allRows = try await AuditLog.query(on: app.db).all()
            let mutationRows = allRows.filter { $0.action == "user_suspended" || $0.action == "user_deleted" }
            #expect(
                mutationRows.isEmpty,
                "It should not write a user_suspended/user_deleted row for a self-suspend/self-delete rejection"
            )
        }
    }

    private func adminHeaders(_ app: Application) async throws -> HTTPHeaders {
        try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
        let pair = try await app.login(username: "root", password: "admin-password-123")
        return bearer(pair.accessToken)
    }
}
