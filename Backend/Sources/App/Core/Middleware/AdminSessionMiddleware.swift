// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Vapor

/// Protects the web admin dashboard (Docs/product-web.md §12). Reads the admin's user ID from the session
/// cookie, loads the account, and requires it to still be an active admin. Any failure clears
/// the session and redirects to the login page rather than returning a JSON error.
///
/// On success the user is placed in `req.auth`, so handlers can use `req.auth.require(User.self)`.
struct AdminSessionMiddleware: AsyncMiddleware {

    // MARK: Static Properties

    static let sessionKey = "adminUserID"

    // MARK: Functions

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let idString = request.session.data[Self.sessionKey],
              let id = UUID(uuidString: idString),
              let user = try await User.find(id, on: request.db),
              user.role == .admin,
              user.isActive
        else {
            request.session.destroy()
            return request.redirect(to: "/admin/login")
        }

        request.auth.login(user)
        return try await next.respond(to: request)
    }
}
