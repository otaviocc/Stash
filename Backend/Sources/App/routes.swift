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

func routes(_ app: Application) throws {
    app.get("health") { _ in HealthResponse(status: "ok") }

    let api = app.grouped("api", "v1")

    try api.register(collection: AuthController())

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
