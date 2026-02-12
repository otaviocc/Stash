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

// MARK: - TagInputSection

/// The shared "Tags" form section: a comma-separated text field plus tap-to-complete suggestion
/// chips drawn from the user's existing tags. Used by both the add and edit forms so they stay in
/// sync. `tags(from:)` is the single place tag text is parsed into a normalized list.
struct TagInputSection: View {

    // MARK: SwiftUI Properties

    @Binding var tagText: String

    // MARK: Properties

    let tagStore: any TagAutocompleting

    // MARK: Computed Properties

    private var suggestions: [Tag] {
        let segment = currentTagSegment
        guard !segment.isEmpty else {
            return []
        }

        return tagStore
            .autocompleteTags(prefix: segment)
            .filter { !Self.tags(from: tagText).dropLast().contains($0.name) }
    }

    private var currentTagSegment: String {
        let segment = tagText.split(separator: ",", omittingEmptySubsequences: false).last
        return segment.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Section("Tags") {
            TextField("comma, separated, tags", text: $tagText)
                .lowercasedFieldStyle()

            if !suggestions.isEmpty {
                TagSuggestionView(suggestions: suggestions) { tag in
                    appendSuggestion(tag)
                }
            }
        }
    }

    // MARK: Static Functions

    /// Parses comma-separated tag text into a trimmed, non-empty list — the payload the add and edit
    /// forms send when saving.
    static func tags(from text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Functions

    private func appendSuggestion(_ tag: Tag) {
        var components = tagText.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        if components.isEmpty {
            components = [tag.name]
        } else {
            components[components.count - 1] = tag.name
        }

        tagText = components.joined(separator: ", ") + ", "
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var text = "swift, "
        Form {
            TagInputSection(tagText: $text, tagStore: PreviewTagStore())
        }
    }
#endif
