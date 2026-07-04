// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

#if os(iOS)

    import SafariServices
    import SwiftUI

    // MARK: - SafariView

    /// Wraps `SFSafariViewController` — Apple's recommended in-app browser — for viewing a bookmark's
    /// `http`/`https` URL without leaving the app. iOS/iPadOS only; macOS always uses the default
    /// browser.
    struct SafariView: UIViewControllerRepresentable {

        // MARK: Properties

        let url: URL
        let entersReader: Bool

        // MARK: Functions

        func makeUIViewController(context: Context) -> SFSafariViewController {
            let configuration = SFSafariViewController.Configuration()
            configuration.entersReaderIfAvailable = entersReader

            return SFSafariViewController(url: url, configuration: configuration)
        }

        func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
    }

#endif
