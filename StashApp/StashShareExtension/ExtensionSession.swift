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

/// Vends an authenticated `StashClient` for the Share Extension, applying the same silent token
/// refresh the main app's `AuthRepository` performs.
///
/// The extension cannot share the app's live repository instances (it is a separate process), so it
/// reads the tokens the app wrote to the shared Keychain access group and the server URL from the
/// shared `UserDefaults` suite. Before each request it refreshes the access token if it is expiring
/// soon, rotating the pair back into the shared Keychain. There is no login flow here: if there is
/// no configured server or no stored refresh token, the extension treats the user as signed out.
@MainActor
final class ExtensionSession {

    // MARK: Properties

    private let clientProvider: StashClientProvider
    private let tokenManager: TokenManager
    private var inflightRefresh: Task<Void, Error>?

    // MARK: Computed Properties

    /// Whether a server is configured and a refresh token is present — the minimum needed to make
    /// authenticated requests without an in-extension login.
    var isSignedIn: Bool {
        clientProvider.client() != nil && tokenManager.refreshToken != nil
    }

    // MARK: Lifecycle

    init() {
        let accessTokenStore = KeychainStore(
            AppGroup.accessTokenKey,
            accessGroup: AppGroup.identifier
        )
        let refreshTokenStore = KeychainStore(
            AppGroup.refreshTokenKey,
            accessGroup: AppGroup.identifier
        )
        tokenManager = TokenManager(
            accessTokenStore: accessTokenStore,
            refreshTokenStore: refreshTokenStore
        )
        clientProvider = StashClientProvider(
            tokenManager: tokenManager,
            defaults: AppGroup.makeSharedDefaults()
        )
    }

    // MARK: Functions

    func authenticatedClient() async throws -> StashClient {
        try await refreshIfNeeded()

        guard let client = clientProvider.client() else {
            throw AppError.notConfigured
        }

        return client
    }

    private func refreshIfNeeded() async throws {
        guard tokenManager.isAccessTokenExpiringSoon() else {
            return
        }

        if let inflightRefresh {
            return try await inflightRefresh.value
        }

        let task = Task { try await performRefresh() }
        inflightRefresh = task

        defer { inflightRefresh = nil }

        try await task.value
    }

    private func performRefresh() async throws {
        guard let client = clientProvider.client(), let refreshToken = tokenManager.refreshToken else {
            throw AppError.sessionExpired
        }

        let pair = try await client
            .run(AuthRequestFactory.makeRefreshRequest(refreshToken: refreshToken))
            .value
        tokenManager.save(accessToken: pair.accessToken, refreshToken: pair.refreshToken)
    }
}
