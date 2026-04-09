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
                    phase = .confirmation(bookmark)
                },
                onCancel: cancel
            )

        case let .confirmation(bookmark):
            ConfirmationView(
                bookmark: bookmark,
                onUndo: { undo(bookmark) },
                onDismiss: complete
            )
        }
    }

    private func makeLoadingView() -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Stash")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func makeSignedOutView() -> some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Sign In to Stash", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Open Stash to sign in before saving bookmarks.")
            }
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
            phase = .add(bookmark.url)
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

/// The post-save confirmation: a checkmark, the saved title, and an Undo button. Auto-dismisses
/// after three seconds unless Undo is tapped first (which cancels the timer via the view's removal).
private struct ConfirmationView: View {

    // MARK: Properties

    let bookmark: Bookmark
    let onUndo: () -> Void
    let onDismiss: () -> Void

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("Saved to Stash")
                    .font(.title2.bold())
                Text(bookmark.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            Button("Undo", role: .destructive, action: onUndo)
                .buttonStyle(.bordered)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else {
                return
            }

            onDismiss()
        }
    }
}

// MARK: - ExtensionCancellation

/// The error passed to `cancelRequest(withError:)` when the user dismisses the extension.
enum ExtensionCancellation: Error {

    case userCancelled
}
