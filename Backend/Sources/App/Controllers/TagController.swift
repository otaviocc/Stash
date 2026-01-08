import Fluent
import Vapor

/// Tag aggregation for the authenticated user (PRD §9.4).
struct TagController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("tags", use: list)
    }

    // GET /tags — every distinct tag with its count, scoped to the current user.
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
}
