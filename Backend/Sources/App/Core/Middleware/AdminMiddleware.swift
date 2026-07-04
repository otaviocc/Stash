// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

/// Restricts a route group to admin accounts. Runs after `AccessTokenAuthenticator` +
/// `guardMiddleware`, so the user is guaranteed to be authenticated; a non-admin gets a
/// 403 `forbidden` in the standard error envelope (PRD §9.6, §17.4).
struct AdminMiddleware: AsyncMiddleware {

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let user = try request.auth.require(User.self)
        guard user.role == .admin else {
            throw APIError.forbidden
        }

        return try await next.respond(to: request)
    }
}
