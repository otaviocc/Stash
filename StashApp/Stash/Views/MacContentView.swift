// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

#if os(macOS)
    import StashKit
    import SwiftUI

    // MARK: - MacContentView

    /// The authenticated macOS shell: a `NavigationSplitView` whose sidebar (All Bookmarks, Untagged,
    /// and the tag list) filters the bookmark list in the detail column. Selecting a bookmark pushes its
    /// detail within the detail column's navigation stack, the same shared `BookmarkListView` /
    /// `BookmarkDetailView` the iPad layout uses.
    struct MacContentView: View {

        // MARK: SwiftUI Properties

        @Environment(AppEnvironment.self) private var environment

        @State private var selection: MacSidebarItem? = .all

        // MARK: Content Properties

        // MARK: Content

        var body: some View {
            makeSplit()
                .macBrowserChooser()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !environment.connectivityMonitor.isOnline {
                        OfflineBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.default, value: environment.connectivityMonitor.isOnline)
        }

        // MARK: Content Methods

        private func makeSplit() -> some View {
            NavigationSplitView {
                List(selection: $selection) {
                    makeViewsSection()
                    makeSmartViewsSection()
                    makeTagsSection()
                }
                .navigationTitle("Stash")
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                .task {
                    try? await environment.tagRepository.load()
                }
                .task {
                    try? await environment.smartViewRepository.load()
                }
                .onSyncCompleted {
                    environment.tagRepository.refresh()
                }
            } detail: {
                NavigationStack {
                    makeDetail()
                }
                .id(selection)
            }
        }

        private func makeViewsSection() -> some View {
            Section("Views") {
                Label("All Bookmarks", systemImage: "bookmark")
                    .tag(MacSidebarItem.all)
                Label("Untagged", systemImage: "tag.slash")
                    .tag(MacSidebarItem.untagged)
                Label("Today", systemImage: "sun.max")
                    .tag(MacSidebarItem.today)
                Label("This Week", systemImage: "calendar")
                    .tag(MacSidebarItem.thisWeek)
            }
        }

        @ViewBuilder
        private func makeSmartViewsSection() -> some View {
            if !environment.smartViewRepository.smartViews.isEmpty {
                Section("Smart Views") {
                    ForEach(environment.smartViewRepository.smartViews) { smartView in
                        Label(smartView.name, systemImage: "line.3.horizontal.decrease.circle")
                            .tag(MacSidebarItem.smartView(smartView))
                    }
                }
            }
        }

        private func makeTagsSection() -> some View {
            Section("Tags") {
                ForEach(environment.tagRepository.flattenedTagHierarchy) { item in
                    TagTreeLabel(node: item.node, depth: item.depth, showsCountBadge: true)
                        .tag(MacSidebarItem.tag(item.node.slug))
                        .bookmarkTagDropDestination(slug: item.node.slug)
                }
            }
        }

        @ViewBuilder
        private func makeDetail() -> some View {
            if case let .smartView(smartView) = selection {
                BookmarkListView(smartView: smartView)
            } else {
                BookmarkListView(tag: selection?.tagFilter)
            }
        }
    }

    // MARK: - MacSidebarItem

    /// A selectable entry in the macOS sidebar.
    private enum MacSidebarItem: Hashable {

        case all
        case untagged
        case today
        case thisWeek
        case tag(String)
        case smartView(SmartView)

        // MARK: Computed Properties

        /// The `tag` filter passed to `BookmarkListView`: `nil` for all, a Views sentinel, or the
        /// literal tag. A Smart View selection is handled separately and returns `nil` here.
        var tagFilter: String? {
            switch self {
            case .all: nil
            case .untagged: BookmarkListQuery.untaggedTag
            case .today: BookmarkListQuery.todayTag
            case .thisWeek: BookmarkListQuery.thisWeekTag
            case let .tag(name): name
            case .smartView: nil
            }
        }
    }

    #if DEBUG
        #Preview {
            MacContentView()
                .environment(AppEnvironment.preview)
                .environment(AppSettings.preview)
        }
    #endif

#endif
