// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import MicroClient
import StashKit

// MARK: - AuthorizedClient

/// A `StashClient` wrapper that reactively recovers from a rejected access token.
///
/// The proactive `refreshIfNeeded()` covers the common case — a token expiring within the next
/// minute is rotated before the request. This handles the residual case: a token the client believed
/// valid that the server rejects anyway (clock skew, a backend `JWT_SECRET` rotation, or a refresh the
/// other process performed first). On a retryable authentication failure it forces one refresh and
/// replays the request exactly once. Replay is safe because the auth middleware rejects an
/// unauthenticated request *before* the route runs, so a `401` carries no side effects — even for a
/// `POST`/`PUT`/`DELETE`. The underlying `StashClient` reads its token from the `TokenManager` at send
/// time, so the same instance picks up the rotated token without being rebuilt.
struct AuthorizedClient {

    // MARK: Properties

    private let client: StashClient
    private let forceRefresh: @Sendable () async throws -> Void

    // MARK: Lifecycle

    init(
        client: StashClient,
        forceRefresh: @escaping @Sendable () async throws -> Void
    ) {
        self.client = client
        self.forceRefresh = forceRefresh
    }

    // MARK: Functions

    func run<ResponseModel: Decodable & Sendable>(
        _ request: NetworkRequest<some Encodable & Sendable, ResponseModel>
    ) async throws -> NetworkResponse<ResponseModel> {
        do {
            return try await client.run(request)
        } catch let error as StashAPIError where error.isRetryableAuthFailure {
            try await forceRefresh()

            return try await client.run(request)
        }
    }
}

// MARK: - StashAPIError + retry

extension StashAPIError {

    /// Whether the failure is an access-token rejection worth retrying after a forced refresh. A dead
    /// *refresh* token surfaces the same cases on the refresh call itself and is handled there by
    /// clearing the session — this only governs a single replay of the original request.
    var isRetryableAuthFailure: Bool {
        switch self {
        case .tokenExpired, .tokenInvalid:
            true
        default:
            false
        }
    }
}
