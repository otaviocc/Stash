import Fluent
import Vapor

/// Protects the user-facing web frontend (PRD §5/§11). Mirrors `AdminSessionMiddleware` but
/// admits any active account regardless of role. Reads the user ID from the `stash_session`
/// cookie, reloads the account, and requires it to still be active (suspended accounts are
/// rejected). Any failure clears the session and redirects to the login page.
///
/// On success the user is placed in `req.auth`, so handlers can use `req.auth.require(User.self)`.
struct UserSessionMiddleware: AsyncMiddleware {
    /// Session key holding the logged-in user's ID. Distinct from the admin dashboard's key.
    static let sessionKey = "appUserID"

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let idString = request.session.data[Self.sessionKey],
              let id = UUID(uuidString: idString),
              let user = try await User.find(id, on: request.db),
              user.isActive
        else {
            request.session.destroy()
            return request.redirect(to: "/app/login")
        }

        request.auth.login(user)
        return try await next.respond(to: request)
    }
}
