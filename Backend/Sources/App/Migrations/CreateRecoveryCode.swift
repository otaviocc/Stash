import Fluent

struct CreateRecoveryCode: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("recovery_codes")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("code_hash", .string, .required)
            .field("used_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("recovery_codes").delete()
    }
}
