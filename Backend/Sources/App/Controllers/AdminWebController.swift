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
import Vapor

// MARK: - AdminWebController

/// Server-rendered web admin dashboard (PRD §11). Session-cookie auth, mounted at `/admin`,
/// entirely separate from the JSON `/api/v1/*` endpoints. Enforces the same business rules as
/// the admin API: accounts are always created as `user`, self-deletion is blocked, and a
/// password reset (or suspension) invalidates the target's refresh tokens.
struct AdminWebController: RouteCollection {

    // MARK: Static Properties

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dummyHash =
        "$2b$12$C6UzMDM.H6dfI/f/IKcEeO2x0jXJ8nKqK8h0V2vQ1nC3l6mFqKQ4u"

    // MARK: Static Functions

    private static func message(for ok: String?) -> String? {
        switch ok {
        case "created": "User created."
        case "suspended": "User suspended; their sessions were revoked."
        case "unsuspended": "User reactivated."
        case "password-reset": "Password reset; the user's sessions were revoked."
        case "totp_reset": "Two-factor authentication reset; the user must set it up again and was signed out."
        default: nil
        }
    }

    // MARK: Functions

    func boot(routes: RoutesBuilder) throws {
        routes.get("login", use: loginPage)
        routes.post("login", use: login)
        routes.post("logout", use: logout)

        let protected = routes.grouped(AdminSessionMiddleware())
        protected.get(use: dashboard)
        protected.get("users", use: userList)
        protected.get("users", "new", use: newUserForm)
        protected.post("users", "new", use: createUser)
        protected.get("users", ":userID", use: userDetail)
        protected.post("users", ":userID", "suspend", use: suspend)
        protected.post("users", ":userID", "unsuspend", use: unsuspend)
        protected.post("users", ":userID", "reset-password", use: resetPassword)
        protected.post("users", ":userID", "reset-totp", use: resetTOTP)
        protected.post("users", ":userID", "delete", use: deleteUser)
    }

    // MARK: - Login / logout

    func loginPage(req: Request) async throws -> View {
        try await req.view.render("login", LoginPageContext(title: "Sign in", error: nil))
    }

    func login(req: Request) async throws -> Response {
        let form = try req.content.decode(LoginForm.self)
        let username = form.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func failure() async throws -> Response {
            try await render(
                req, "login",
                LoginPageContext(title: "Sign in", error: "Invalid username, password, or 2FA code."),
                status: .unauthorized
            )
        }

        guard let user = try await User.query(on: req.db).filter(\.$username == username).first() else {
            _ = try? await req.password.async.verify(form.password, created: Self.dummyHash)
            return try await failure()
        }
        guard try await req.password.async.verify(form.password, created: user.passwordHash),
              user.isActive,
              user.role == .admin
        else {
            return try await failure()
        }

        if user.isTOTPEnabled {
            guard let code = form.totpCode?.nonEmpty,
                  let secret = user.totpSecret,
                  let secretData = Base32.decode(secret),
                  TOTP(secret: secretData).validate(code)
            else {
                return try await failure()
            }
        }

        req.session.data[AdminSessionMiddleware.sessionKey] = try user.requireID().uuidString
        return req.redirect(to: "/admin")
    }

    func logout(req: Request) async throws -> Response {
        req.session.destroy()
        return req.redirect(to: "/admin/login")
    }

    // MARK: - Dashboard

    func dashboard(req: Request) async throws -> View {
        let admin = try req.auth.require(User.self)
        let users = try await User.query(on: req.db).sort(\.$username).all()
        let rows = try users.map { try $0.asRow() }
        let totalBookmarks = rows.reduce(0) { $0 + $1.bookmarkCount }

        return try await req.view.render("dashboard", DashboardContext(
            title: "Dashboard",
            adminUsername: admin.username,
            totalUsers: users.count,
            totalBookmarks: totalBookmarks,
            users: rows
        ))
    }

    // MARK: - User list & create

    func userList(req: Request) async throws -> View {
        let admin = try req.auth.require(User.self)
        let users = try await User.query(on: req.db).sort(\.$username).all()
        return try await req.view.render("users", UsersContext(
            title: "Users",
            adminUsername: admin.username,
            users: users.map { try $0.asRow() }
        ))
    }

    func newUserForm(req: Request) async throws -> View {
        let admin = try req.auth.require(User.self)
        return try await req.view.render("user-new", NewUserContext(
            title: "New user", adminUsername: admin.username, error: nil, username: nil
        ))
    }

