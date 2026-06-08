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

import Foundation
import MicroClient
import StashKit

// MARK: - AuthorizedClient

/// A `StashClient` wrapper that reactively recovers from a rejected access token.
///
/// `CLIRuntime` already refreshes a token that is expiring within the next minute before building the
/// client. This handles the residual case: a token the CLI believed valid that the server rejects
/// anyway (clock skew, or a backend `JWT_SECRET` rotation). On a retryable authentication failure it
/// forces one refresh and replays the request exactly once — safe because a `401` is rejected by the
/// auth middleware before the route runs, so the request carries no side effects. The CLI keeps its
/// own copy of this type (mirroring the app's) because StashKit is deliberately free of refresh logic.
struct AuthorizedClient {

    // MARK: Properties

    private let client: StashClient
    private let forceRefresh: () async throws -> Void

    // MARK: Lifecycle

    init(
        client: StashClient,
        forceRefresh: @escaping () async throws -> Void
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

// MARK: - TokenHolder

/// A thread-safe mutable access-token box. The CLI builds its `StashClient` with a token provider that
/// reads this, so a forced refresh can swap in the rotated token without rebuilding the client.
final class TokenHolder: @unchecked Sendable {

    // MARK: Properties

    private let lock = NSLock()
    private var token: String?

    // MARK: Computed Properties

    var current: String? {
        lock.withLock { token }
    }

    // MARK: Lifecycle

    init(_ token: String?) {
        self.token = token
    }

    // MARK: Functions

    func update(_ token: String?) {
        lock.withLock { self.token = token }
    }
}

// MARK: - StashAPIError + retry

extension StashAPIError {

    /// Whether the failure is an access-token rejection worth retrying after a forced refresh. A dead
    /// *refresh* token surfaces the same cases on the refresh call itself and is handled there by
    /// clearing the stored tokens — this only governs a single replay of the original request.
    var isRetryableAuthFailure: Bool {
        switch self {
        case .tokenExpired, .tokenInvalid:
            true
        default:
            false
        }
    }
}
