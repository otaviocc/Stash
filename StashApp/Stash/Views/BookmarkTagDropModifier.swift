// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - BookmarkTagDropModifier

/// Makes a sidebar tag row accept dropped bookmarks, appending the tag to each. Used by the iPad and
/// macOS tag sidebars so a bookmark can be tagged by dragging it onto a tag. The drop reuses the
/// repository's optimistic `update`, so the change shows immediately and syncs in the background.
struct BookmarkTagDropModifier: ViewModifier {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.instanceAccent) private var instanceAccent
    @State private var isTargeted = false

    // MARK: Properties

    let slug: String

    // MARK: Content Methods

    // MARK: Content

    func body(content: Content) -> some View {
        content
            .dropDestination(for: Bookmark.self) { bookmarks, _ in
                handleDrop(bookmarks)

                return true
            } isTargeted: { isTargeted = $0 }
            .listRowBackground(isTargeted ? instanceAccent.opacity(0.15) : nil)
    }

    // MARK: Functions

    private func handleDrop(_ bookmarks: [Bookmark]) {
        let repository = environment.makeBookmarkRepository()

        Task {
            for bookmark in bookmarks where !bookmark.tags.contains(slug) {
                _ = try? await repository.update(
                    id: bookmark.id,
                    title: bookmark.title,
                    description: bookmark.description,
                    tags: bookmark.tags + [slug]
                )
            }

            environment.tagRepository.refresh()
        }
    }
}

extension View {

    /// Accepts bookmarks dropped onto a tag row, appending `slug` to each dropped bookmark's tags.
    func bookmarkTagDropDestination(slug: String) -> some View {
        modifier(BookmarkTagDropModifier(slug: slug))
    }
}
