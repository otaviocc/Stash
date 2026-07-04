// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

// MARK: - ErrorResponse

/// The single error envelope returned for every API error (PRD §17.4).
struct ErrorResponse: Content {

    let error: Bool
    let code: String
    let message: String
}

// MARK: - DuplicateURLErrorResponse

/// The duplicate-URL envelope, which additionally carries the existing bookmark's ID (PRD §17.4).
struct DuplicateURLErrorResponse: Content {

    let error: Bool
    let code: String
    let message: String
    let existingID: UUID
}

// MARK: - StashErrorMiddleware

/// Replaces Vapor's default error middleware so *all* errors — including 404s from
/// unmatched routes and validation failures — serialize to the standard envelope.
struct StashErrorMiddleware: AsyncMiddleware {

    // MARK: Static Functions

    private static func code(for status: HTTPResponseStatus) -> String {
        switch status {
        case .badRequest: "bad_request"
        case .unauthorized: "token_invalid"
        case .forbidden: "forbidden"
        case .notFound: "not_found"
        case .conflict: "duplicate_url"
        case .unprocessableEntity: "validation_failed"
        default: status.code >= 500 ? "internal_error" : "error"
        }
    }

    // MARK: Functions

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            return handle(error, for: request)
        }
    }

    private func handle(_ error: Error, for request: Request) -> Response {
        let status: HTTPResponseStatus
        let code: String
        let message: String
        var duplicateExistingID: UUID?

        switch error {
        case let apiError as APIError:
            status = apiError.status
            code = apiError.code
            message = apiError.reason
            if case let .duplicateURL(existingID) = apiError {
                duplicateExistingID = existingID
            }
        case let validation as ValidationsError:
            status = .unprocessableEntity
            code = "validation_failed"
            message = validation.description
        case let abort as AbortError:
            status = abort.status
            code = Self.code(for: abort.status)
            message = abort.reason
        default:
            status = .internalServerError
            code = "internal_error"
            message = "An unexpected error occurred."
        }

        if status == .internalServerError {
            request.logger.report(error: error)
        }

        let response = Response(status: status)
        response.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
        do {
            if let existingID = duplicateExistingID {
                response.body = try .init(data: JSONEncoder().encode(
                    DuplicateURLErrorResponse(error: true, code: code, message: message, existingID: existingID)
                ))
            } else {
                response.body = try .init(data: JSONEncoder().encode(
                    ErrorResponse(error: true, code: code, message: message)
                ))
            }
        } catch {
            response
                .body =
                .init(string: #"{"error":true,"code":"internal_error","message":"An unexpected error occurred."}"#)
        }
        return response
    }
}
