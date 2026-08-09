// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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

    /// Whether a server is configured and a refresh token is present: the minimum needed to make
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

    func authenticatedClient() async throws -> AuthorizedClient {
        try await refreshIfNeeded()

        guard let client = clientProvider.client() else {
            throw AppError.notConfigured
        }

        return AuthorizedClient(client: client) { [weak self] in
            try await self?.coalescedRefresh()
        }
    }

    private func refreshIfNeeded() async throws {
        guard tokenManager.isAccessTokenExpiringSoon() else {
            return
        }

        try await coalescedRefresh()
    }

    private func coalescedRefresh() async throws {
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
