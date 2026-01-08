import Fluent
import Testing
import Vapor
import VaporTesting

@testable import App

/// Boot a fully-configured app against an in-memory SQLite database, run the test, tear down.
///
/// Named distinctly from VaporTesting's `withApp` on purpose: a test body that is a single
/// expression (e.g. just a `.test(...)` call, which returns a value) would otherwise infer a
/// non-`Void` return type and silently resolve to VaporTesting's generic `withApp`, skipping
/// our explicit `asyncBoot()` and leaving the app's responder unbooted (every route 404s).
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
    /// Insert a user directly (bypassing the admin-create flow, which is a later milestone).
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
        try await user.save(on: self.db)
        return user
    }
}

extension Application {
    /// Insert a bookmark directly (bypassing metadata fetch / the create endpoint).
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
        try await bookmark.save(on: self.db)
        return bookmark
    }
}

/// Authorization header for a bearer access token.
func bearer(_ token: String) -> HTTPHeaders {
    ["Authorization": "Bearer \(token)"]
}

extension Application {
    /// Perform a full password login and return the issued token pair (2FA must be disabled).
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

    /// Perform a password login expecting a 2FA challenge; returns the temp token.
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

/// Decode an error envelope from a test response body.
struct TestError: Content {
    let error: Bool
    let code: String
    let message: String
}

/// Decode the duplicate-URL error envelope (includes `existingID`).
struct TestDuplicateError: Content {
    let error: Bool
    let code: String
    let message: String
    let existingID: UUID
}
