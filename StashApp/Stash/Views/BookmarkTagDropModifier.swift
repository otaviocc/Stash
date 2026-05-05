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

import SwiftUI

// MARK: - BookmarkTagDropModifier

/// Makes a sidebar tag row accept dropped bookmarks, appending the tag to each. Used by the iPad and
/// macOS tag sidebars so a bookmark can be tagged by dragging it onto a tag. The drop reuses the
/// repository's optimistic `update`, so the change shows immediately and syncs in the background.
struct BookmarkTagDropModifier: ViewModifier {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment
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
            .listRowBackground(isTargeted ? Color.accentColor.opacity(0.15) : nil)
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
