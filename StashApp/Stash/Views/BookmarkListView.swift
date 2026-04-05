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

// MARK: - BookmarkListView

/// The main bookmark list: searchable, paginated, with a tag filter and an archived toggle.
///
/// Each instance owns its own `BookmarkRepository` so the Bookmarks tab, a Tags-tab drill-in, and the
/// iPad detail column keep independent contents — browsing a tag in one does not change the others.
struct BookmarkListView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment
    @State private var repository: BookmarkRepository?

    // MARK: Properties

    /// An externally-supplied tag filter (the iPad sidebar selection / Tags tab); `nil` shows all.
    let tag: String?

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Group {
            if let repository {
                BookmarkListContent(tag: tag, repository: repository)
            } else {
                ProgressView()
            }
        }
        .task {
            if repository == nil {
                repository = environment.makeBookmarkRepository()
            }
        }
    }
}

// MARK: - BookmarkListContent

/// The bookmark list bound to a specific repository instance.
private struct BookmarkListContent: View {

    // MARK: SwiftUI Properties

    @Environment(\.openURL) private var openURL

    @FocusState private var isSearchFocused: Bool

    @State private var searchText = ""
    @State private var showArchived = false
    @State private var showingAddSheet = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    // MARK: Properties

    let tag: String?
    let repository: BookmarkRepository

    // MARK: Computed Properties

    private var query: BookmarkQuery {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return BookmarkQuery(
            searchQuery: trimmed.isEmpty ? nil : trimmed,
            tag: tag,
            archived: showArchived
        )
    }

    private var navigationTitle: String {
        if let tag {
            switch tag {
            case Bookmark.untaggedSentinel: return "Untagged"
            case Bookmark.todaySentinel: return "Today"
            case Bookmark.thisWeekSentinel: return "This Week"
            default: return tag
            }
        }

        return showArchived ? "Archived" : "Bookmarks"
    }

    private var optionsPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .topBarLeading
        #else
            .automatic
        #endif
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        List {
            ForEach(repository.bookmarks) { bookmark in
                NavigationLink {
                    BookmarkDetailView(bookmark: bookmark, repository: repository)
                } label: {
                    BookmarkRowView(bookmark: bookmark)
                }
                .onAppear {
                    loadMoreIfNeeded(currentItem: bookmark)
                }
                .contextMenu {
                    rowContextMenu(for: bookmark)
                }
            }

            if repository.isLoading, !repository.bookmarks.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .overlay {
            if repository.bookmarks.isEmpty, !repository.isLoading {
                emptyState
            }
        }
        .navigationTitle(navigationTitle)
        .searchable(text: $searchText, prompt: "Search bookmarks")
        .searchInputStyle()
        .searchFocused($isSearchFocused)
        .background {
            Button("Find") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .onSubmit(of: .search) {
            reload()
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                reload()
            }
        }
        .onChange(of: tag) {
            reload()
        }
        .onChange(of: showArchived) {
            reload()
        }
        .refreshable {
            await load()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Bookmark", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            ToolbarItem(placement: optionsPlacement) {
                Menu {
                    Toggle(isOn: $showArchived) {
                        Label("Show Archived", systemImage: "archivebox")
                    }

                    Button {
                        reload()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddBookmarkSheet(repository: repository)
        }
        .task {
            guard !didLoad else {
                return
            }

            didLoad = true
            await load()
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedSearch.isEmpty {
            ContentUnavailableView.search(text: trimmedSearch)
        } else if let tag {
            ContentUnavailableView(
                "No Bookmarks",
                systemImage: "bookmark",
                description: Text(emptyDescription(for: tag))
            )
        } else if showArchived {
            ContentUnavailableView(
                "No Archived Bookmarks",
                systemImage: "archivebox",
                description: Text("Bookmarks you archive will appear here.")
            )
        } else {
            ContentUnavailableView(
                "No Bookmarks",
                systemImage: "bookmark",
                description: Text("Tap + to save your first bookmark.")
            )
        }
    }

    // MARK: Content Methods

    @ViewBuilder
    private func rowContextMenu(for bookmark: Bookmark) -> some View {
        Button {
            openURL(bookmark.url)
        } label: {
            Label("Open in Browser", systemImage: "safari")
        }

        Button {
            copyToPasteboard(bookmark.url.absoluteString)
        } label: {
            Label("Copy URL", systemImage: "doc.on.doc")
        }

        Button {
            setArchived(bookmark, archived: !bookmark.isArchived)
        } label: {
            Label(
                bookmark.isArchived ? "Unarchive" : "Archive",
                systemImage: bookmark.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }

        Button(role: .destructive) {
            delete(bookmark)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: Functions

    private func emptyDescription(for tag: String) -> String {
        switch tag {
        case Bookmark.untaggedSentinel: "Every bookmark here has at least one tag."
        case Bookmark.todaySentinel: "No bookmarks were saved today."
        case Bookmark.thisWeekSentinel: "No bookmarks were saved this week."
        default: "No bookmarks are tagged this way."
        }
    }

    private func reload() {
        Task { await load() }
    }

    private func setArchived(_ bookmark: Bookmark, archived: Bool) {
        Task {
            do {
                _ = try await repository.setArchived(id: bookmark.id, archived: archived)
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }

    private func delete(_ bookmark: Bookmark) {
        Task {
            do {
                try await repository.delete(id: bookmark.id)
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }

    private func load() async {
        do {
            try await repository.load(query: query)
        } catch {
            errorMessage = error.stashUserMessage
        }
    }

    private func loadMoreIfNeeded(currentItem: Bookmark) {
        guard currentItem.id == repository.bookmarks.last?.id, repository.hasMore else {
            return
        }

        Task {
            do {
                try await repository.loadNextPage()
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            BookmarkListView(tag: nil)
        }
        .environment(AppEnvironment.preview)
        .environment(AppSettings.preview)
    }
#endif
