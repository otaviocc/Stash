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

import StashKit
import SwiftUI

#if os(iOS)

    // MARK: - MainView

    /// The authenticated app shell: a tag-sidebar split view on iPad, a tab bar on iPhone.
    struct MainView: View {

        // MARK: SwiftUI Properties

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(AppEnvironment.self) private var environment

        // MARK: Content Properties

        // MARK: Content

        var body: some View {
            makeContent()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !environment.connectivityMonitor.isOnline {
                        OfflineBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.default, value: environment.connectivityMonitor.isOnline)
        }

        // MARK: Content Methods

        @ViewBuilder
        private func makeContent() -> some View {
            if horizontalSizeClass == .regular {
                SidebarSplitView()
            } else {
                TabContainerView()
            }
        }
    }

    // MARK: - SidebarSplitView

    /// The iPad layout: a tag list in the sidebar driving a filtered bookmark list in the detail column.
    private struct SidebarSplitView: View {

        // MARK: SwiftUI Properties

        @Environment(AppEnvironment.self) private var environment

        @State private var selection: SidebarItem? = .all
        @State private var showingSettings = false

        // MARK: Content Properties

        // MARK: Content

        var body: some View {
            NavigationSplitView {
                List(selection: $selection) {
                    makeViewsSection()
                    makeSmartViewsSection()
                    makeTagsSection()
                }
                .navigationTitle("Stash")
                .toolbar {
                    ToolbarItem {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
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
                .inAppBrowser()
            }
            .sheet(isPresented: $showingSettings) {
                makeSettingsSheet()
            }
        }

        // MARK: Content Methods

        private func makeViewsSection() -> some View {
            Section("Views") {
                Label("All Bookmarks", systemImage: "bookmark")
                    .tag(SidebarItem.all)
                Label("Untagged", systemImage: "tag.slash")
                    .tag(SidebarItem.untagged)
                Label("Today", systemImage: "sun.max")
                    .tag(SidebarItem.today)
                Label("This Week", systemImage: "calendar")
                    .tag(SidebarItem.thisWeek)
            }
        }

        @ViewBuilder
        private func makeSmartViewsSection() -> some View {
            if !environment.smartViewRepository.smartViews.isEmpty {
                Section("Smart Views") {
                    ForEach(environment.smartViewRepository.smartViews) { smartView in
                        Label(smartView.name, systemImage: "line.3.horizontal.decrease.circle")
                            .tag(SidebarItem.smartView(smartView))
                    }
                }
            }
        }

        private func makeTagsSection() -> some View {
            Section("Tags") {
                ForEach(environment.tagRepository.flattenedTagHierarchy) { item in
                    TagTreeLabel(node: item.node, depth: item.depth, showsCountBadge: true)
                        .tag(SidebarItem.tag(item.node.slug))
                        .bookmarkTagDropDestination(slug: item.node.slug)
                }
            }
        }

        @ViewBuilder
        private func makeDetail() -> some View {
            if case let .smartView(smartView) = selection {
                BookmarkListView(smartView: smartView)
            } else {
                BookmarkListView(tag: selection?.tagName)
            }
        }

        private func makeSettingsSheet() -> some View {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
    }

    // MARK: - SidebarItem

    /// A selectable entry in the iPad sidebar.
    private enum SidebarItem: Hashable {

        case all
        case untagged
        case today
        case thisWeek
        case tag(String)
        case smartView(SmartView)

        // MARK: Computed Properties

        /// The `tag` filter passed to `BookmarkListView`: `nil` for all, a Views sentinel, or the
        /// literal tag. A Smart View selection is handled separately and returns `nil` here.
        var tagName: String? {
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
            MainView()
                .environment(AppEnvironment.preview)
                .environment(AppSettings.preview)
        }
    #endif

#endif
