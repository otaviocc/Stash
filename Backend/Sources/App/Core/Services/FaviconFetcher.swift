// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation
import Vapor

/// Fetches and caches a favicon image for a domain, trying the site's own icon first and falling
/// back to a third-party favicon service. Runs detached at bookmark creation time so it never
/// blocks the save. See the Favicon Caching section of `DECISIONS.md`.
enum FaviconFetcher {

    // MARK: Static Properties

    static let googleServicePrefix = "https://www.google.com/s2/favicons?sz=64&domain="

    // MARK: Static Functions

    static func fetchAndCache(
        domain: String,
        originURL: String? = nil,
        declaredIconURL: String? = nil,
        on db: Database,
        client: Client
    ) async {
        let cache = FaviconCache(domain: domain, status: .pending)
        do {
            try await cache.create(on: db)
        } catch let error as any DatabaseError where error.isConstraintFailure {
            return
        } catch {
            db.logger.error("Favicon cache insert failed for \(domain): \(String(reflecting: error))")
            return
        }

        let host = domain.split(separator: ":", maxSplits: 1).first.map(String.init) ?? domain

        var candidates: [String] = []
        if let declaredIconURL, !declaredIconURL.isEmpty { candidates.append(declaredIconURL) }
        candidates.append("\(originURL ?? "https://\(domain)")/favicon.ico")
        candidates.append("\(googleServicePrefix)\(host)")

        for candidate in candidates {
            guard let image = await fetchImage(candidate, client: client) else { continue }

            cache.imageData = image.data
            cache.contentType = image.contentType
            cache.sourceURL = candidate
            cache.status = .cached
            cache.fetchedAt = Date()
            await persist(cache, on: db)
            return
        }

        cache.status = .failed
        cache.fetchedAt = Date()
        await persist(cache, on: db)
    }

    static func enqueue(forURL url: String, declaredIconURL: String?, on app: Application) {
        guard let domain = DomainExtractor.domain(from: url) else { return }

        spawn(domain: domain, originURL: DomainExtractor.origin(from: url), declaredIconURL: declaredIconURL, on: app)
    }

    static func refresh(domain: String, on app: Application) async throws {
        try await FaviconCache.query(on: app.db)
            .filter(\.$domain == domain)
            .delete()
        spawn(domain: domain, originURL: nil, declaredIconURL: nil, on: app)
    }

    static func enqueueBackfill(forUser userID: UUID, on app: Application) {
        guard app.environment != .testing else { return }

        let db = app.db
        let client = app.client
        Task.detached {
            await backfill(forUser: userID, on: db, client: client)
        }
    }

    static func backfill(forUser userID: UUID, on db: Database, client: Client) async {
        let urls = await (try? Bookmark.query(on: db).filter(\.$user.$id == userID).all(\.$url)) ?? []

        var seen = Set<String>()
        for url in urls {
            guard let domain = DomainExtractor.domain(from: url), seen.insert(domain).inserted else { continue }

            await fetchAndCache(domain: domain, originURL: DomainExtractor.origin(from: url), on: db, client: client)
        }
    }

    // MARK: - Fetching

    private static func spawn(domain: String, originURL: String?, declaredIconURL: String?, on app: Application) {
        guard app.environment != .testing else { return }

        let db = app.db
        let client = app.client
        Task.detached {
            await fetchAndCache(
                domain: domain,
                originURL: originURL,
                declaredIconURL: declaredIconURL,
                on: db,
                client: client
            )
        }
    }

    private static func persist(_ cache: FaviconCache, on db: Database) async {
        do {
            try await cache.save(on: db)
        } catch {
            db.logger.error("Favicon cache save failed for \(cache.domain): \(String(reflecting: error))")
            try? await cache.delete(on: db)
        }
    }

    private static func fetchImage(
        _ urlString: String,
        client: Client
    ) async -> (data: Data, contentType: String)? {
        do {
            var headers = HTTPHeaders()
            headers.add(name: .userAgent, value: "StashBot/1.0 (+https://github.com/otaviocc/stash)")

            let response = try await client.get(URI(string: urlString), headers: headers)

            if let lengthHeader = response.headers.first(name: .contentLength),
               let length = Int(lengthHeader), length > FaviconCache.maxImageBytes
            {
                return nil
            }

            let type = response.headers.first(name: .contentType)?.lowercased()
            guard response.status == .ok,
                  let contentType = type,
                  contentType.hasPrefix("image/"),
                  !contentType.contains("svg"),
                  let body = response.body,
                  body.readableBytes > 0,
                  body.readableBytes <= FaviconCache.maxImageBytes,
                  let data = body.getData(at: body.readerIndex, length: body.readableBytes),
                  !data.isEmpty
            else {
                return nil
            }

            return (data, contentType)
        } catch {
            return nil
        }
    }
}
