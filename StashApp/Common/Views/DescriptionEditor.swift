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
