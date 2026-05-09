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
