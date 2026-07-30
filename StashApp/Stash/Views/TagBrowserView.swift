// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import StashKit
import SwiftUI

// MARK: - TagBrowserView

/// The Tags tab: the bookmark-list "Views" (All, Untagged, Today, This Week) over a collapsible,
/// hierarchical tag tree mirroring the web sidebar. Each entry drills into a filtered bookmark list.
struct TagBrowserView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment

    @State private var errorMessage: String?

    // MARK: Computed Properties

    private var flatNodes: [FlatTagNode] {
        environment.tagRepository.flattenedTagHierarchy
    }

    private var smartViews: [SmartView] {
        environment.smartViewRepository.smartViews
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        List {
            makeViewsSection()
            makeSmartViewsSection()
            makeTagsSection()
        }
        .navigationTitle("Tags")
        .refreshable {
            await load(force: true)
        }
        .task {
            await load(force: false)
        }
        .onSyncCompleted {
            environment.tagRepository.refresh()
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

    private func makeViewsSection() -> some View {
        Section("Views") {
            makeViewLink("All Bookmarks", systemImage: "bookmark", tag: nil)
            makeViewLink("Untagged", systemImage: "tag.slash", tag: BookmarkListQuery.untaggedTag)
            makeViewLink("Today", systemImage: "sun.max", tag: BookmarkListQuery.todayTag)
            makeViewLink("This Week", systemImage: "calendar", tag: BookmarkListQuery.thisWeekTag)
        }
    }

    @ViewBuilder
    private func makeSmartViewsSection() -> some View {
        if !smartViews.isEmpty {
            Section("Smart Views") {
                ForEach(smartViews) { smartView in
                    NavigationLink {
                        BookmarkListView(smartView: smartView)
                    } label: {
                        Label(smartView.name, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func makeTagsSection() -> some View {
        if !flatNodes.isEmpty {
            Section("Tags") {
                ForEach(flatNodes) { item in
                    NavigationLink {
                        BookmarkListView(tag: item.node.slug)
                    } label: {
                        TagTreeLabel(node: item.node, depth: item.depth, showsCountBadge: true)
                    }
                }
            }
        }
    }

    private func makeViewLink(_ title: String, systemImage: String, tag: String?) -> some View {
        NavigationLink {
            BookmarkListView(tag: tag)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    // MARK: Functions

    private func load(force: Bool) async {
        do {
            if force {
                try await environment.tagRepository.reload()
                try await environment.smartViewRepository.reload()
            } else {
                try await environment.tagRepository.load()
                try await environment.smartViewRepository.load()
            }
        } catch {
            errorMessage = error.stashUserMessage
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            TagBrowserView()
        }
        .environment(AppEnvironment.preview)
        .environment(AppSettings.preview)
    }
#endif
