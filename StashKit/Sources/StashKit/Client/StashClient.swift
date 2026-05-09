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

// MARK: - StashClient

/// A configured client for communicating with a Stash server.
///
/// `StashClient` is a thin wrapper around `NetworkClient`: it owns the `NetworkConfiguration`
/// (base URL plus a `BearerAuthorizationInterceptor` for the JWT access token) and exposes a
/// single `run(_:)` method. It performs no storage, no token refresh, and no business logic —
/// those are the app's repository-layer responsibilities. Its only added behavior over
/// `NetworkClient` is mapping a failed response into a typed `StashAPIError`.
public final class StashClient: Sendable {

    // MARK: Properties

    private let client: NetworkClient
    private let errorDecoder: JSONDecoder

    // MARK: Lifecycle

    public convenience init(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?
    ) {
        self.init(
            baseURL: baseURL,
            session: URLSession.shared,
            tokenProvider: tokenProvider
        )
    }

    init(
        baseURL: URL,
        session: URLSessionProtocol,
        tokenProvider: @escaping @Sendable () async -> String?
    ) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let configuration = NetworkConfiguration(
            session: session,
            defaultDecoder: decoder,
            defaultEncoder: encoder,
            baseURL: baseURL,
            interceptors: [BearerAuthorizationInterceptor(tokenProvider: tokenProvider)]
        )

        client = NetworkClient(configuration: configuration)
        errorDecoder = JSONDecoder()
    }

    // MARK: Static Functions

    private static func mappedError(
        dto: APIErrorDTO,
        statusCode: Int,
        fallback: NetworkClientError
    ) -> StashAPIError {
        switch dto.code {
        case "invalid_credentials": .invalidCredentials
        case "account_suspended": .accountSuspended
        case "token_expired": .tokenExpired
        case "token_invalid": .tokenInvalid
        case "totp_required": .totpRequired
        case "totp_invalid": .totpInvalid
        case "forbidden": .forbidden
        case "not_found": .notFound
        case "username_taken": .usernameTaken
        case "validation_failed": .validationFailed
        case "internal_error": .serverError
        case "duplicate_url": dto.existingID.map { .duplicateURL(existingID: $0) } ?? .serverError
        default: statusCode >= 500 ? .serverError : .unknown(fallback)
        }
    }

    // MARK: Functions

    public func run<ResponseModel: Decodable & Sendable>(
        _ request: NetworkRequest<some Encodable & Sendable, ResponseModel>
    ) async throws -> NetworkResponse<ResponseModel> {
        do {
            return try await client.run(request)
        } catch let error as NetworkClientError {
            throw mapError(error)
        }
    }

    private func mapError(
        _ error: NetworkClientError
    ) -> StashAPIError {
        guard case let .unacceptableStatusCode(statusCode, _, data) = error else {
            return .unknown(error)
        }
        guard
            let data,
            let dto = try? errorDecoder.decode(APIErrorDTO.self, from: data)
        else {
            return statusCode >= 500 ? .serverError : .unknown(error)
        }

        return Self.mappedError(dto: dto, statusCode: statusCode, fallback: error)
    }
}
