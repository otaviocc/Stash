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
