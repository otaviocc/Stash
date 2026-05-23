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

// MARK: - TagSummarySection

/// The "Tags" field on the add and edit bookmark forms: a `FieldLabel`, a horizontally scrollable
/// strip of removable `SelectedTagChip`s (the same chip used in `TagPickerSheet`), and a trailing
/// "Add Tags" button that presents the picker. Tapping a chip's `×` removes that tag from the binding
/// directly, without reopening the picker. Shared by both forms (and so by the Share Extension) so tag
/// editing is identical everywhere, and styled to match the custom label-above-field layout. It owns
/// the picker presentation state; the selection is a binding the picker updates live.
struct TagSummarySection: View {

    // MARK: SwiftUI Properties

    @Binding var selectedTags: [String]

    @State private var isShowingPicker = false

    // MARK: Properties

    let tagHierarchy: [TagNode]

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: "Tags")

            HStack(spacing: 0) {
                makeSummary()
                Spacer(minLength: 12)
                makeAddButton()
            }
        }
        .fieldSectionPadding()
        .sheet(isPresented: $isShowingPicker) {
            TagPickerSheet(
                selectedTags: $selectedTags,
                tagHierarchy: tagHierarchy
            ) {
                isShowingPicker = false
            }
        }
    }

    // MARK: Content Methods

    @ViewBuilder
    private func makeSummary() -> some View {
        if !selectedTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedTags, id: \.self) { tag in
                        SelectedTagChip(tag: tag) {
                            selectedTags.removeAll { $0 == tag }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func makeAddButton() -> some View {
        Button("Add Tags") {
            isShowingPicker = true
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .font(.body)
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var tags = ["swift", "swift/server"]
        TagSummarySection(selectedTags: $tags, tagHierarchy: Tag.samples.hierarchy())
    }
#endif
