// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import SQLKit

/// Migration that creates the `audit_logs` table.
struct CreateAuditLog: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("audit_logs")
            .id()
            .field("actor_username", .string)
            .field("action", .string, .required)
            .field("detail", .string)
            .field("ip", .string)
            .field("created_at", .datetime)
            .create()

        try await (database as? SQLDatabase)?.create(index: "audit_logs_created_at")
            .on("audit_logs")
            .column("created_at")
            .run()
    }

    func revert(on database: Database) async throws {
        try await (database as? SQLDatabase)?.drop(index: "audit_logs_created_at").run()
        try await database.schema("audit_logs").delete()
    }
}
