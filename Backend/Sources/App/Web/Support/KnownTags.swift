// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent

/// Loads a user's distinct tag names as a JSON array string, embedded in the add/edit and Smart View
/// forms (the `data-known-tags` attribute) to drive client-side tag autocomplete.
enum KnownTags {

    static func json(for user: User, on db: any Database) async throws -> String {
        let bookmarks = try await Bookmark.query(on: db)
            .filter(\.$user.$id == user.requireID())
            .all()
        let names = Set(bookmarks.flatMap(\.tags)).sorted()
        return TagPresenter.jsonArray(names)
    }
}
