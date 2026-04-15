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

/// Protects the web admin dashboard (PRD §11). Reads the admin's user ID from the session
/// cookie, loads the account, and requires it to still be an active admin. Any failure clears
/// the session and redirects to the login page rather than returning a JSON error.
///
/// On success the user is placed in `req.auth`, so handlers can use `req.auth.require(User.self)`.
struct AdminSessionMiddleware: AsyncMiddleware {

    // MARK: Static Properties

    /// Session key holding the logged-in admin's user ID.
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
