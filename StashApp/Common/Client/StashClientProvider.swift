// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

/// Vends a `StashClient` configured for the currently saved server URL.
///
/// The server URL is read from the injected `UserDefaults` (the same key `AppSettings`
/// persists to), so the provider always reflects the latest configuration without holding a
/// reference to the observable settings, and so the Share Extension, a separate process, sees the
/// server the main app configured. The client is rebuilt only when the URL changes; its
/// `tokenProvider` reads the access token from the `TokenManager` at request time, so a silent
/// refresh that rewrites the token is picked up without rebuilding the client.
final class StashClientProvider: @unchecked Sendable {

    // MARK: Properties

    private let tokenManager: TokenManager
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cachedURLString: String?
    private var cachedClient: StashClient?

    // MARK: Lifecycle

    init(
        tokenManager: TokenManager,
        defaults: UserDefaults
    ) {
        self.tokenManager = tokenManager
        self.defaults = defaults
    }

    // MARK: Functions

    /// The signed-in user's server ID (from the access token), or `nil` when unauthenticated. Lets
    /// the repositories and sync engine tag and filter local records by owner synchronously.
    func currentUserID() -> String? {
        tokenManager.currentUserID
    }

    /// Returns a client for the current server URL, or `nil` if no valid URL is configured.
    func client() -> StashClient? {
        let urlString = defaults.string(forKey: AppGroup.serverURLKey) ?? ""
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        if cachedURLString == urlString, let cachedClient {
            return cachedClient
        }

        let client = StashClient(baseURL: url) { [tokenManager] in
            tokenManager.accessToken
        }

        cachedURLString = urlString
        cachedClient = client

        return client
    }
}
