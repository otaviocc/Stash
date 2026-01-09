import Fluent
import Testing
import Vapor
import VaporTesting

@testable import App

@Suite("Admin — user management & stats")
struct AdminTests {
    // Convenience: seed an admin and return a bearer header for it.
    private func adminHeaders(_ app: Application) async throws -> HTTPHeaders {
        try await app.makeUser(username: "root", password: "admin-password-123", role: .admin)
        let pair = try await app.login(username: "root", password: "admin-password-123")
        return bearer(pair.accessToken)
    }

    // MARK: - Access control

    @Test("non-admin is blocked from /admin/* with 403 and the standard envelope")
    func nonAdminForbidden() async throws {
        try await withTestApp { app in
            try await app.makeUser(username: "alice", password: "alice-password-123", role: .user)
            let pair = try await app.login(username: "alice", password: "alice-password-123")

            for path in ["api/v1/admin/users", "api/v1/admin/stats"] {
                try await app.testing().test(
                    .GET, path,
                    headers: bearer(pair.accessToken),
                    afterResponse: { res async throws in
                        #expect(res.status == .forbidden)
                        let err = try res.content.decode(TestError.self)
                        #expect(err.error == true)
                        #expect(err.code == "forbidden")
                        #expect(!err.message.isEmpty)
                    }
                )
            }
        }
    }

