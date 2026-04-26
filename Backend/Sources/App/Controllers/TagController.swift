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

/// Tag aggregation for the authenticated user (PRD §9.4).
struct TagController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get("tags", use: list)
        routes.post("tags", "rename", use: rename)
    }

    /// GET /tags — every distinct tag with its count, scoped to the current user.
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

    /// POST /tags/rename — rename a tag (and its children) across the current user's bookmarks.
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
}
