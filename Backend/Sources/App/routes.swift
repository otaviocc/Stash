// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ in HealthResponse(status: "ok") }

    let api = app.grouped("api", "v1")

    try api.register(collection: AuthController())

    try api.register(collection: InstanceController())

    let favicons = FaviconController()
    api.get("favicons", ":domain", use: favicons.serve)

    let protected = api.grouped(
        AccessTokenAuthenticator(),
        User.guardMiddleware(throwing: APIError.tokenInvalid)
    )
    try protected.register(collection: UserController())
    try protected.register(collection: BookmarkController())
    try protected.register(collection: SmartViewController())
    try protected.register(collection: TagController())
    try protected.register(collection: MetadataController())
    protected.post("favicons", ":domain", "refresh", use: favicons.refresh)

    let admin = protected.grouped("admin").grouped(AdminMiddleware())
    try admin.register(collection: AdminController())

    let dashboard = app.grouped("admin").grouped(app.sessions.middleware)
    try dashboard.register(collection: AdminWebController())

    let appSessions = SessionsMiddleware(
        session: app.sessions.driver,
        configuration: SessionsConfiguration(cookieName: "stash_session") { sessionID in
            HTTPCookies.Value(
                string: sessionID.string,
                expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 7),
                maxAge: nil,
                domain: nil,
                path: "/app",
                isSecure: false,
                isHTTPOnly: true,
                sameSite: .lax
            )
        }
    )
    let frontend = app.grouped("app").grouped(appSessions)
    try frontend.register(collection: AppAuthWebController())

    let authed = frontend.grouped(UserSessionMiddleware())
    try authed.register(collection: BookmarkWebController())
    try authed.register(collection: SmartViewWebController())
    try authed.register(collection: TagWebController())
    try authed.register(collection: SettingsWebController())

    try app.register(collection: LandingController())
}
