// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import JWT
import Vapor

/// Authenticates requests carrying a `Bearer` access-token JWT.
///
/// On a present-but-bad token it throws the appropriate `APIError`; a missing token simply
/// leaves the request unauthenticated, so `User.guardMiddleware` produces the 401.
struct AccessTokenAuthenticator: AsyncBearerAuthenticator {

    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        let payload: AccessTokenPayload
        do {
            payload = try request.jwt.verify(bearer.token, as: AccessTokenPayload.self)
        } catch let error as JWTError {
            if case let .claimVerificationFailure(name, _) = error, name == "exp" {
                throw APIError.tokenExpired
            }
            throw APIError.tokenInvalid
        } catch {
            throw APIError.tokenInvalid
        }

        guard let userID = payload.userID,
              let user = try await User.find(userID, on: request.db)
        else {
            throw APIError.tokenInvalid
        }
        guard user.isActive else {
            throw APIError.accountSuspended
        }

        request.auth.login(user)
    }
}
