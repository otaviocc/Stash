// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - AddBookmarkSheet

/// Presents the shared `AddBookmarkView` as a sheet in the main app.
///
/// The URL is editable here (the user types or pastes it) and metadata is fetched on demand. A
/// saved bookmark invalidates the tag cache and dismisses the sheet; it also lands in the presenting
/// list because the shared `AddBookmarkView` writes through the list's repository.
struct AddBookmarkSheet: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    // MARK: Properties

    /// The list's repository, so a saved bookmark appears in the list that presented this sheet.
    let repository: BookmarkRepository

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        AddBookmarkView(
            isURLEditable: true,
            autoFetchOnAppear: false,
            bookmarkStore: repository,
            tagStore: environment.tagRepository,
            onSaved: { _ in
                environment.tagRepository.refresh()
                dismiss()
            },
            onCancel: { dismiss() }
        )
    }
}

#if DEBUG
    #Preview {
        AddBookmarkSheet(repository: AppEnvironment.preview.makeBookmarkRepository())
            .environment(AppEnvironment.preview)
    }
#endif
