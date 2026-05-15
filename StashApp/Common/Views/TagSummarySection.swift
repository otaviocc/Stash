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

/// The "Tags" field on the add and edit bookmark forms: a `FieldLabel`, a read-only summary of the
/// selected tags (up to three `TagPill` chips plus a `+N` overflow), and a trailing "Add Tags" button
/// that presents `TagPickerSheet`. Shared by both forms (and so by the Share Extension) so tag editing
/// is identical everywhere, and styled to match the custom label-above-field layout. It owns the picker
/// presentation state; the selection is a binding the picker updates live.
struct TagSummarySection: View {

    // MARK: SwiftUI Properties

    @Binding var selectedTags: [String]

    @State private var isShowingPicker = false

    // MARK: Properties

    let tagHierarchy: [TagNode]

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Tags")

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                makeSummary()
                Spacer(minLength: 12)
                makeAddButton()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
            HStack(spacing: 6) {
                ForEach(selectedTags.prefix(3), id: \.self) { tag in
                    TagPill(name: tag)
                }

                if selectedTags.count > 3 {
                    Text("+\(selectedTags.count - 3)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
        }
    }

    private func makeAddButton() -> some View {
        Button {
            isShowingPicker = true
        } label: {
            HStack(spacing: 4) {
                Text("Add Tags")
                Image(systemName: "arrow.right")
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var tags = ["swift", "swift/server"]
        TagSummarySection(selectedTags: $tags, tagHierarchy: Tag.samples.hierarchy())
    }
#endif
