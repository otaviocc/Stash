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

// MARK: - AuthRequestFactory

/// Factory for authentication-related API requests.
public enum AuthRequestFactory {

    public static func makeLoginRequest(
        username: String,
        password: String
    ) -> NetworkRequest<LoginRequest, TokenPairDTO> {
        .init(
            path: "/api/v1/auth/login",
            method: .post,
            body: LoginRequest(username: username, password: password)
        )
    }

    public static func makeTOTPRequest(
        tempToken: String,
        code: String
    ) -> NetworkRequest<TOTPRequest, TokenPairDTO> {
        .init(
            path: "/api/v1/auth/totp",
            method: .post,
            body: TOTPRequest(tempToken: tempToken, totpCode: code)
        )
    }

    public static func makeRecoveryRequest(
        tempToken: String,
        code: String
    ) -> NetworkRequest<RecoveryCodeRequest, TokenPairDTO> {
        .init(
            path: "/api/v1/auth/recovery",
            method: .post,
            body: RecoveryCodeRequest(tempToken: tempToken, recoveryCode: code)
        )
    }

    public static func makeRefreshRequest(
        refreshToken: String
    ) -> NetworkRequest<RefreshRequest, TokenPairDTO> {
        .init(
            path: "/api/v1/auth/refresh",
            method: .post,
            body: RefreshRequest(refreshToken: refreshToken)
        )
    }

    public static func makeLogoutRequest(
        refreshToken: String
    ) -> NetworkRequest<RefreshRequest, VoidResponse> {
        .init(
            path: "/api/v1/auth/logout",
            method: .post,
            body: RefreshRequest(refreshToken: refreshToken)
        )
    }

    public static func makeTOTPSetupRequest() -> NetworkRequest<VoidRequest, TOTPSetupDTO> {
        .init(
            path: "/api/v1/auth/totp/setup",
            method: .get
        )
    }

    public static func makeTOTPVerifyRequest(
        code: String
    ) -> NetworkRequest<TOTPVerifyRequest, TOTPEnrolmentDTO> {
        .init(
            path: "/api/v1/auth/totp/verify-setup",
            method: .post,
            body: TOTPVerifyRequest(totpCode: code)
        )
    }

    public static func makeTOTPDisableRequest(
        totpCode: String
    ) -> NetworkRequest<TOTPDisableRequest, VoidResponse> {
        .init(
            path: "/api/v1/auth/totp/disable",
            method: .post,
            body: TOTPDisableRequest(totpCode: totpCode)
        )
    }
}
