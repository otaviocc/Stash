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
import SQLKit

/// Migration that creates the `deleted_bookmarks` tombstone table.
struct CreateDeletedBookmarks: AsyncMigration {

    func prepare(on database: Database) async throws {
        try await database.schema("deleted_bookmarks")
            .id()
            .field("user_id", .uuid, .required)
            .field("bookmark_id", .uuid, .required)
            .field("deleted_at", .datetime)
            .create()

        try await (database as? SQLDatabase)?.create(index: "deleted_bookmarks_user_deleted_at")
            .on("deleted_bookmarks")
            .column("user_id")
            .column("deleted_at")
            .run()
    }

    func revert(on database: Database) async throws {
        try await (database as? SQLDatabase)?.drop(index: "deleted_bookmarks_user_deleted_at").run()
        try await database.schema("deleted_bookmarks").delete()
    }
}
