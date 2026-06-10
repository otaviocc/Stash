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
/// to expire. A failed refresh clears the session so the UI returns to the login screen.
@MainActor
@Observable
final class AuthRepository: SessionRefreshing {

    // MARK: Properties

    private(set) var isAuthenticated: Bool

    private let clientProvider: StashClientProvider
    private let tokenManager: TokenManager

    // MARK: Lifecycle

    init(
        clientProvider: StashClientProvider,
        tokenManager: TokenManager
    ) {
        self.clientProvider = clientProvider
        self.tokenManager = tokenManager
        isAuthenticated = tokenManager.accessToken != nil
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
        defer { clearSession() }

        if let client = clientProvider.client(), let refreshToken = tokenManager.refreshToken {
            _ = try? await client.run(AuthRequestFactory.makeLogoutRequest(refreshToken: refreshToken))
        }
    }

    func refreshIfNeeded() async throws {
        guard tokenManager.isAccessTokenExpiringSoon() else {
            return
        }
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
            clearSession()
            throw error
        }
    }

    func currentUser() async throws -> CurrentUser {
        let client = try await authenticatedClient()
        let dto = try await client.run(UserRequestFactory.makeMeRequest()).value

        return CurrentUser(dto: dto)
    }

    func changePassword(
        current: String,
        new: String
    ) async throws {
        let client = try await authenticatedClient()
        _ = try await client.run(
            UserRequestFactory.makeChangePasswordRequest(
                ChangePasswordRequest(currentPassword: current, newPassword: new)
            )
        )
    }

    func beginTOTPSetup() async throws -> TOTPSetup {
        let client = try await authenticatedClient()
        let dto = try await client.run(AuthRequestFactory.makeTOTPSetupRequest()).value

        return TOTPSetup(secret: dto.secret, otpauthURI: dto.otpauthURI)
    }

    func completeTOTPSetup(
        code: String
    ) async throws -> [String] {
        let client = try await authenticatedClient()

        return try await client.run(
            AuthRequestFactory.makeTOTPVerifyRequest(code: code)
        ).value.recoveryCodes
    }

    func disableTOTP(
        code: String
    ) async throws {
        let client = try await authenticatedClient()
        _ = try await client.run(
            AuthRequestFactory.makeTOTPDisableRequest(totpCode: code)
        )
    }

    private func authenticatedClient() async throws -> StashClient {
        try await refreshIfNeeded()

        guard let client = clientProvider.client() else {
            throw AppError.notConfigured
        }

        return client
    }

    private func completeLogin(accessToken: String, refreshToken: String) {
        tokenManager.save(accessToken: accessToken, refreshToken: refreshToken)
        isAuthenticated = true
    }

    private func clearSession() {
        tokenManager.clearTokens()
        isAuthenticated = false
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
