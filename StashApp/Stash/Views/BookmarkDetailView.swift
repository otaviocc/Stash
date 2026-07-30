// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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
            HeaderSectionView(bookmark: bookmark)
            DescriptionSectionView(description: bookmark.description)
            TagsSectionView(tags: bookmark.tags)
            MetadataSectionView(
                createdAt: bookmark.createdAt,
                isArchived: bookmark.isArchived,
                isReadLater: bookmark.isReadLater
            )
            ActionsSectionView(
                bookmark: bookmark,
                isWorking: isWorking,
                onRefreshFavicon: refreshFavicon,
                onSubmitToWayback: submitToWayback,
                onToggleArchived: toggleArchived,
                onToggleReadLater: toggleReadLater
            )
            DeleteSectionView(isWorking: isWorking) {
                showingDeleteConfirmation = true
            }
            ErrorMessageView(message: errorMessage)
        }
        .formStyle(.grouped)
        .navigationTitle("Bookmark")
        .inlineNavigationTitleStyle()
        .background {
            makeEscapeShortcut()
        }
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

    private func makeEscapeShortcut() -> some View {
        Button("Back") { dismiss() }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .accessibilityHidden(true)
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

    private func toggleReadLater() {
        errorMessage = nil
        isWorking = true

        Task {
            defer { isWorking = false }

            do {
                bookmark = try await repository.setReadLater(id: bookmark.id, readLater: !bookmark.isReadLater)
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }

    private func refreshFavicon() {
        errorMessage = nil
        isWorking = true

        Task {
            defer { isWorking = false }

            do {
                guard let domain = bookmark.faviconDomain else { return }

                try await repository.refreshFavicon(domain: domain)
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }

    private func submitToWayback() {
        errorMessage = nil
        isWorking = true

        Task {
            defer { isWorking = false }

            do {
                try await repository.submitToWayback(id: bookmark.id)
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

// MARK: - HeaderSectionView

/// The title, favicon/domain, pending-sync badge, and link. Extracted so toggling `isWorking`
/// elsewhere in `BookmarkDetailView` doesn't re-diff this section too.
private struct HeaderSectionView: View {

    // MARK: Properties

    let bookmark: Bookmark

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bookmark.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if bookmark.isPendingSync || bookmark.hasSyncError {
                        PendingSyncBadge(failed: bookmark.hasSyncError)
                    }
                }

                HStack(spacing: 6) {
                    FaviconView(domain: bookmark.faviconDomain)
                    Text(bookmark.faviconDomain ?? bookmark.hostname)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Link(destination: bookmark.url) {
                    Text(bookmark.url.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.tint)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - DescriptionSectionView

/// The description section, hidden when empty. Extracted so it doesn't share an invalidation
/// boundary with the actions below it.
private struct DescriptionSectionView: View {

    // MARK: Properties

    let description: String?

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        if let description, !description.isEmpty {
            Section("Description") {
                Text(description)
            }
        }
    }
}

// MARK: - TagsSectionView

/// The tag chips, hidden when empty. Extracted so it doesn't share an invalidation boundary with the
/// actions below it.
private struct TagsSectionView: View {

    // MARK: Properties

    let tags: [String]

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        if !tags.isEmpty {
            Section("Tags") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            TagPill(name: tag)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - MetadataSectionView

/// The "Added"/status row. Extracted so it doesn't share an invalidation boundary with the actions
/// below it.
private struct MetadataSectionView: View {

    // MARK: Properties

    let createdAt: Date
    let isArchived: Bool
    let isReadLater: Bool

    // MARK: Computed Properties

    private var statuses: [String] {
        [
            isArchived ? "Archived" : nil,
            isReadLater ? "To Read" : nil
        ].compactMap(\.self)
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Section {
            LabeledContent("Added", value: createdAt, format: .dateTime.day().month().year())

            if !statuses.isEmpty {
                LabeledContent("Status", value: statuses.joined(separator: ", "))
            }
        }
    }
}

// MARK: - ActionsSectionView

/// The open/copy/share/favicon/wayback/archive/read-later actions. Extracted so toggling `isWorking`
/// while one of these actions runs only re-diffs this section, not the header/description/tags/
/// metadata sections above it.
private struct ActionsSectionView: View {

    // MARK: SwiftUI Properties

    @Environment(\.openURL) private var openURL

    // MARK: Properties

    let bookmark: Bookmark
    let isWorking: Bool
    let onRefreshFavicon: () -> Void
    let onSubmitToWayback: () -> Void
    let onToggleArchived: () -> Void
    let onToggleReadLater: () -> Void

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
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

            ShareLink(item: bookmark.url) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            .formButtonRowStyle()

            if bookmark.faviconDomain != nil {
                Button(action: onRefreshFavicon) {
                    Label("Refresh Favicon", systemImage: "arrow.clockwise")
                }
                .formButtonRowStyle()
                .disabled(isWorking)
            }

            Button(action: onSubmitToWayback) {
                Label("Save to Wayback Machine", systemImage: "clock.arrow.circlepath")
            }
            .formButtonRowStyle()
            .disabled(isWorking)

            if let waybackURL = bookmark.waybackURL {
                Button {
                    openURL(waybackURL)
                } label: {
                    Label("View on Wayback Machine", systemImage: "clock.arrow.circlepath")
                }
                .formButtonRowStyle()
            }

            Button(action: onToggleArchived) {
                Label(
                    bookmark.isArchived ? "Unarchive" : "Archive",
                    systemImage: bookmark.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }
            .formButtonRowStyle()
            .disabled(isWorking)

            Button(action: onToggleReadLater) {
                Label(
                    bookmark.isReadLater ? "Mark as Read" : "Mark to Read Later",
                    systemImage: bookmark.isReadLater ? "book.closed" : "bookmark.fill"
                )
            }
            .formButtonRowStyle()
            .disabled(isWorking)
        }
    }
}

// MARK: - DeleteSectionView

/// The destructive delete action. Extracted so toggling `isWorking` only re-diffs this section, not
/// the sections above it.
private struct DeleteSectionView: View {

    // MARK: Properties

    let isWorking: Bool
    let onDelete: () -> Void

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Section {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .formButtonRowStyle(isDestructive: true)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(isWorking)
        }
    }
}

// MARK: - ErrorMessageView

/// The inline error message, hidden when there is none.
private struct ErrorMessageView: View {

    // MARK: Properties

    let message: String?

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        if let message {
            Text(message)
                .foregroundStyle(.red)
                .font(.footnote)
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
