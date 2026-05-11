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
import StashKit

/// Builds configured `StashClient` instances and performs CLI-side token refresh.
///
/// Before an authenticated command runs, the stored access token is checked for imminent expiry
/// (within 60 seconds, via the JWT `exp` claim). If it is expiring and a refresh token exists, a
/// refresh is attempted and the new token pair persisted. A failed refresh clears the stored tokens
/// and surfaces a "session expired" message so the user re-authenticates.
enum CLIRuntime {

    // MARK: Static Properties

    private static let refreshThreshold: TimeInterval = 60

    // MARK: Static Functions

    static func requireBaseURL(_ config: CLIConfig) throws -> URL {
        guard let baseURL = config.baseURL else {
            throw CLIError("No server URL configured. Run: stash config set-url <url>")
        }

        return baseURL
    }

    /// A client for unauthenticated endpoints (login, refresh). Supplies no access token.
    static func unauthenticatedClient(baseURL: URL) -> StashClient {
        StashClient(baseURL: baseURL) { nil }
    }

    /// Prepares a client for authenticated commands, refreshing the access token if it is expiring.
    static func authenticatedClient(store: ConfigStore) async throws -> StashClient {
        var config = try store.load()
        let baseURL = try requireBaseURL(config)

        guard let accessToken = config.accessToken else {
            throw CLIError("Not logged in. Run: stash login")
        }

        var token = accessToken
        if config.refreshToken != nil, JWTDecoder.isExpiring(token, within: refreshThreshold) {
            token = try await refresh(store: store, config: &config, baseURL: baseURL)
        }

        let activeToken = token

        return StashClient(baseURL: baseURL) { activeToken }
    }

    private static func refresh(
        store: ConfigStore,
        config: inout CLIConfig,
        baseURL: URL
    ) async throws -> String {
        guard let refreshToken = config.refreshToken else {
            throw sessionExpired(store: store, config: config)
        }

        let client = unauthenticatedClient(baseURL: baseURL)
        do {
            let pair = try await client
                .run(AuthRequestFactory.makeRefreshRequest(refreshToken: refreshToken))
                .value
            config.accessToken = pair.accessToken
            config.refreshToken = pair.refreshToken
            try store.save(config)

            return pair.accessToken
        } catch {
            throw sessionExpired(store: store, config: config)
        }
    }

    private static func sessionExpired(store: ConfigStore, config: CLIConfig) -> CLIError {
        var cleared = config
        cleared.accessToken = nil
        cleared.refreshToken = nil
        try? store.save(cleared)

        return CLIError("Session expired — please run stash login")
    }
}
