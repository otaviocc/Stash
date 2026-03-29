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

// MARK: - AddBookmarkView

/// The shared add-bookmark form, used by both the main app's `AddBookmarkSheet` and the Share
/// Extension's `ShareExtensionView`.
///
/// The form owns its own field state and surfaces metadata fetch, comma-separated tag input, and
/// tag autocomplete. Its data dependencies are the narrow `BookmarkCreating`/`TagAutocompleting`
/// protocols, so it does not know whether it is talking to the app's repositories or the extension's
/// lightweight ones. Saving and cancelling are reported through the `onSaved`/`onCancel` callbacks
/// rather than handled here, so the host decides whether to dismiss (app) or advance to a
/// confirmation screen (extension).
///
/// When `isURLEditable` is `true` (the app) the URL field is editable with a paste button and an
/// explicit "Fetch Metadata" button. When `false` (the extension) the URL arrives from the share
/// sheet, is shown read-only, and metadata is fetched automatically on appear.
struct AddBookmarkView: View {

    // MARK: SwiftUI Properties

    @State private var urlText: String
    @State private var title = ""
    @State private var description = ""
    @State private var tagText = ""
    @State private var isFetching = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    // MARK: Properties

    let bookmarkStore: any BookmarkCreating
    let tagStore: any TagAutocompleting
    let isURLEditable: Bool
    let autoFetchOnAppear: Bool
    let usesInlineActionBar: Bool
    let onSaved: (Bookmark) -> Void
    let onCancel: () -> Void

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

    // MARK: Lifecycle

    init(
        initialURL: String = "",
        isURLEditable: Bool,
        autoFetchOnAppear: Bool,
        usesInlineActionBar: Bool = false,
        bookmarkStore: any BookmarkCreating,
        tagStore: any TagAutocompleting,
        onSaved: @escaping (Bookmark) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _urlText = State(initialValue: initialURL)
        self.isURLEditable = isURLEditable
        self.autoFetchOnAppear = autoFetchOnAppear
        self.usesInlineActionBar = usesInlineActionBar
        self.bookmarkStore = bookmarkStore
        self.tagStore = tagStore
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        NavigationStack {
            Form {
                urlSection

                Section("Details") {
                    TextField("Title", text: $title)
                        .labelsHidden()
                    TextField("Description", text: $description, axis: .vertical)
                        .labelsHidden()
                        .lineLimit(2...5)
                }

                TagInputSection(tagText: $tagText, tagStore: tagStore)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Bookmark")
            .inlineNavigationTitleStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(parsedURL == nil || isSaving)
                }
            }
            .task {
                try? await tagStore.load()

                if autoFetchOnAppear {
                    fetchMetadata()
                }
            }
            #if os(macOS)
            .safeAreaInset(edge: .bottom) {
                if usesInlineActionBar {
                    macActionBar
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    #if os(macOS)
        private var macActionBar: some View {
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsedURL == nil || isSaving)
            }
            .padding()
            .background(.bar)
        }
    #endif

    private var urlSection: some View {
        Section("URL") {
            if isURLEditable {
                HStack {
                    TextField("https://example.com", text: $urlText)
                        .urlFieldStyle()
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
            } else {
                Text(urlText)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
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
                let metadata = try await bookmarkStore.fetchMetadata(for: url)
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
                tags: TagInputSection.tags(from: tagText),
                fetchMetadata: true
            )

            do {
                let bookmark = try await bookmarkStore.create(input)
                onSaved(bookmark)
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }
}

#if DEBUG
    #Preview("Add — editable URL") {
        AddBookmarkView(
            isURLEditable: true,
            autoFetchOnAppear: false,
            bookmarkStore: PreviewBookmarkStore(),
            tagStore: PreviewTagStore(),
            onSaved: { _ in },
            onCancel: {}
        )
    }

    #Preview("Add — locked URL (share sheet)") {
        AddBookmarkView(
            initialURL: "https://swift.org",
            isURLEditable: false,
            autoFetchOnAppear: false,
            bookmarkStore: PreviewBookmarkStore(),
            tagStore: PreviewTagStore(),
            onSaved: { _ in },
            onCancel: {}
        )
    }
#endif
