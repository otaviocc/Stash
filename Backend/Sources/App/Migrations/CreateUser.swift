import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .id()
            .field("username", .string, .required)
            .field("password_hash", .string, .required)
            .field("totp_secret", .string)
            .field("is_totp_enabled", .bool, .required, .sql(.default(false)))
            .field("role", .string, .required)
            .field("is_active", .bool, .required, .sql(.default(true)))
            .field("bookmark_count", .int, .required, .sql(.default(0)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "username")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users").delete()
    }
}
