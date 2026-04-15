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
import Foundation

/// Records every hard-deleted bookmark so clients can remove their local copies.
///
/// A deleted bookmark disappears from the `bookmarks` table and can no longer be
/// returned by a `changes?since=` query, so a synced client would never learn it
/// is gone. This tombstone persists the deletion, scoped to the owning user, and
/// is kept indefinitely — no cleanup in this version.
final class DeletedBookmark: Model, @unchecked Sendable {

    // MARK: Static Properties

    static let schema = "deleted_bookmarks"

    // MARK: Properties

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userID: UUID

    @Field(key: "bookmark_id")
    var bookmarkID: UUID

    @Timestamp(key: "deleted_at", on: .create)
    var deletedAt: Date?

    // MARK: Lifecycle

    init() {}

    init(userID: UUID, bookmarkID: UUID) {
        self.userID = userID
        self.bookmarkID = bookmarkID
    }

    // MARK: Static Functions

    /// Records a tombstone for a hard-deleted bookmark. Call after the bookmark row
    /// is removed.
    static func record(bookmarkID: UUID, userID: UUID, on db: Database) async throws {
        try await DeletedBookmark(userID: userID, bookmarkID: bookmarkID).save(on: db)
    }
}
