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
    // Unversioned health check (PRD §17.3).
    app.get("health") { _ in HealthResponse(status: "ok") }

    // All API routes are prefixed /api/v1/ (PRD §17.3).
    let api = app.grouped("api", "v1")

    // Unauthenticated auth endpoints.
    try api.register(collection: AuthController())

    // Authenticated endpoints (any role).
    let protected = api.grouped(
        AccessTokenAuthenticator(),
        User.guardMiddleware(throwing: APIError.tokenInvalid)
    )
    try protected.register(collection: UserController())
    try protected.register(collection: BookmarkController())
    try protected.register(collection: TagController())
    try protected.register(collection: MetadataController())

    // Admin-only endpoints (PRD §9.6). Non-admins get 403 via AdminMiddleware.
    let admin = protected.grouped("admin").grouped(AdminMiddleware())
    try admin.register(collection: AdminController())

    // Web admin dashboard (PRD §11). Server-rendered Leaf pages at /admin, using cookie-based
    // session auth — entirely separate from the JWT API above. Unversioned (PRD §17.3).
    let dashboard = app.grouped("admin").grouped(app.sessions.middleware)
    try dashboard.register(collection: AdminWebController())

    // User-facing web frontend (PRD §5, P2). Server-rendered Leaf pages at /app, with its own
    // session cookie (`stash_session`) distinct from the admin dashboard's, sharing the same
    // in-memory session store. Separate from the JWT API and admin pages.
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
    try frontend.register(collection: AppWebController())
}
