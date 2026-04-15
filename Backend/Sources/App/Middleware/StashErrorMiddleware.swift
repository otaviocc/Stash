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
/// unmatched routes and validation failures — serialise to the standard envelope.
struct StashErrorMiddleware: AsyncMiddleware {

    // MARK: Static Functions

    /// Map bare HTTP statuses (e.g. routing 404s) onto the standard code table.
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
