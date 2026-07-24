// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - TagSuggestionView

/// A horizontally-scrolling row of tag suggestion chips. Tapping a chip appends it to the input.
struct TagSuggestionView: View {

    // MARK: SwiftUI Properties

    @Environment(\.instanceAccent) private var instanceAccent

    // MARK: Properties

    let suggestions: [Tag]
    let onSelect: (Tag) -> Void

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { tag in
                    Button {
                        onSelect(tag)
                    } label: {
                        Text(tag.name)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(instanceAccent.opacity(0.15), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(instanceAccent)
                }
            }
        }
    }
}

#if DEBUG
    #Preview {
        TagSuggestionView(suggestions: Tag.samples) { _ in }
            .padding()
    }
#endif
