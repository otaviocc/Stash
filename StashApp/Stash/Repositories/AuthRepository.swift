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

// MARK: - AuthRepository

/// Manages authentication state and login/logout operations.
///
/// Owns the silent token refresh used by the other repositories: before an authenticated request,
/// `refreshIfNeeded()` checks the access token's expiry and rotates the token pair when it is about
/// to expire. Concurrent callers are coalesced onto a single in-flight refresh so the single-use
/// refresh token is never rotated twice in parallel. Only a definitive authentication failure clears
/// the session and returns the UI to login; a transient network or server error is rethrown with the
/// session left intact so the caller can retry.
@MainActor
@Observable
final class AuthRepository: SessionRefreshing {

    // MARK: Properties

    private(set) var isAuthenticated: Bool

    /// Invoked when the session is cleared by an **involuntary** expiry (token expired/revoked,
    /// account suspended). Pending offline writes are preserved by this path.
    var onSessionCleared: (() -> Void)?

    /// Invoked when the user **explicitly** signs out. A full clean slate — pending offline writes are
    /// discarded so the next user inherits nothing.
    var onExplicitLogout: (() -> Void)?

    private let clientProvider: StashClientProvider
    private let tokenManager: TokenManager
    private var inflightRefresh: Task<Void, Error>?

    // MARK: Lifecycle

    init(
        clientProvider: StashClientProvider,
        tokenManager: TokenManager
    ) {
        self.clientProvider = clientProvider
        self.tokenManager = tokenManager
        isAuthenticated = tokenManager.refreshToken != nil
    }

    // MARK: Static Functions

    private static func isAuthenticationFailure(_ error: Error) -> Bool {
        switch error {
        case StashAPIError.tokenExpired,
             StashAPIError.tokenInvalid,
             StashAPIError.invalidCredentials,
             StashAPIError.accountSuspended:
            true
        default:
            false
        }
    }

    // MARK: Functions

    func login(
        username: String,
        password: String
    ) async throws -> LoginResult {
        guard let client = clientProvider.client() else {
            throw AppError.notConfigured
        }

        let outcome = try await client
            .run(LoginOutcome.makeRequest(username: username, password: password))
            .value

        if outcome.requires2FA == true {
            guard let tempToken = outcome.tempToken else {
                throw AppError.unexpectedResponse
            }

            return .requires2FA(tempToken: tempToken)
        }

        guard let accessToken = outcome.accessToken, let refreshToken = outcome.refreshToken else {
            throw AppError.unexpectedResponse
        }

        completeLogin(accessToken: accessToken, refreshToken: refreshToken)

        return .authenticated
    }

    func submitTOTP(
        tempToken: String,
        code: String
    ) async throws {
        guard let client = clientProvider.client() else {
            throw AppError.notConfigured
        }

        let pair = try await client
            .run(AuthRequestFactory.makeTOTPRequest(tempToken: tempToken, code: code))
            .value

        completeLogin(accessToken: pair.accessToken, refreshToken: pair.refreshToken)
    }

    func submitRecoveryCode(
        tempToken: String,
        code: String
    ) async throws {
        guard let client = clientProvider.client() else {
            throw AppError.notConfigured
        }

        let pair = try await client
            .run(AuthRequestFactory.makeRecoveryRequest(tempToken: tempToken, code: code))
            .value

        completeLogin(accessToken: pair.accessToken, refreshToken: pair.refreshToken)
    }

    func logout() async throws {
        defer { clearSession(explicit: true) }

        if let client = clientProvider.client(), let refreshToken = tokenManager.refreshToken {
            _ = try? await client.run(AuthRequestFactory.makeLogoutRequest(refreshToken: refreshToken))
        }
    }

    func authorizedClient() async throws -> AuthorizedClient {
        try await refreshIfNeeded()

        guard let client = clientProvider.client() else {
            throw AppError.notConfigured
        }

        return AuthorizedClient(client: client) { [weak self] in
            try await self?.coalescedRefresh()
        }
    }

    func currentUser() async throws -> CurrentUser {
        let client = try await authorizedClient()
        let dto = try await client.run(UserRequestFactory.makeMeRequest()).value

        return CurrentUser(dto: dto)
    }

    func changePassword(
        current: String,
        new: String
    ) async throws {
        let client = try await authorizedClient()
        _ = try await client.run(
            UserRequestFactory.makeChangePasswordRequest(
                ChangePasswordRequest(currentPassword: current, newPassword: new)
            )
        )
    }

    func beginTOTPSetup() async throws -> TOTPSetup {
        let client = try await authorizedClient()
        let dto = try await client.run(AuthRequestFactory.makeTOTPSetupRequest()).value

        return TOTPSetup(secret: dto.secret, otpauthURI: dto.otpauthURI)
    }

    func completeTOTPSetup(
        code: String
    ) async throws -> [String] {
        let client = try await authorizedClient()

        return try await client.run(
            AuthRequestFactory.makeTOTPVerifyRequest(code: code)
        ).value.recoveryCodes
    }

    func disableTOTP(
        code: String
    ) async throws {
        let client = try await authorizedClient()
        _ = try await client.run(
            AuthRequestFactory.makeTOTPDisableRequest(totpCode: code)
        )
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

    /// Rotates the token pair using the stored refresh token.
    ///
    /// On a definitive authentication failure the session is cleared — but only if the refresh token
    /// in the Keychain is still the one this call attempted with. The app and the Share Extension share
    /// one single-use refresh token across processes, so the other process may have legitimately
    /// rotated it between our read and the server's reply; in that race our token is rejected as
    /// already-used while a valid successor sits in the Keychain. Re-reading guards against that
    /// spurious logout — the next request picks up the rotated token instead.
    private func performRefresh() async throws {
        guard let client = clientProvider.client(), let refreshToken = tokenManager.refreshToken else {
            clearSession()
            throw AppError.sessionExpired
        }

        do {
            let pair = try await client
                .run(AuthRequestFactory.makeRefreshRequest(refreshToken: refreshToken))
                .value
            tokenManager.save(accessToken: pair.accessToken, refreshToken: pair.refreshToken)
        } catch {
            if Self.isAuthenticationFailure(error), tokenManager.refreshToken == refreshToken {
                clearSession()
            }

            throw error
        }
    }

    private func completeLogin(accessToken: String, refreshToken: String) {
        tokenManager.save(accessToken: accessToken, refreshToken: refreshToken)
        isAuthenticated = true
    }

    private func clearSession(explicit: Bool = false) {
        tokenManager.clearTokens()
        isAuthenticated = false

        if explicit {
            onExplicitLogout?()
        } else {
            onSessionCleared?()
        }
    }
}

// MARK: - LoginOutcome

/// Decodes either shape of a successful login response: a token pair, or a 2FA challenge.
///
/// StashKit's typed login factory returns only `TokenPairDTO`, which cannot represent the
/// 2FA-challenge branch (both are returned as HTTP 200), so the repository builds its own request
/// against the same endpoint — the same approach the CLI uses.
struct LoginOutcome: Decodable {

    // MARK: Properties

    let accessToken: String?
    let refreshToken: String?
    let requires2FA: Bool?
    let tempToken: String?

    // MARK: Static Functions

    static func makeRequest(
        username: String,
        password: String
    ) -> NetworkRequest<LoginRequest, LoginOutcome> {
        .init(
            path: "/api/v1/auth/login",
            method: .post,
            body: LoginRequest(username: username, password: password)
        )
    }
}
