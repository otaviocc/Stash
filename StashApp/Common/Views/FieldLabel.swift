// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - FieldLabel

/// A small, muted label that floats above a form field in the custom add/edit bookmark layout
/// (Things-style), replacing the grouped `Form`'s section headers. The tertiary level of the same
/// typographic scale used across the bookmark list and detail views.
struct FieldLabel: View {

    // MARK: Properties

    let text: String

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - View + FieldSectionPadding

extension View {

    /// The standard insets for one field group in the custom label-above-field layout (the add/edit
    /// bookmark forms and the tag summary row). One source for the spacing so every section breathes
    /// identically.
    func fieldSectionPadding() -> some View {
        padding(.horizontal, 20)
            .padding(.vertical, 14)
    }
}

#if DEBUG
    #Preview {
        VStack(alignment: .leading, spacing: 14) {
            FieldLabel(text: "URL")
            FieldLabel(text: "Title")
            FieldLabel(text: "Description")
        }
        .padding()
    }
#endif
