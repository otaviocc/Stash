// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - TagCountBadge

/// A badge showing a tag's visible bookmark count. When archived items exist under the tag
/// (`totalCount > count`) it splits into two halves: the visible count on the accent-filled left and
/// the hidden (archived) count on the muted right, so both read at a glance without any arithmetic.
/// When everything is visible a single accent capsule shows the count: accent always means "visible",
/// dimmed always means "hidden".
struct TagCountBadge: View {

    // MARK: Properties

    let count: Int
    let totalCount: Int

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        if totalCount > count {
            makeSplitBadge()
        } else {
            makePlainBadge()
        }
    }

    // MARK: Content Methods

    private func makeSplitBadge() -> some View {
        HStack(spacing: 0) {
            Text("\(count)")
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.accentColor)
                .foregroundStyle(.white)

            Rectangle()
                .fill(.quaternary)
                .frame(width: 0.5)

            Text("\(totalCount - count)")
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.quaternary)
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .clipShape(Capsule())
    }

    private func makePlainBadge() -> some View {
        Text("\(count)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor, in: Capsule())
    }
}

#if DEBUG
    #Preview {
        VStack(alignment: .leading, spacing: 12) {
            TagCountBadge(count: 5, totalCount: 5)
            TagCountBadge(count: 1, totalCount: 5)
            TagCountBadge(count: 0, totalCount: 5)
        }
        .padding()
    }
#endif
