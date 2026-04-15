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
