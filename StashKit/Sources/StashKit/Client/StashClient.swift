// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import MicroClient

// MARK: - StashClient

/// A configured client for communicating with a Stash server.
///
/// `StashClient` is a thin wrapper around `NetworkClient`: it owns the `NetworkConfiguration`
/// (base URL plus a `BearerAuthorizationInterceptor` for the JWT access token) and exposes a
/// single `run(_:)` method. It performs no storage, no token refresh, and no business logic:
/// those are the app's repository-layer responsibilities. Its only added behavior over
/// `NetworkClient` is mapping a failed response into a typed `StashAPIError`.
public final class StashClient: Sendable {

    // MARK: Static Properties

    /// The per-request timeout, in seconds, for the default session.
    ///
    /// Kept well below `URLSession`'s 60-second default so that an unreachable server (the network
    /// is up but the backend can't be reached, e.g. the user is off the LAN where Stash is hosted)
    /// fails fast and surfaces an error, rather than leaving a spinner running for a full minute. This
    /// caps the wait for *new data* and resets whenever data arrives, so a slow-but-progressing
    /// transfer is not aborted; no `timeoutIntervalForResource` is set for the same reason.
    private static let defaultRequestTimeout: TimeInterval = 15

    /// A single process-wide session for every default client.
    ///
    /// Mirrors `URLSession.shared` (a long-lived, never-invalidated session with a shared connection
    /// pool) while applying `defaultRequestTimeout`. Shared rather than per-client so that rebuilding a
    /// `StashClient` on a server-URL change recreates only the lightweight wrapper, never orphaning a
    /// session.
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = defaultRequestTimeout

        return URLSession(configuration: configuration)
    }()

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
            session: Self.defaultSession,
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
            interceptors: [
                BearerAuthorizationInterceptor(tokenProvider: tokenProvider),
                ContentTypeInterceptor(),
                AcceptHeaderInterceptor()
            ]
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
        case "not_found", "smart_view_not_found": .notFound
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
