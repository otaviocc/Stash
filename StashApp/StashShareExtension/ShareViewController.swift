// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

#if os(iOS)
    import SwiftUI
    import UIKit

    /// The root view controller for the iOS Share Extension, hosting the SwiftUI `ShareExtensionView`.
    final class ShareViewController: UIViewController {

        override func viewDidLoad() {
            super.viewDidLoad()

            guard let extensionContext else {
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
    }

#endif
