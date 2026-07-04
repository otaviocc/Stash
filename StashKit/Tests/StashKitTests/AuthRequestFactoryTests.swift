// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import MicroClient
import Testing
@testable import StashKit

// MARK: - AuthRequestFactoryTests

/// Verifies the paths, methods, and body encoding produced by `AuthRequestFactory`.
@Suite("AuthRequestFactory — paths, methods, and bodies")
struct AuthRequestFactoryTests {

    @Test("builds a POST login request with the correct path and encoded body")
    func loginRequest() throws {
        // Given
        let request = AuthRequestFactory.makeLoginRequest(username: "ada", password: "lovelace-12")

        // When
        let json = try encodedBody(request.body)

        // Then
        #expect(request.path == "/api/v1/auth/login", "It should target the login endpoint")
        #expect(request.method == .post, "It should use POST")
        #expect(json["username"] as? String == "ada", "It should encode the username")
        #expect(json["password"] as? String == "lovelace-12", "It should encode the password")
    }

    @Test("builds a POST refresh request with the correct path and encoded body")
    func refreshRequest() throws {
        // Given
        let request = AuthRequestFactory.makeRefreshRequest(refreshToken: "refresh-abc")

        // When
        let json = try encodedBody(request.body)

        // Then
        #expect(request.path == "/api/v1/auth/refresh", "It should target the refresh endpoint")
        #expect(request.method == .post, "It should use POST")
        #expect(json["refreshToken"] as? String == "refresh-abc", "It should encode the refresh token")
    }

    @Test("builds a GET TOTP setup request with no body")
    func totpSetupRequest() {
        // Given
        let request = AuthRequestFactory.makeTOTPSetupRequest()

        // Then
        #expect(request.path == "/api/v1/auth/totp/setup", "It should target the TOTP setup endpoint")
        #expect(request.method == .get, "It should use GET")
        #expect(request.body == nil, "It should not carry a request body")
    }

    // MARK: - Helpers

    private func encodedBody(_ body: (some Encodable)?) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: data)

        return object as? [String: Any] ?? [:]
    }
}
