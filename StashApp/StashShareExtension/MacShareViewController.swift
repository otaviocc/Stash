// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

#if os(macOS)
    import AppKit
    import SwiftUI

    /// The principal view controller for the macOS Share Extension, hosting the same SwiftUI
    /// `ShareExtensionView` the iOS extension uses inside an `NSHostingController`.
    final class MacShareViewController: NSViewController {

        // MARK: Overridden Properties

        override var nibName: NSNib.Name? {
            nil
        }

        // MARK: Overridden Functions

        override func loadView() {
            view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 600))
        }

        override func viewDidLoad() {
            super.viewDidLoad()

            guard let extensionContext else {
                return
            }

            let hosting = NSHostingController(rootView: ShareExtensionView(extensionContext: extensionContext))
            addChild(hosting)
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(hosting.view)

            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        }
    }

#endif
