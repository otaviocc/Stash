// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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
    ///
    /// The returned `AuthorizedClient` also recovers reactively: if the server rejects an
    /// apparently-valid token, it forces one refresh — swapping the rotated token into the holder the
    /// client reads from — and replays the request once.
    static func authenticatedClient(store: ConfigStore) async throws -> AuthorizedClient {
        var config = try store.load()
        let baseURL = try requireBaseURL(config)

        guard let accessToken = config.accessToken else {
            throw CLIError("Not logged in. Run: stash login")
        }

        var token = accessToken
        if config.refreshToken != nil, JWTDecoder.isExpiring(token, within: refreshThreshold) {
            token = try await refresh(store: store, config: &config, baseURL: baseURL)
        }

        let holder = TokenHolder(token)
        let client = StashClient(baseURL: baseURL) { holder.current }

        return AuthorizedClient(client: client) {
            let refreshed = try await forceRefresh(store: store, baseURL: baseURL)
            holder.update(refreshed)
        }
    }

    private static func forceRefresh(store: ConfigStore, baseURL: URL) async throws -> String {
        var config = try store.load()

        return try await refresh(store: store, config: &config, baseURL: baseURL)
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
