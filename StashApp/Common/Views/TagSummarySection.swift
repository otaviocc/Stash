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

/// The "Tags" form section on the add and edit bookmark forms: a read-only summary of the selected
/// tags plus an "Add Tags" button that presents `TagPickerSheet`. Shared by both forms (and so by the
/// Share Extension) so tag editing is identical everywhere. It owns the picker presentation state; the
/// selection is a binding the picker updates live.
struct TagSummarySection: View {

    // MARK: SwiftUI Properties

    @Binding var selectedTags: [String]

    @State private var isShowingPicker = false

    // MARK: Properties

    let tagHierarchy: [TagNode]

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Section("Tags") {
            makeSummary()
            makeAddButton()
        }
    }

    // MARK: Content Methods

    @ViewBuilder
    private func makeSummary() -> some View {
        if selectedTags.isEmpty {
            Text("No tags")
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(selectedTags, id: \.self) { tag in
                        TagPill(name: tag)
                    }
                }
            }
        }
    }

    private func makeAddButton() -> some View {
        Button {
            isShowingPicker = true
        } label: {
            Label("Add Tags", systemImage: "tag")
        }
        .formButtonRowStyle()
        .sheet(isPresented: $isShowingPicker) {
            TagPickerSheet(
                selectedTags: $selectedTags,
                tagHierarchy: tagHierarchy
            ) {
                isShowingPicker = false
            }
        }
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var tags = ["swift", "swift/server"]
        Form {
            TagSummarySection(selectedTags: $tags, tagHierarchy: Tag.samples.hierarchy())
        }
        .formStyle(.grouped)
    }
#endif
