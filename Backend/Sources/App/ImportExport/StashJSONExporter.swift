import Fluent
import Foundation

/// Exports all of a user's bookmarks (archived included) in Stash's native JSON format,
/// sorted by `createdAt` ascending.
struct StashJSONExporter: BookmarkExporter {
    static let identifier = "stash-json"
    static let displayName = "Stash JSON"
    static let fileExtension = "json"
    static let mimeType = "application/json"

    private struct Document: Encodable {
        let version: String
        let exportedAt: String
        let bookmarks: [Item]
    }

    private struct Item: Encodable {
        let id: String
        let url: String
        let title: String
        let description: String?
        let tags: [String]
        let faviconURL: String?
        let isArchived: Bool
        let createdAt: String
        let updatedAt: String
    }

    func export(for userID: UUID, on db: any Database) async throws -> Data {
        let bookmarks = try await Bookmark.query(on: db)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .ascending)
            .sort(\.$id, .ascending)
            .all()

        let iso = ISO8601DateFormatter()
        let items = try bookmarks.map { bookmark in
            Item(
                id: try bookmark.requireID().uuidString,
                url: bookmark.url,
                title: bookmark.title,
                description: bookmark.description,
                tags: bookmark.tags,
                faviconURL: bookmark.faviconURL,
                isArchived: bookmark.isArchived,
                createdAt: iso.string(from: bookmark.createdAt ?? Date()),
                updatedAt: iso.string(from: bookmark.updatedAt ?? Date())
            )
        }

        let document = Document(version: "1", exportedAt: iso.string(from: Date()), bookmarks: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }
}
