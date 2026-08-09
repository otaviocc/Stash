// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Foundation

/// Records every hard-deleted bookmark so clients can remove their local copies.
///
/// A deleted bookmark disappears from the `bookmarks` table and can no longer be
/// returned by a `changes?since=` query, so a synced client would never learn it
/// is gone. This tombstone persists the deletion, scoped to the owning user, and
/// is kept indefinitely; no cleanup in this version.
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
