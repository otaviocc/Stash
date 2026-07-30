// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

#if os(iOS)
    import SwiftUI
    import UIKit

    /// The root view controller for the iOS Share Extension, hosting the SwiftUI `ShareExtensionView`.
    final class ShareViewController: UIViewController {

        // MARK: Overridden Functions

        override func viewDidLoad() {
            super.viewDidLoad()

            guard let extensionContext else {
                presentMissingContextFallback()

                return
            }

            let hosting = UIHostingController(rootView: ShareExtensionView(extensionContext: extensionContext))
            addChild(hosting)
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(hosting.view)

            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])

            hosting.didMove(toParent: self)
        }

        // MARK: Functions

        /// The host is expected to always supply an `NSExtensionContext`; this only guards against
        /// a stranded, permanently blank screen if it somehow doesn't, by giving the user an explicit
        /// way to close the extension instead of a dead end.
        private func presentMissingContextFallback() {
            let hosting = UIHostingController(
                rootView: MissingExtensionContextView { [weak self] in
                    self?.dismiss(animated: true)
                }
            )
            addChild(hosting)
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(hosting.view)

            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])

            hosting.didMove(toParent: self)
        }
    }

#endif
