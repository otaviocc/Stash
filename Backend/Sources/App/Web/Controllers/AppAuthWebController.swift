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

/// Login and logout for the user-facing web frontend (`/app`). Public — it carries the session
/// cookie but no session guard; a successful sign-in writes the user ID into the session that
/// `UserSessionMiddleware` later reads to protect the rest of `/app`.
struct AppAuthWebController: RouteCollection {

    // MARK: Static Properties

    private static let dummyHash =
        "$2b$12$C6UzMDM.H6dfI/f/IKcEeO2x0jXJ8nKqK8h0V2vQ1nC3l6mFqKQ4u"

    // MARK: Functions

    func boot(routes: RoutesBuilder) throws {
        routes.get("login", use: loginPage)
        routes.post("login", use: login)
        routes.post("logout", use: logout)
    }

    func loginPage(req: Request) async throws -> View {
        try await req.view.render("app-login", LoginPageContext(title: "Sign in", error: nil, chrome: req.siteChrome()))
    }

    func login(req: Request) async throws -> Response {
        let form = try req.content.decode(LoginForm.self)
        let username = form.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func failure() async throws -> Response {
            try await req.renderHTML(
                "app-login",
                LoginPageContext(
                    title: "Sign in",
                    error: "Invalid username, password, or 2FA code.",
                    chrome: req.siteChrome()
                ),
                status: .unauthorized
            )
        }

        guard let user = try await User.query(on: req.db).filter(\.$username == username).first() else {
            _ = try? await req.password.async.verify(form.password, created: Self.dummyHash)
            return try await failure()
        }
        guard try await req.password.async.verify(form.password, created: user.passwordHash),
              user.isActive
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

        req.session.data[UserSessionMiddleware.sessionKey] = try user.requireID().uuidString
        return req.redirect(to: "/app")
    }

    func logout(req: Request) async throws -> Response {
        req.session.destroy()
        return req.redirect(to: "/app/login")
    }
}
