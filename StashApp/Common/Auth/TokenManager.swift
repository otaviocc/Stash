// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

/// Manages authentication tokens backed by the Keychain.
///
/// Token expiry is determined by manually base64url-decoding the access token's JWT payload and
/// reading its `exp` claim, no external dependency, mirroring the CLI's refresh logic. A token
/// that cannot be parsed is treated as expiring, so the caller refreshes rather than sending a
/// request that would be rejected.
final class TokenManager: Sendable {

    // MARK: Static Properties

    private static let expiryThreshold: TimeInterval = 60

    // MARK: Properties

    private let accessTokenStore: KeychainStore
    private let refreshTokenStore: KeychainStore

    // MARK: Computed Properties

    var accessToken: String? {
        accessTokenStore.wrappedValue
    }

    var refreshToken: String? {
        refreshTokenStore.wrappedValue
    }

    /// The signed-in user's server ID, read synchronously from the access token's `sub` claim (the
    /// backend sets it to the user's UUID string). `nil` when there is no token or it cannot be
    /// parsed. Used to tag and filter local records by owner without a network round-trip.
    var currentUserID: String? {
        guard let accessToken else {
            return nil
        }

        return subject(of: accessToken)
    }

    // MARK: Lifecycle

    init(
        accessTokenStore: KeychainStore,
        refreshTokenStore: KeychainStore
    ) {
        self.accessTokenStore = accessTokenStore
        self.refreshTokenStore = refreshTokenStore
    }

    // MARK: Functions

    func save(
        accessToken: String,
        refreshToken: String
    ) {
        accessTokenStore.wrappedValue = accessToken
        refreshTokenStore.wrappedValue = refreshToken
    }

    func clearTokens() {
        accessTokenStore.wrappedValue = nil
        refreshTokenStore.wrappedValue = nil
    }

    /// Returns `true` if there is no access token, it cannot be parsed, or its `exp` claim is within
    /// 60 seconds of now.
    func isAccessTokenExpiringSoon() -> Bool {
        guard let accessToken, let expiration = expirationDate(of: accessToken) else {
            return true
        }

        return expiration.timeIntervalSinceNow < Self.expiryThreshold
    }

    private func expirationDate(of token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard
            segments.count >= 2,
            let payload = base64URLDecode(String(segments[1])),
            let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let exp = object["exp"] as? Double
        else {
            return nil
        }

        return Date(timeIntervalSince1970: exp)
    }

    private func subject(of token: String) -> String? {
        let segments = token.split(separator: ".")
        guard
            segments.count >= 2,
            let payload = base64URLDecode(String(segments[1])),
            let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let subject = object["sub"] as? String
        else {
            return nil
        }

        return subject
    }

    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4

        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }
}
