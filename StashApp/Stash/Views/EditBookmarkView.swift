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

// MARK: - EditBookmarkView

/// An edit sheet for a bookmark's title, description, and tags. The URL is fixed — editing it would
/// reintroduce duplicate-URL handling (the same choice the web frontend makes). Tags use the same
/// `TagPickerSheet` as the add form.
struct EditBookmarkView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var description: String
    @State private var selectedTags: [String]
    @State private var isSaving = false
    @State private var errorMessage: String?

    // MARK: Properties

    let bookmark: Bookmark
    let repository: BookmarkRepository
    let onSaved: (Bookmark) -> Void

    // MARK: Lifecycle

    init(
        bookmark: Bookmark,
        repository: BookmarkRepository,
        onSaved: @escaping (Bookmark) -> Void
    ) {
        self.bookmark = bookmark
        self.repository = repository
        self.onSaved = onSaved
        _title = State(initialValue: bookmark.title)
        _description = State(initialValue: bookmark.description ?? "")
        _selectedTags = State(initialValue: bookmark.tags)
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    makeURLSection()
                    Divider().opacity(0.3)
                    makeTitleSection()
                    Divider().opacity(0.3)
                    makeDescriptionSection()
                    Divider().opacity(0.3)

                    TagSummarySection(
                        selectedTags: $selectedTags,
                        tagHierarchy: environment.tagRepository.tagHierarchy
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Bookmark")
            .inlineNavigationTitleStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    makeSaveButton()
                }
            }
            .task {
                try? await environment.tagRepository.load()
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    // MARK: Content Methods

    @ViewBuilder
    private func makeSaveButton() -> some View {
        if isSaving {
            ProgressView()
                .controlSize(.small)
        } else {
            Button("Save", action: save)
        }
    }

    private func makeURLSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "URL")
            Text(bookmark.url.absoluteString)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            makeInlineError()
        }
        .fieldSectionPadding()
    }

    private func makeTitleSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Title")
            TextField("Title", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
        }
        .fieldSectionPadding()
    }

    private func makeDescriptionSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Description")
            TextField("Description", text: $description, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
        }
        .fieldSectionPadding()
    }

    @ViewBuilder
    private func makeInlineError() -> some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Functions

    private func save() {
        errorMessage = nil
        isSaving = true

        Task {
            defer { isSaving = false }

            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                let updated = try await repository.update(
                    id: bookmark.id,
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    tags: selectedTags
                )
                environment.tagRepository.refresh()
                onSaved(updated)
                dismiss()
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }
}

#if DEBUG
    #Preview {
        EditBookmarkView(bookmark: .sample, repository: AppEnvironment.preview.makeBookmarkRepository()) { _ in }
            .environment(AppEnvironment.preview)
    }
#endif
