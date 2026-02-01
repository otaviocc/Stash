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

/// Manages authentication tokens backed by the Keychain.
///
/// Token expiry is determined by manually base64url-decoding the access token's JWT payload and
/// reading its `exp` claim — no external dependency, mirroring the CLI's refresh logic. A token
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

    // MARK: Lifecycle

    init(accessTokenStore: KeychainStore, refreshTokenStore: KeychainStore) {
        self.accessTokenStore = accessTokenStore
        self.refreshTokenStore = refreshTokenStore
    }

    // MARK: Functions

    func save(accessToken: String, refreshToken: String) {
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
