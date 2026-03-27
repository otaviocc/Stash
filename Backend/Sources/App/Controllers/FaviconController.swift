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

import Fluent
import Vapor

/// Serves cached favicons by domain and triggers manual re-fetches (PRD §9.8). The `serve`
/// endpoint is unauthenticated so `<img>` tags can load it without attaching credentials; the
/// `refresh` endpoint requires an active user since it triggers outbound fetches.
struct FaviconController {

    // MARK: Static Properties

    static let cacheControl = "public, max-age=2592000, immutable"

    // MARK: Functions

    func serve(req: Request) async throws -> Response {
        guard let domain = req.parameters.get("domain")?.lowercased(), !domain.isEmpty else {
            throw APIError.notFound
        }
        guard let cache = try await FaviconCache.query(on: req.db)
            .filter(\.$domain == domain)
            .first(),
            cache.status == .cached,
            let data = cache.imageData
        else {
            throw APIError.notFound
        }

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: cache.contentType ?? "application/octet-stream")
        headers.replaceOrAdd(name: .cacheControl, value: Self.cacheControl)
        headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }

    func refresh(req: Request) async throws -> Response {
        _ = try req.auth.require(User.self)
        guard let domain = req.parameters.get("domain")?.lowercased(), !domain.isEmpty else {
            throw APIError.notFound
        }

        try await FaviconFetcher.refresh(domain: domain, on: req.application)
        return Response(status: .accepted)
    }
}