    func createUser(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let form = try req.content.decode(CreateUserForm.self)
        let username = form.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func formError(_ message: String) async throws -> Response {
            try await render(
                req, "user-new",
                NewUserContext(title: "New user", adminUsername: admin.username, error: message, username: username),
                status: .badRequest
            )
        }

        guard !username.isEmpty else { return try await formError("Username must not be empty.") }
        guard form.password.count >= 12 else {
            return try await formError("Password must be at least 12 characters.")
        }

        if try await User.query(on: req.db).filter(\.$username == username).first() != nil {
            return try await formError("That username is already taken.")
        }

        let user = try await User(
            username: username,
            passwordHash: req.password.async.hash(form.password),
            role: .user
        )
        do {
            try await user.save(on: req.db)
        } catch {
            return try await formError("That username is already taken.")
        }

        return try req.redirect(to: "/admin/users/\(user.requireID())?ok=created")
    }

    // MARK: - User detail & actions

    func userDetail(req: Request) async throws -> Response {
        guard let user = try await loadUser(req) else {
            return req.redirect(to: "/admin/users")
        }

        let message = Self.message(for: req.query[String.self, at: "ok"])
        return try await renderDetail(req, user: user, error: nil, message: message)
    }

    func suspend(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }

        if try user.requireID() == admin.requireID() {
            return try await renderDetail(
                req, user: user, error: "You cannot suspend your own account.", message: nil,
                status: .badRequest
            )
        }

        user.isActive = false
        try await user.save(on: req.db)
        try await user.$refreshTokens.query(on: req.db).delete()
        return try req.redirect(to: "/admin/users/\(user.requireID())?ok=suspended")
    }

    func unsuspend(req: Request) async throws -> Response {
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }

        user.isActive = true
        try await user.save(on: req.db)
        return try req.redirect(to: "/admin/users/\(user.requireID())?ok=unsuspended")
    }

    func resetPassword(req: Request) async throws -> Response {
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }

        let form = try req.content.decode(ResetPasswordForm.self)

        guard form.password.count >= 12 else {
            return try await renderDetail(
                req, user: user, error: "Password must be at least 12 characters.", message: nil,
                status: .badRequest
            )
        }

        user.passwordHash = try await req.password.async.hash(form.password)
        try await user.save(on: req.db)
        try await user.$refreshTokens.query(on: req.db).delete()
        return try req.redirect(to: "/admin/users/\(user.requireID())?ok=password-reset")
    }

    func resetTOTP(req: Request) async throws -> Response {
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }

        try await user.$recoveryCodes.query(on: req.db).delete()
        user.totpSecret = nil
        user.isTOTPEnabled = false
        try await user.save(on: req.db)
        try await user.$refreshTokens.query(on: req.db).delete()

        return try req.redirect(to: "/admin/users/\(user.requireID())?ok=totp_reset")
    }

    func deleteUser(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }

        if try user.requireID() == admin.requireID() {
            return try await renderDetail(
                req, user: user, error: "You cannot delete your own account.", message: nil,
                status: .badRequest
            )
        }

        try await user.$bookmarks.query(on: req.db).delete()
        try await user.$refreshTokens.query(on: req.db).delete()
        try await user.$recoveryCodes.query(on: req.db).delete()
        try await user.delete(on: req.db)

        return req.redirect(to: "/admin/users")
    }

    // MARK: - Helpers

    private func loadUser(_ req: Request) async throws -> User? {
        guard let id = req.parameters.get("userID", as: UUID.self) else { return nil }

        return try await User.find(id, on: req.db)
    }

    private func renderDetail(
        _ req: Request,
        user: User,
        error: String?,
        message: String?,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        let admin = try req.auth.require(User.self)
        let isSelf = try user.requireID() == admin.requireID()
        let context = try UserDetailContext(
            title: user.username,
            adminUsername: admin.username,
            user: user.asRow(),
            createdAt: Self.dateFormatter.string(from: user.createdAt ?? Date()),
            isSelf: isSelf,
            error: error,
            message: message
        )
        return try await render(req, "user-detail", context, status: status)
    }

    private func render(
        _ req: Request,
        _ template: String,
        _ context: some Encodable,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        let view: View = try await req.view.render(template, context)
        let response = Response(status: status)
        response.headers.contentType = .html
        response.body = .init(buffer: view.data)
        return response
    }
}

private extension User {

    func asRow() throws -> UserRowContext {
        try UserRowContext(
            id: requireID().uuidString,
            username: username,
            role: role.rawValue,
            isActive: isActive,
            bookmarkCount: bookmarkCount,
            isTOTPEnabled: isTOTPEnabled
        )
    }
}
