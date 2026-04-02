import Fluent
import Vapor

/// Server-rendered web admin dashboard (PRD §11). Session-cookie auth, mounted at `/admin`,
/// entirely separate from the JSON `/api/v1/*` endpoints. Enforces the same business rules as
/// the admin API: accounts are always created as `user`, self-deletion is blocked, and a
/// password reset (or suspension) invalidates the target's refresh tokens.
struct AdminWebController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // Public — login / logout.
        routes.get("login", use: loginPage)
        routes.post("login", use: login)
        routes.post("logout", use: logout)

        // Everything else requires an authenticated admin session.
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

    // GET /admin/login
    func loginPage(req: Request) async throws -> View {
        try await req.view.render("login", LoginPageContext(title: "Sign in", error: nil))
    }

    // POST /admin/login
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
            // Keep timing roughly constant for unknown usernames.
            _ = try? await req.password.async.verify(form.password, created: Self.dummyHash)
            return try await failure()
        }
        guard try await req.password.async.verify(form.password, created: user.passwordHash),
              user.isActive,
              user.role == .admin
        else {
            return try await failure()
        }

        // If the admin has 2FA enabled, the single login form must carry a valid TOTP code.
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

    // POST /admin/logout
    func logout(req: Request) async throws -> Response {
        req.session.destroy()
        return req.redirect(to: "/admin/login")
    }

    // MARK: - Dashboard

    // GET /admin
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

    // GET /admin/users
    func userList(req: Request) async throws -> View {
        let admin = try req.auth.require(User.self)
        let users = try await User.query(on: req.db).sort(\.$username).all()
        return try await req.view.render("users", UsersContext(
            title: "Users",
            adminUsername: admin.username,
            users: try users.map { try $0.asRow() }
        ))
    }

    // GET /admin/users/new
    func newUserForm(req: Request) async throws -> View {
        let admin = try req.auth.require(User.self)
        return try await req.view.render("user-new", NewUserContext(
            title: "New user", adminUsername: admin.username, error: nil, username: nil
        ))
    }

    // POST /admin/users/new
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

        // Role is never accepted here — dashboard-created accounts are always regular users.
        let user = User(
            username: username,
            passwordHash: try await req.password.async.hash(form.password),
            role: .user
        )
        do {
            try await user.save(on: req.db)
        } catch {
            return try await formError("That username is already taken.")
        }

        return req.redirect(to: "/admin/users/\(try user.requireID())?ok=created")
    }

    // MARK: - User detail & actions

    // GET /admin/users/:id
    func userDetail(req: Request) async throws -> Response {
        guard let user = try await loadUser(req) else {
            return req.redirect(to: "/admin/users")
        }
        let message = Self.message(for: req.query[String.self, at: "ok"])
        return try await renderDetail(req, user: user, error: nil, message: message)
    }

    // POST /admin/users/:id/suspend
    func suspend(req: Request) async throws -> Response {
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }
        user.isActive = false
        try await user.save(on: req.db)
        // Suspension immediately invalidates all refresh tokens (PRD §8.6).
        try await user.$refreshTokens.query(on: req.db).delete()
        return req.redirect(to: "/admin/users/\(try user.requireID())?ok=suspended")
    }

    // POST /admin/users/:id/unsuspend
    func unsuspend(req: Request) async throws -> Response {
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }
        user.isActive = true
        try await user.save(on: req.db)
        return req.redirect(to: "/admin/users/\(try user.requireID())?ok=unsuspended")
    }

    // POST /admin/users/:id/reset-password
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
        // A password reset forces re-authentication everywhere (PRD §8.6).
        try await user.$refreshTokens.query(on: req.db).delete()
        return req.redirect(to: "/admin/users/\(try user.requireID())?ok=password-reset")
    }

    // POST /admin/users/:id/reset-totp — disable the user's 2FA. Self-reset is allowed.
    func resetTOTP(req: Request) async throws -> Response {
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }

        try await user.$recoveryCodes.query(on: req.db).delete()
        user.totpSecret = nil
        user.isTOTPEnabled = false
        try await user.save(on: req.db)
        // Their session security level changed, so force re-login everywhere.
        try await user.$refreshTokens.query(on: req.db).delete()

        return req.redirect(to: "/admin/users/\(try user.requireID())?ok=totp_reset")
    }

    // POST /admin/users/:id/delete
    func deleteUser(req: Request) async throws -> Response {
        let admin = try req.auth.require(User.self)
        guard let user = try await loadUser(req) else { return req.redirect(to: "/admin/users") }

        // An admin cannot delete their own account (same rule as the API; returns 400).
        if try user.requireID() == admin.requireID() {
            return try await renderDetail(
                req, user: user, error: "You cannot delete your own account.", message: nil,
                status: .badRequest
            )
        }

        // Hard delete, cascading all owned data (PRD §8.6).
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
        let context = UserDetailContext(
            title: user.username,
            adminUsername: admin.username,
            user: try user.asRow(),
            createdAt: Self.dateFormatter.string(from: user.createdAt ?? Date()),
            isSelf: isSelf,
            error: error,
            message: message
        )
        return try await render(req, "user-detail", context, status: status)
    }

    /// Render a Leaf template into an HTML `Response` with an explicit status code.
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

    private static func message(for ok: String?) -> String? {
        switch ok {
        case "created": return "User created."
        case "suspended": return "User suspended; their sessions were revoked."
        case "unsuspended": return "User reactivated."
        case "password-reset": return "Password reset; the user's sessions were revoked."
        case "totp_reset": return "Two-factor authentication reset; the user must set it up again and was signed out."
        default: return nil
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// A valid bcrypt hash used to equalise timing for unknown usernames.
    private static let dummyHash =
        "$2b$12$C6UzMDM.H6dfI/f/IKcEeO2x0jXJ8nKqK8h0V2vQ1nC3l6mFqKQ4u"
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
