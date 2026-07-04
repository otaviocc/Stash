// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

#if os(iOS)

    /// The iPhone layout: Bookmarks, Tags, and Settings tabs, each in its own navigation stack.
    struct TabContainerView: View {

        // MARK: Content Properties

        // MARK: Content

        var body: some View {
            TabView {
                Tab("Bookmarks", systemImage: "bookmark") {
                    makeBookmarksTab()
                }

                Tab("Tags", systemImage: "tag") {
                    makeTagsTab()
                }

                Tab("Settings", systemImage: "gearshape") {
                    makeSettingsTab()
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
        }

        // MARK: Content Methods

        private func makeBookmarksTab() -> some View {
            NavigationStack {
                BookmarkListView(tag: nil)
            }
            .inAppBrowser()
        }

        private func makeTagsTab() -> some View {
            NavigationStack {
                TagBrowserView()
            }
            .inAppBrowser()
        }

        private func makeSettingsTab() -> some View {
            NavigationStack {
                SettingsView()
            }
        }
    }

#endif
