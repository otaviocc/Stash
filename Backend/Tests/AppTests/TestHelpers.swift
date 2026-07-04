// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Testing
import Vapor
import VaporTesting
@testable import App

func withTestApp(_ test: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    do {
        try await configure(app)
        try await app.asyncBoot()
        try await test(app)
    } catch {
        try await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}

extension Application {

    @discardableResult
    func makeUser(
        username: String = "otavio",
        password: String = "correct-horse-battery",
        role: UserRole = .user,
        isActive: Bool = true,
        isTOTPEnabled: Bool = false,
        totpSecret: String? = nil
    ) async throws -> User {
        let hash = try await self.password.async.hash(password)
        let user = User(
            username: username,
            passwordHash: hash,
            role: role,
            isActive: isActive,
            isTOTPEnabled: isTOTPEnabled,
            totpSecret: totpSecret
        )
        try await user.save(on: db)
        return user
    }
}

extension Application {

    @discardableResult
    func makeBookmark(
        for user: User,
        url: String,
        title: String = "Title",
        description: String? = nil,
        tags: [String] = [],
        isArchived: Bool = false
    ) async throws -> Bookmark {
        let bookmark = try Bookmark(
            userID: user.requireID(),
            url: url,
            title: title,
            description: description,
            tags: tags,
            isArchived: isArchived
        )
        try await bookmark.save(on: db)
        user.bookmarkCount += 1
        try await user.save(on: db)
        return bookmark
    }
}

func bearer(_ token: String) -> HTTPHeaders {
    ["Authorization": "Bearer \(token)"]
}

extension Application {

    func login(username: String, password: String) async throws -> TokenPair {
        var pair: TokenPair?
        try await testing().test(
            .POST, "api/v1/auth/login",
            beforeRequest: { req in
                try req.content.encode(LoginRequest(username: username, password: password))
            },
            afterResponse: { res async throws in
                pair = try res.content.decode(TokenPair.self)
            }
        )
        guard let pair else {
            throw Abort(.internalServerError, reason: "login did not return a token pair")
        }

        return pair
    }

    func loginForTempToken(username: String, password: String) async throws -> String {
        var token: String?
        try await testing().test(
            .POST, "api/v1/auth/login",
            beforeRequest: { req in
                try req.content.encode(LoginRequest(username: username, password: password))
            },
            afterResponse: { res async throws in
                token = try res.content.decode(TwoFactorRequired.self).tempToken
            }
        )
        guard let token else {
            throw Abort(.internalServerError, reason: "login did not return a temp token")
        }

        return token
    }
}

// MARK: - TestError

/// Decode an error envelope from a test response body.
struct TestError: Content {

    let error: Bool
    let code: String
    let message: String
}

// MARK: - TestDuplicateError

/// Decode the duplicate-URL error envelope (includes `existingID`).
struct TestDuplicateError: Content {

    let error: Bool
    let code: String
    let message: String
    let existingID: UUID
}
