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

// MARK: - BookmarkDetailView

/// A bookmark detail view with edit, archive, and delete actions.
///
/// Shared between the iOS push presentation and the macOS inspector panel. It keeps the displayed
/// bookmark in local state so an in-place edit or archive is reflected immediately, and reports a
/// deletion through `onDeleted` so the host can pop (iOS) or clear its selection (macOS).
struct BookmarkDetailView: View {

    // MARK: SwiftUI Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var bookmark: Bookmark
    @State private var editingBookmark: Bookmark?
    @State private var showingDeleteConfirmation = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    // MARK: Properties

    let repository: BookmarkRepository
    let onDeleted: () -> Void

    // MARK: Lifecycle

    init(
        bookmark: Bookmark,
        repository: BookmarkRepository,
        onDeleted: @escaping () -> Void = {}
    ) {
        _bookmark = State(initialValue: bookmark)
        self.repository = repository
        self.onDeleted = onDeleted
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Form {
            makeHeaderSection()
            makeDescriptionSection()
            makeTagsSection()
            makeMetadataSection()
            makeActionsSection()
            makeDeleteSection()
            makeErrorMessage()
        }
        .formStyle(.grouped)
        .navigationTitle("Bookmark")
        .inlineNavigationTitleStyle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                makeEditButton()
            }
        }
        .sheet(item: $editingBookmark) { item in
            EditBookmarkView(bookmark: item, repository: repository) { updated in
                bookmark = updated
            }
        }
        .confirmationDialog(
            "Delete this bookmark?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(bookmark.title)
        }
    }

    // MARK: Content Methods

    private func makeHeaderSection() -> some View {
        Section {
            HStack(spacing: 8) {
                FaviconView(domain: bookmark.faviconDomain)
                Text(bookmark.title)
                    .font(.headline)
            }

            Link(destination: bookmark.url) {
                Text(bookmark.url.absoluteString)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func makeDescriptionSection() -> some View {
        if let description = bookmark.description, !description.isEmpty {
            Section("Description") {
                Text(description)
            }
        }
    }

    @ViewBuilder
    private func makeTagsSection() -> some View {
        if !bookmark.tags.isEmpty {
            Section("Tags") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(bookmark.tags, id: \.self) { tag in
                            TagPill(name: tag)
                        }
                    }
                }
            }
        }
    }

    private func makeMetadataSection() -> some View {
        Section {
            LabeledContent("Added", value: bookmark.createdAt, format: .dateTime.day().month().year())
            if bookmark.isArchived {
                LabeledContent("Status", value: "Archived")
            }
        }
    }

    private func makeActionsSection() -> some View {
        Section {
            Button {
                openURL(bookmark.url)
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
            .formButtonRowStyle()

            Button {
                copyToPasteboard(bookmark.url.absoluteString)
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }
            .formButtonRowStyle()

            Button {
                copyToPasteboard("[\(bookmark.title)](\(bookmark.url.absoluteString))")
            } label: {
                Label("Copy Markdown URL", systemImage: "doc.on.doc")
            }
            .formButtonRowStyle()

            Button(action: toggleArchived) {
                Label(
                    bookmark.isArchived ? "Unarchive" : "Archive",
                    systemImage: bookmark.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }
            .formButtonRowStyle()
            .disabled(isWorking)
        }
    }

    private func makeDeleteSection() -> some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .formButtonRowStyle(isDestructive: true)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(isWorking)
        }
    }

    @ViewBuilder
    private func makeErrorMessage() -> some View {
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .font(.footnote)
        }
    }

    private func makeEditButton() -> some View {
        Button {
            editingBookmark = bookmark
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(isWorking)
    }

    // MARK: Functions

    private func toggleArchived() {
        errorMessage = nil
        isWorking = true

        Task {
            defer { isWorking = false }

            do {
                bookmark = try await repository.setArchived(id: bookmark.id, archived: !bookmark.isArchived)
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }

    private func delete() {
        errorMessage = nil
        isWorking = true

        Task {
            defer { isWorking = false }

            do {
                try await repository.delete(id: bookmark.id)
                onDeleted()
                dismiss()
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            BookmarkDetailView(bookmark: .sample, repository: AppEnvironment.preview.makeBookmarkRepository())
        }
        .environment(AppEnvironment.preview)
        .environment(AppSettings.preview)
    }
#endif
