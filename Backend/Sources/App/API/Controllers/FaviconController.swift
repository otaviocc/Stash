// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

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
