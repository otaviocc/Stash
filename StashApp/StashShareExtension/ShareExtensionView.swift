// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - ShareExtensionView

/// The root view of the Share Extension.
///
/// Drives a small state machine: it bootstraps (reads the shared tokens, resolves the shared URL),
/// then shows either a "sign in first" message (no server or no tokens), the shared add-bookmark
/// form, or — after a save — a confirmation with an undo option that auto-dismisses. All exits go
/// back to the host through the `NSExtensionContext`.
struct ShareExtensionView: View {

    // MARK: Nested Types

    /// The screens the extension can show. `add` carries the resolved URL; `confirmation` the saved
    /// bookmark so it can be undone.
    private enum Phase {

        case loading
        case signedOut
        case add(URL)
        case restoring(Bookmark)
        case confirmation(Bookmark)
    }

    // MARK: SwiftUI Properties

    @State private var phase: Phase = .loading

    // MARK: Properties

    let extensionContext: NSExtensionContext

    private let session: ExtensionSession
    private let bookmarkRepository: ExtensionBookmarkRepository
    private let tagRepository: ExtensionTagRepository

    // MARK: Lifecycle

    init(extensionContext: NSExtensionContext) {
        self.extensionContext = extensionContext
        let session = ExtensionSession()
        self.session = session
        bookmarkRepository = ExtensionBookmarkRepository(session: session)
        tagRepository = ExtensionTagRepository(session: session)
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        makeContent()
            .task {
                await bootstrap()
            }
    }

    // MARK: Content Methods

    @ViewBuilder
    private func makeContent() -> some View {
        switch phase {
        case .loading:
            makeLoadingView()

        case .signedOut:
            makeSignedOutView()

        case let .add(url):
            AddBookmarkView(
                initialURL: url.absoluteString,
                isURLEditable: false,
                autoFetchOnAppear: true,
                usesInlineActionBar: true,
                bookmarkStore: bookmarkRepository,
                tagStore: tagRepository,
                onSaved: { bookmark in
                    withAnimation {
                        phase = .confirmation(bookmark)
                    }
                },
                onCancel: cancel
            )

        case let .restoring(bookmark):
            AddBookmarkView(
                restoring: bookmark,
                isURLEditable: false,
                autoFetchOnAppear: false,
                usesInlineActionBar: true,
                bookmarkStore: bookmarkRepository,
                tagStore: tagRepository,
                onSaved: { bookmark in
                    withAnimation {
                        phase = .confirmation(bookmark)
                    }
                },
                onCancel: cancel
            )

        case let .confirmation(bookmark):
            ConfirmationView(
                bookmark: bookmark,
                onUndo: { undo(bookmark) },
                onDismiss: complete
            )
            .transition(.opacity)
        }
    }

    private func makeLoadingView() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            ProgressView()
                .tint(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func makeSignedOutView() -> some View {
        NavigationStack {
            BookmarkEmptyState(
                symbol: "person.crop.circle",
                title: "Sign in to Stash",
                message: "Open the Stash app to sign in, then share this page again."
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
            }
        }
    }

    // MARK: Functions

    private func bootstrap() async {
        guard session.isSignedIn else {
            phase = .signedOut

            return
        }

        let items = extensionContext.inputItems.compactMap { $0 as? NSExtensionItem }
        guard let url = await SharedItemLoader.loadURL(from: items) else {
            phase = .signedOut

            return
        }

        phase = .add(url)
    }

    private func undo(_ bookmark: Bookmark) {
        Task {
            try? await bookmarkRepository.deleteBookmark(id: bookmark.id)

            withAnimation {
                phase = .restoring(bookmark)
            }
        }
    }

    private func complete() {
        extensionContext.completeRequest(returningItems: [])
    }

    private func cancel() {
        extensionContext.cancelRequest(withError: ExtensionCancellation.userCancelled)
    }
}

// MARK: - ConfirmationView

/// The post-save confirmation: a checkmark, "Saved to Stash", the saved bookmark's domain, its tags
/// (read-only), and an unobtrusive Undo button. Auto-dismisses after 1.5 seconds unless Undo is tapped
/// first (which cancels the timer via the view's removal).
private struct ConfirmationView: View {

    // MARK: Properties

    let bookmark: Bookmark
    let onUndo: () -> Void
    let onDismiss: () -> Void

    // MARK: Computed Properties

    private var domain: String {
        Bookmark.faviconDomain(for: bookmark.url) ?? bookmark.hostname
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Saved to Stash")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text(domain)
                .font(.body)
                .foregroundStyle(.secondary)

            makeTags()

            Button("Undo", action: onUndo)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else {
                return
            }

            onDismiss()
        }
    }

    // MARK: Content Methods

    @ViewBuilder
    private func makeTags() -> some View {
        if !bookmark.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(bookmark.tags, id: \.self) { tag in
                        SelectedTagChip(tag: tag, showsDismissButton: false) {}
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - MissingExtensionContextView

/// Shown by the host view controllers when `extensionContext` is unexpectedly `nil`, so the user has
/// an explicit way to close the extension instead of a permanently blank, stuck screen.
struct MissingExtensionContextView: View {

    // MARK: Properties

    let onClose: () -> Void

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        NavigationStack {
            BookmarkEmptyState(
                symbol: "exclamationmark.triangle",
                title: "Something Went Wrong",
                message: "This share sheet couldn't be set up. Please close it and try again."
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }
}

// MARK: - ExtensionCancellation

/// The error passed to `cancelRequest(withError:)` when the user dismisses the extension.
enum ExtensionCancellation: Error {

    case userCancelled
}
