import Vapor

/// Fetch page metadata for a URL without saving it (PRD §9.5).
struct MetadataController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("metadata", use: fetch)
    }

    // POST /metadata
    func fetch(req: Request) async throws -> MetadataResponse {
        _ = try req.auth.require(User.self)
        let input = try req.content.decode(MetadataRequest.self)
        let url = try Bookmark.validatedURL(input.url)
        return await MetadataFetcher.fetch(url: url, on: req)
    }
}
