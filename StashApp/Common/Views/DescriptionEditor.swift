// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - DescriptionEditor

/// The multiline description editor shared by the add and edit bookmark forms. A `TextEditor` (not a
/// `TextField`) so it scrolls with the mouse wheel on macOS and by touch on iOS when the text overflows.
/// It grows to fill the height its container offers (down to a usable minimum), letting the form absorb
/// the slack between the tags section and the action buttons. The borderless look matches the other
/// fields; the placeholder is drawn manually since `TextEditor` has none.
struct DescriptionEditor: View {

    // MARK: SwiftUI Properties

    @Binding var text: String

    // MARK: Properties

    var placeholder = "Description"

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .background(.clear)
        }
        .frame(minHeight: 120, maxHeight: .infinity)
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var text = ""
        DescriptionEditor(text: $text)
            .padding()
    }
#endif
