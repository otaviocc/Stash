// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import MicroClient

// MARK: - MockURLSession

/// A `URLSessionProtocol` stub that records the last request it received and replays a
/// canned status code and body, so `StashClient` can be exercised without real networking.
final class MockURLSession: URLSessionProtocol, @unchecked Sendable {

    // MARK: Properties

    private let lock = NSLock()
    private let statusCode: Int
    private let body: Data
    private var capturedRequest: URLRequest?

    // MARK: Computed Properties

    var lastRequest: URLRequest? {
        lock.withLock { capturedRequest }
    }

    // MARK: Lifecycle

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    convenience init(statusCode: Int, json: String) {
        self.init(statusCode: statusCode, body: Data(json.utf8))
    }

    // MARK: Functions

    func data(
        for request: URLRequest,
        delegate: URLSessionTaskDelegate?
    ) async throws -> (Data, URLResponse) {
        lock.withLock { capturedRequest = request }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        return (body, response)
    }
}
