// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import StashKit
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

    private let source: BookmarkListSource

    // MARK: Lifecycle

    /// A tag-filtered list (the iPad/macOS sidebar selection or the Tags tab); `nil` shows all.
    init(tag: String?) {
        source = .tag(tag)
    }

    /// A list backed by a Smart View's saved query, run live server-side.
    init(smartView: SmartView) {
        source = .smartView(smartView)
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Group {
            if let repository {
                BookmarkListContent(source: source, repository: repository)
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

// MARK: - BookmarkListSource

/// What a `BookmarkListView` shows: a tag filter (`nil` for all bookmarks) or a Smart View's query.
enum BookmarkListSource: Hashable {

    case tag(String?)
    case smartView(SmartView)
}

// MARK: - BookmarkListContent

/// The bookmark list bound to a specific repository instance.
private struct BookmarkListContent: View {

    // MARK: SwiftUI Properties

    @Environment(\.openURL) private var openURL
    @Environment(AppEnvironment.self) private var environment
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @FocusState private var isSearchFocused: Bool

    @State private var searchText = ""
    @State private var showArchived = false
    @State private var showingAddSheet = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    // MARK: Properties

    let source: BookmarkListSource
    let repository: BookmarkRepository

    // MARK: Computed Properties

    /// The Smart View backing this list, if any. When set the list runs that saved query and hides the
    /// search field, archived toggle, and add button (Smart Views are consumption-only on native).
    private var smartView: SmartView? {
        if case let .smartView(smartView) = source {
            return smartView
        }

        return nil
    }

    /// The tag filter for a non-Smart-View list; `nil` for all bookmarks.
    private var tag: String? {
        if case let .tag(tag) = source {
            return tag
        }

        return nil
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
        if let smartView {
            return smartView.name
        }

        if let tag {
            switch tag {
            case BookmarkListQuery.untaggedTag: return "Untagged"
            case BookmarkListQuery.todayTag: return "Today"
            case BookmarkListQuery.thisWeekTag: return "This Week"
            default: return tag
            }
        }

        return showArchived ? "Archived" : "Bookmarks"
    }

    /// Whether bookmark rows can be dragged onto a sidebar tag. Always on macOS; on iOS only at regular
    /// width (iPad), where the sidebar and list share the screen. Off on iPhone (compact), where the
    /// tags are a separate tab.
    private var isDragEnabled: Bool {
        #if os(iOS)
            horizontalSizeClass == .regular
        #else
            true
        #endif
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
        makeList()
            .overlay {
                if repository.bookmarks.isEmpty, !repository.isLoading {
                    makeEmptyState()
                }
            }
            .navigationTitle(navigationTitle)
            .modifier(
                SearchableIfNeeded(
                    isEnabled: smartView == nil,
                    text: $searchText,
                    isFocused: $isSearchFocused
                )
            )
            .onSubmit(of: .search) {
                reload()
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty {
                    reload()
                }
            }
            .onChange(of: source) {
                reload()
            }
            .onChange(of: showArchived) {
                reload()
            }
            .onSyncCompleted {
                repository.refresh()
            }
            .toolbar {
                if smartView == nil {
                    ToolbarItem(placement: .primaryAction) {
                        makeAddButton()
                    }
                }

                ToolbarItem(placement: optionsPlacement) {
                    makeOptionsMenu()
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
                    set: {
                        if !$0 {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: Content Methods

    private func makeList() -> some View {
        List {
            ForEach(repository.bookmarks) { bookmark in
                makeBookmarkRow(bookmark)
            }

            if repository.isLoading, !repository.bookmarks.isEmpty {
                makeLoadingRow()
            }
        }
    }

    private func makeBookmarkRow(_ bookmark: Bookmark) -> some View {
        NavigationLink {
            BookmarkDetailView(bookmark: bookmark, repository: repository)
        } label: {
            BookmarkRowView(bookmark: bookmark)
        }
        .draggableBookmark(bookmark, enabled: isDragEnabled)
        .onAppear {
            loadMoreIfNeeded(currentItem: bookmark)
        }
        .contextMenu {
            makeRowContextMenu(for: bookmark)
        }
    }

    private func makeLoadingRow() -> some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
    }

    private func makeAddButton() -> some View {
        Button {
            showingAddSheet = true
        } label: {
            Label("Add Bookmark", systemImage: "plus")
        }
        .keyboardShortcut("n", modifiers: .command)
    }

    private func makeOptionsMenu() -> some View {
        Menu {
            if smartView == nil {
                Toggle(isOn: $showArchived) {
                    Label("Show Archived", systemImage: "archivebox")
                }
            }

            Button {
                sync()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
        } label: {
            Label("Options", systemImage: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private func makeEmptyState() -> some View {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if smartView != nil {
            BookmarkEmptyState(
                symbol: "line.3.horizontal.decrease.circle",
                title: "No bookmarks match",
                message: "Try adjusting the conditions for this Smart View."
            )
        } else if !trimmedSearch.isEmpty {
            ContentUnavailableView.search(text: trimmedSearch)
        } else if let tag {
            makeTagEmptyState(for: tag)
        } else if showArchived {
            BookmarkEmptyState(
                symbol: "archivebox",
                title: "No archived bookmarks",
                message: "Bookmarks you archive will appear here."
            )
        } else {
            BookmarkEmptyState(
                symbol: "bookmark",
                title: "No bookmarks yet",
                message: "Save your first bookmark using the + button, the Share Extension, or the browser extension."
            )
        }
    }

    private func makeTagEmptyState(for tag: String) -> some View {
        switch tag {
        case BookmarkListQuery.untaggedTag:
            BookmarkEmptyState(
                symbol: "tag",
                title: "No untagged bookmarks",
                message: "Every bookmark here has at least one tag."
            )
        case BookmarkListQuery.todayTag:
            BookmarkEmptyState(
                symbol: "calendar",
                title: "Nothing saved today",
                message: "Bookmarks you save today will appear here."
            )
        case BookmarkListQuery.thisWeekTag:
            BookmarkEmptyState(
                symbol: "calendar",
                title: "Nothing saved this week",
                message: "Bookmarks you save this week will appear here."
            )
        case BookmarkListQuery.readLaterTag:
            BookmarkEmptyState(
                symbol: "book",
                title: "Nothing to read",
                message: "Bookmarks you mark to read later will appear here."
            )
        default:
            BookmarkEmptyState(
                symbol: "tag",
                title: "No bookmarks tagged \(tag.tagDisplayName)",
                message: "Bookmarks you tag with this will appear here."
            )
        }
    }

    @ViewBuilder
    private func makeRowContextMenu(for bookmark: Bookmark) -> some View {
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
            copyToPasteboard("[\(bookmark.title)](\(bookmark.url.absoluteString))")
        } label: {
            Label("Copy Markdown URL", systemImage: "doc.on.doc")
        }

        ShareLink(item: bookmark.url) {
            Label("Share…", systemImage: "square.and.arrow.up")
        }

        if bookmark.faviconDomain != nil {
            Button {
                refreshFavicon(bookmark)
            } label: {
                Label("Refresh Favicon", systemImage: "arrow.clockwise")
            }
        }

        Button {
            submitToWayback(bookmark)
        } label: {
            Label("Save to Wayback Machine", systemImage: "clock.arrow.circlepath")
        }

        if let waybackURL = bookmark.waybackURL {
            Button {
                openURL(waybackURL)
            } label: {
                Label("View on Wayback Machine", systemImage: "clock.arrow.circlepath")
            }
        }

        Button {
            setArchived(bookmark, archived: !bookmark.isArchived)
        } label: {
            Label(
                bookmark.isArchived ? "Unarchive" : "Archive",
                systemImage: bookmark.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }

        Button {
            setReadLater(bookmark, readLater: !bookmark.isReadLater)
        } label: {
            Label(
                bookmark.isReadLater ? "Mark as Read" : "Mark to Read Later",
                systemImage: bookmark.isReadLater ? "book.closed" : "bookmark.fill"
            )
        }

        Button(role: .destructive) {
            delete(bookmark)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: Functions

    private func reload() {
        Task { await load() }
    }

    private func sync() {
        Task { await environment.syncEngine.sync() }
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

    private func setReadLater(_ bookmark: Bookmark, readLater: Bool) {
        Task {
            do {
                _ = try await repository.setReadLater(id: bookmark.id, readLater: readLater)
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }

    private func refreshFavicon(_ bookmark: Bookmark) {
        Task {
            do {
                guard let domain = bookmark.faviconDomain else { return }

                try await repository.refreshFavicon(domain: domain)
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }

    private func submitToWayback(_ bookmark: Bookmark) {
        Task {
            do {
                try await repository.submitToWayback(id: bookmark.id)
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
            if let smartView {
                try await repository.load(smartView: smartView)
            } else {
                try await repository.load(query: query)
            }
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

// MARK: - SearchableIfNeeded

/// Applies the search field (and its ⌘F shortcut) only when enabled. A Smart View list omits it, since
/// its server-side query takes no free-text search term.
private struct SearchableIfNeeded: ViewModifier {

    // MARK: Properties

    let isEnabled: Bool

    // MARK: SwiftUI Properties

    @Binding var text: String

    var isFocused: FocusState<Bool>.Binding

    // MARK: Content Methods

    // MARK: Content

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .searchable(text: $text, prompt: "Search bookmarks")
                .searchInputStyle()
                .searchFocused(isFocused)
                .background {
                    Button("Find") {
                        isFocused.wrappedValue = true
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
                }
        } else {
            content
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
