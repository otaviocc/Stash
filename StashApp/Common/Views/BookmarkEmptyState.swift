// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - BookmarkEmptyState

/// A calm, consistent empty state for bookmark lists and filtered views. Each use supplies copy that
/// names the active context and tells the user what to do next, rather than a generic placeholder.
struct BookmarkEmptyState: View {

    // MARK: Properties

    let symbol: String
    let title: String
    let message: String

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.quaternary)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
    #Preview {
        BookmarkEmptyState(
            symbol: "bookmark",
            title: "No bookmarks yet",
            message: "Save your first bookmark using the + button, the Share Extension, or the browser extension."
        )
    }
#endif
