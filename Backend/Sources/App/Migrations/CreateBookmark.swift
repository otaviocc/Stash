import Fluent

struct CreateBookmark: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("bookmarks")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("url", .string, .required)
            .field("title", .string, .required)
            .field("description", .string)
            .field("favicon_url", .string)
            .field("tags", .array(of: .string), .required)
            .field("tags_search", .string, .required)
            .field("is_archived", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            // One bookmark per URL per user (PRD §7.2).
            .unique(on: "user_id", "url")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("bookmarks").delete()
    }
}
