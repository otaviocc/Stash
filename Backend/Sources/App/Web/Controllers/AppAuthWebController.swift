// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Vapor

/// Login and logout for the user-facing web frontend (`/app`). Public — it carries the session
/// cookie but no session guard; a successful sign-in writes the user ID into the session that
/// `UserSessionMiddleware` later reads to protect the rest of `/app`.
struct AppAuthWebController: RouteCollection {

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
            _ = try? await req.password.async.verify(form.password, created: User.dummyPasswordHash)
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
