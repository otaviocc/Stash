// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - SelectedTagChip

/// A muted chip for a selected tag. Renders the tag in the same `›`-separated display format as
/// `TagPill`, but with a quiet `.quaternary` capsule (rather than the accent tint) and an optional
/// `×` dismiss button. Shared by the tag picker's selected-tags strip and the add/edit forms' tag
/// row, so a tag removes the same way in both places; the Share Extension's confirmation passes
/// `showsDismissButton: false` for a read-only summary. Distinct from `TagPill`, which stays the
/// styled summary chip for the detail view.
struct SelectedTagChip: View {

    // MARK: Properties

    let tag: String
    var showsDismissButton = true
    let onRemove: () -> Void

    // MARK: Computed Properties

    private var displayName: String {
        tag.tagDisplayName
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        HStack(spacing: 6) {
            Text(displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            if showsDismissButton {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(displayName)")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, showsDismissButton ? 6 : 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: .capsule)
    }
}

#if DEBUG
    #Preview {
        HStack {
            SelectedTagChip(tag: "swift") {}
            SelectedTagChip(tag: "swift/vapor") {}
        }
        .padding()
    }
#endif
