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

/// A form for saving a new bookmark, with metadata fetch and tag autocomplete.
struct AddBookmarkSheet: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var title = ""
    @State private var description = ""
    @State private var tagText = ""
    @State private var isFetching = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    // MARK: Properties

    /// The list's repository, so a saved bookmark appears in the list that presented this sheet.
    let repository: BookmarkRepository

    // MARK: Computed Properties

    private var parsedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            url.scheme != nil,
            url.host() != nil
        else {
            return nil
        }

        return url
    }

    private var tags: [String] {
        tagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var suggestions: [Tag] {
        let segment = currentTagSegment
        guard !segment.isEmpty else {
            return []
        }

        return environment.tagRepository
            .autocompleteTags(prefix: segment)
            .filter { !tags.dropLast().contains($0.name) }
    }

    private var currentTagSegment: String {
        let segment = tagText.split(separator: ",", omittingEmptySubsequences: false).last
        return segment.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        NavigationStack {
            Form {
                Section("URL") {
                    HStack {
                        TextField("https://example.com", text: $urlText)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        PasteButton(payloadType: String.self) { strings in
                            guard let pasted = strings.first else {
                                return
                            }

                            urlText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                    }

                    Button(action: fetchMetadata) {
                        if isFetching {
                            ProgressView()
                        } else {
                            Text("Fetch Metadata")
                        }
                    }
                    .disabled(parsedURL == nil || isFetching)
                }

                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Tags") {
                    TextField("comma, separated, tags", text: $tagText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !suggestions.isEmpty {
                        TagSuggestionView(suggestions: suggestions) { tag in
                            appendSuggestion(tag)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle("Add Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(parsedURL == nil || isSaving)
                }
            }
            .task {
                try? await environment.tagRepository.load()
            }
        }
    }

    // MARK: Functions

    private func fetchMetadata() {
        guard let url = parsedURL else {
            return
        }

        errorMessage = nil
        isFetching = true

        Task {
            defer { isFetching = false }

            do {
                let metadata = try await repository.fetchMetadata(for: url)
                if let fetchedTitle = metadata.title, !fetchedTitle.isEmpty {
                    title = fetchedTitle
                }

                if let fetchedDescription = metadata.description, !fetchedDescription.isEmpty {
                    description = fetchedDescription
                }
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }

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

    private func save() {
        guard let url = parsedURL else {
            return
        }

        errorMessage = nil
        isSaving = true

        Task {
            defer { isSaving = false }

            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            let input = CreateBookmarkInput(
                url: url,
                title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                tags: tags,
                fetchMetadata: true
            )

            do {
                _ = try await repository.create(input)
                environment.tagRepository.invalidateCache()
                dismiss()
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }
}
