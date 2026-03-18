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

import ArgumentParser
import Foundation
import MicroClient
import StashKit

// MARK: - CLIError

/// An error carrying a human-readable message to print to stderr.
struct CLIError: Error {

    // MARK: Properties

    let message: String

    // MARK: Lifecycle

    init(_ message: String) {
        self.message = message
    }
}

// MARK: - CLIErrorReporter

/// Maps thrown errors to the single-line messages shown to the user.
enum CLIErrorReporter {

    static func message(for error: Error) -> String {
        switch error {
        case let error as CLIError:
            error.message
        case let error as StashAPIError:
            message(for: error)
        case let error as NetworkClientError:
            message(for: error)
        default:
            error.localizedDescription
        }
    }

    /// Whether an error should abort a batch operation rather than be treated as one bad record.
    /// Per-record rejections (validation, duplicate, not-found, username conflicts) are recoverable
    /// and let the batch continue; auth, connectivity, server, and unrecognized errors abort it so a
    /// transient failure is never silently miscounted as invalid data.
    static func abortsBatch(_ error: Error) -> Bool {
        switch error {
        case StashAPIError.validationFailed,
             StashAPIError.duplicateURL,
             StashAPIError.notFound,
             StashAPIError.usernameTaken:
            false
        default:
            true
        }
    }

    private static func message(for error: StashAPIError) -> String {
        switch error {
        case .invalidCredentials:
            "Invalid username or password."
        case .accountSuspended:
            "This account is suspended."
        case .tokenExpired:
            "Session expired — please run stash login."
        case .tokenInvalid:
            "Session invalid — please run stash login."
        case .totpRequired:
            "Two-factor authentication is required."
        case .totpInvalid:
            "Invalid two-factor code."
        case .forbidden:
            "You don't have permission to perform that action."
        case .notFound:
            "Not found."
        case let .duplicateURL(existingID):
            "This URL is already saved (existing bookmark \(existingID.uuidString))."
        case .usernameTaken:
            "That username is already taken."
        case .validationFailed:
            "The request was invalid."
        case .serverError:
            "The server encountered an error."
        case let .unknown(underlying):
            message(for: underlying)
        }
    }

    private static func message(for error: NetworkClientError) -> String {
        switch error {
        case .malformedURL:
            "The server URL is invalid. Set it with: stash config set-url <url>"
        case let .transportError(underlying):
            "Could not reach the server. \(underlying.localizedDescription) "
                + "(Check the URL and scheme — a plain HTTP server needs http://, not https://.)"
        case let .unacceptableStatusCode(statusCode, _, _):
            "The server returned HTTP \(statusCode)."
        case .decodingError:
            "Could not decode the server's response."
        case .encodingError:
            "Could not encode the request."
        case let .interceptorError(underlying):
            "Request preparation failed. \(underlying.localizedDescription)"
        case let .responseInterceptorError(underlying):
            "Response handling failed. \(underlying.localizedDescription)"
        case let .unknown(underlying):
            underlying?.localizedDescription ?? "An unknown network error occurred."
        }
    }
}

extension AsyncParsableCommand {

    /// Runs a command body, printing `Error: <message>` to stderr and exiting non-zero on failure.
    func runCLI(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let exit as ExitCode {
            throw exit
        } catch {
            Console.error("Error: \(CLIErrorReporter.message(for: error))")

            throw ExitCode.failure
        }
    }

    func requireUUID(_ value: String, label: String = "ID") throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw CLIError("Invalid \(label): \(value)")
        }

        return id
    }
}