    @Test("unauthenticated requests to /admin/* are rejected with 401")
    func unauthenticatedRejected() async throws {
        try await withTestApp { app in
            try await app.testing().test(.GET, "api/v1/admin/users", afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
                #expect(try res.content.decode(TestError.self).error == true)
            })
        }
    }

    // MARK: - List & get

    @Test("admin lists all users")
    func listUsers() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)
            try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeUser(username: "bob", password: "bob-password-1234")

            try await app.testing().test(.GET, "api/v1/admin/users", headers: headers, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let users = try res.content.decode([UserResponse].self)
                let names = Set(users.map(\.username))
                #expect(names == ["root", "alice", "bob"])
            })
        }
    }

    @Test("get single user, and 404 for unknown id")
    func getUser() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")

            try await app.testing().test(
                .GET, "api/v1/admin/users/\(try alice.requireID())",
                headers: headers,
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    #expect(try res.content.decode(UserResponse.self).username == "alice")
                }
            )

            try await app.testing().test(
                .GET, "api/v1/admin/users/\(UUID())",
                headers: headers,
                afterResponse: { res async throws in
                    #expect(res.status == .notFound)
                    #expect(try res.content.decode(TestError.self).code == "not_found")
                }
            )
        }
    }

    // MARK: - Create

    @Test("create user returns 201 and the new account can log in")
    func createUser() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)

            try await app.testing().test(
                .POST, "api/v1/admin/users",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(CreateUserInput(username: "Alice", password: "alice-password-123", role: .user))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .created)
                    let user = try res.content.decode(UserResponse.self)
                    #expect(user.username == "alice") // lowercased
                    #expect(user.role == .user)
                    #expect(user.isActive == true)
                    #expect(user.bookmarkCount == 0)
                }
            )

            // The created account works.
            _ = try await app.login(username: "alice", password: "alice-password-123")
        }
    }

    @Test("create user defaults role to user when omitted")
    func createUserDefaultRole() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)
            try await app.testing().test(
                .POST, "api/v1/admin/users",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(CreateUserInput(username: "carol", password: "carol-password-123", role: nil))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .created)
                    #expect(try res.content.decode(UserResponse.self).role == .user)
                }
            )
        }
    }

    @Test("duplicate username returns 409 username_taken")
    func duplicateUsername() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)
            try await app.makeUser(username: "alice", password: "alice-password-123")

            try await app.testing().test(
                .POST, "api/v1/admin/users",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(CreateUserInput(username: "alice", password: "another-password-123", role: .user))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .conflict)
                    #expect(try res.content.decode(TestError.self).code == "username_taken")
                }
            )
        }
    }

    @Test("create user with a too-short password fails validation (422)")
    func createUserShortPassword() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)
            try await app.testing().test(
                .POST, "api/v1/admin/users",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(CreateUserInput(username: "dave", password: "short", role: .user))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unprocessableEntity)
                    #expect(try res.content.decode(TestError.self).code == "validation_failed")
                }
            )
        }
    }

    // MARK: - Suspend / unsuspend

    @Test("suspending a user sets isActive=false and invalidates their refresh tokens")
    func suspendUser() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            let aliceTokens = try await app.login(username: "alice", password: "alice-password-123")

            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(try alice.requireID())",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(UpdateUserInput(isActive: false, password: nil))
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    #expect(try res.content.decode(UserResponse.self).isActive == false)
                }
            )

            // Their existing refresh token is gone.
            try await app.testing().test(
                .POST, "api/v1/auth/refresh",
                beforeRequest: { req in try req.content.encode(RefreshRequest(refreshToken: aliceTokens.refreshToken)) },
                afterResponse: { res async throws in #expect(res.status == .unauthorized) }
            )

            // They can no longer log in.
            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in try req.content.encode(LoginRequest(username: "alice", password: "alice-password-123")) },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    #expect(try res.content.decode(TestError.self).code == "account_suspended")
                }
            )
        }
    }

    @Test("unsuspending a user restores login")
    func unsuspendUser() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123", isActive: false)
            let id = try alice.requireID()

            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(id)",
                headers: headers,
                beforeRequest: { req in try req.content.encode(UpdateUserInput(isActive: true, password: nil)) },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    #expect(try res.content.decode(UserResponse.self).isActive == true)
                }
            )

            _ = try await app.login(username: "alice", password: "alice-password-123")
        }
    }

    // MARK: - Reset password

    @Test("resetting a password: old fails, new works")
    func resetPassword() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")

            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(try alice.requireID())",
                headers: headers,
                beforeRequest: { req in try req.content.encode(UpdateUserInput(isActive: nil, password: "brand-new-password-456")) },
                afterResponse: { res async throws in #expect(res.status == .ok) }
            )

            try await app.testing().test(
                .POST, "api/v1/auth/login",
                beforeRequest: { req in try req.content.encode(LoginRequest(username: "alice", password: "alice-password-123")) },
                afterResponse: { res async throws in #expect(res.status == .unauthorized) }
            )

            _ = try await app.login(username: "alice", password: "brand-new-password-456")
        }
    }

    @Test("resetting to a too-short password fails validation (422)")
    func resetPasswordTooShort() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.testing().test(
                .PUT, "api/v1/admin/users/\(try alice.requireID())",
                headers: headers,
                beforeRequest: { req in try req.content.encode(UpdateUserInput(isActive: nil, password: "short")) },
                afterResponse: { res async throws in
                    #expect(res.status == .unprocessableEntity)
                    #expect(try res.content.decode(TestError.self).code == "validation_failed")
                }
            )
        }
    }

    // MARK: - Hard delete

    @Test("hard delete removes the user and cascades bookmarks, refresh tokens, recovery codes")
    func hardDelete() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            let aliceID = try alice.requireID()

            // Give Alice data across all three child tables.
            try await app.makeBookmark(for: alice, url: "https://a.com")
            try await app.makeBookmark(for: alice, url: "https://b.com")
            _ = try await app.login(username: "alice", password: "alice-password-123") // refresh token
            try await RecoveryCode(userID: aliceID, codeHash: "hash").save(on: app.db)

            try await app.testing().test(
                .DELETE, "api/v1/admin/users/\(aliceID)",
                headers: headers,
                afterResponse: { res async throws in #expect(res.status == .noContent) }
            )

            // User gone.
            #expect(try await User.find(aliceID, on: app.db) == nil)
            // All owned data gone.
            let bookmarks = try await Bookmark.query(on: app.db).filter(\.$user.$id == aliceID).count()
            let tokens = try await RefreshToken.query(on: app.db).filter(\.$user.$id == aliceID).count()
            let codes = try await RecoveryCode.query(on: app.db).filter(\.$user.$id == aliceID).count()
            #expect(bookmarks == 0)
            #expect(tokens == 0)
            #expect(codes == 0)
        }
    }

    @Test("delete unknown user returns 404")
    func deleteUnknown() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)
            try await app.testing().test(
                .DELETE, "api/v1/admin/users/\(UUID())",
                headers: headers,
                afterResponse: { res async throws in #expect(res.status == .notFound) }
            )
        }
    }

    // MARK: - Stats

    @Test("stats reports totals and per-user bookmark counts")
    func stats() async throws {
        try await withTestApp { app in
            let headers = try await adminHeaders(app)
            let alice = try await app.makeUser(username: "alice", password: "alice-password-123")
            let bob = try await app.makeUser(username: "bob", password: "bob-password-1234")

            try await app.makeBookmark(for: alice, url: "https://a1.com")
            try await app.makeBookmark(for: alice, url: "https://a2.com")
            try await app.makeBookmark(for: alice, url: "https://a3.com")
            try await app.makeBookmark(for: bob, url: "https://b1.com")

            try await app.testing().test(.GET, "api/v1/admin/stats", headers: headers, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let stats = try res.content.decode(AdminStatsResponse.self)
                #expect(stats.totalUsers == 3) // root, alice, bob
                #expect(stats.totalBookmarks == 4)
                let byName = Dictionary(uniqueKeysWithValues: stats.users.map { ($0.username, $0) })
                #expect(byName["alice"]?.bookmarkCount == 3)
                #expect(byName["bob"]?.bookmarkCount == 1)
                #expect(byName["root"]?.bookmarkCount == 0)
                #expect(byName["alice"]?.isActive == true)
            })
        }
    }
}
