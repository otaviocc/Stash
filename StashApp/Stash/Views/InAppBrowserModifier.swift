// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

#if os(iOS)

    import SwiftUI

    // MARK: - InAppBrowserModifier

    /// Routes link opens within a subtree to an in-app Safari sheet when the user's
    /// `BrowserPreference` is `.inApp`.
    ///
    /// It overrides the `openURL` environment action so that both imperative `openURL(_:)` calls and
    /// SwiftUI `Link`s below it are intercepted from one place — leaving the shared bookmark views
    /// untouched. Only `http`/`https` URLs are captured; every other scheme (and the
    /// `.defaultBrowser` preference) falls through to the system, so `mailto:`, `tel:`, and share
    /// actions behave normally.
    private struct InAppBrowserModifier: ViewModifier {

        // MARK: Nested Types

        /// A URL wrapped for `sheet(item:)`, keyed on the address so re-tapping a different link
        /// re-presents the sheet.
        private struct IdentifiedURL: Identifiable {

            // MARK: Properties

            let url: URL

            // MARK: Computed Properties

            var id: String {
                url.absoluteString
            }
        }

        // MARK: SwiftUI Properties

        @Environment(AppSettings.self) private var settings

        @State private var presentedURL: IdentifiedURL?

        // MARK: Content Methods

        func body(content: Content) -> some View {
            content
                .environment(\.openURL, OpenURLAction { url in
                    guard
                        settings.browserPreference == .inApp,
                        let scheme = url.scheme?.lowercased(),
                        scheme == "http" || scheme == "https"
                    else {
                        return .systemAction
                    }

                    presentedURL = IdentifiedURL(url: url)

                    return .handled
                })
                .sheet(item: $presentedURL) { item in
                    SafariView(url: item.url, entersReader: settings.readerMode)
                        .ignoresSafeArea()
                }
        }
    }

    extension View {

        /// Presents `http`/`https` link opens in an in-app Safari sheet when the user prefers in-app
        /// browsing. Apply to a `NavigationStack` that hosts bookmark browsing.
        func inAppBrowser() -> some View {
            modifier(InAppBrowserModifier())
        }
    }

#endif
