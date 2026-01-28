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

/// The main bookmark list: searchable, paginated, with a tag filter and an archived toggle.
struct BookmarkListView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment

    @State private var searchText = ""
    @State private var showArchived = false
    @State private var showingAddSheet = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    // MARK: Properties

    /// An externally-supplied tag filter (the iPad sidebar selection); `nil` shows all bookmarks.
    let tag: String?

    // MARK: Computed Properties

    private var repository: BookmarkRepository {
        environment.bookmarkRepository
    }

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
            return tag
        }

        return showArchived ? "Archived" : "Bookmarks"
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        List {
            ForEach(repository.bookmarks) { bookmark in
                NavigationLink(value: bookmark) {
                    BookmarkRowView(bookmark: bookmark)
                }
                .onAppear {
                    loadMoreIfNeeded(currentItem: bookmark)
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
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text("Tap + to save your first bookmark.")
                )
            }
        }
        .navigationTitle(navigationTitle)
        .navigationDestination(for: Bookmark.self) { bookmark in
            BookmarkDetailView(bookmark: bookmark)
        }
        .searchable(text: $searchText, prompt: "Search bookmarks")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
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
            }

            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Toggle(isOn: $showArchived) {
                        Label("Show Archived", systemImage: "archivebox")
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddBookmarkSheet()
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

    // MARK: Functions

    private func reload() {
        Task { await load() }
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
