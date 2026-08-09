// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Vapor

/// Tag aggregation for the authenticated user (Docs/product-api.md §9.4).
struct TagController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get("tags", use: list)
        routes.post("tags", "rename", use: rename)
        routes.delete("tags", ":tag", use: delete)
    }

    func list(req: Request) async throws -> [TagCount] {
        let user = try req.auth.require(User.self)

        let bookmarks = try await Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .all()

        var counts: [String: Int] = [:]
        for bookmark in bookmarks {
            for tag in bookmark.tags {
                counts[tag, default: 0] += 1
            }
        }

        return counts
            .map { TagCount(name: $0.key, count: $0.value) }
            .sorted { $0.name < $1.name }
    }

    func rename(req: Request) async throws -> TagRenameResponse {
        let user = try req.auth.require(User.self)
        let input = try req.content.decode(TagRenameRequest.self)
        let result = try await TagRenamer.rename(
            rawFrom: input.from,
            rawTo: input.to,
            for: user.requireID(),
            on: req.db
        )
        return TagRenameResponse(from: result.from, to: result.to, affectedBookmarks: result.affectedBookmarks)
    }

    func delete(req: Request) async throws -> TagDeleteResponse {
        let user = try req.auth.require(User.self)
        let rawTag = req.parameters.get("tag") ?? ""
        let result = try await TagDeleter.delete(
            rawTag: rawTag,
            for: user.requireID(),
            on: req.db
        )
        return TagDeleteResponse(tag: result.tag, affectedBookmarks: result.affectedBookmarks)
    }
}
