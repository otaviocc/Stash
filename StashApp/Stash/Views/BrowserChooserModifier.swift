// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

#if os(macOS)

    import AppKit
    import SwiftUI

    // MARK: - InstalledBrowser

    /// A browser discovered on the Mac, capable of opening `http`/`https` URLs.
    struct InstalledBrowser: Identifiable, Hashable {

        // MARK: Properties

        let bundleID: String
        let name: String
        let appURL: URL

        // MARK: Computed Properties

        var id: String {
            bundleID
        }

        var icon: NSImage {
            NSWorkspace.shared.icon(forFile: appURL.path)
        }

        // MARK: Static Functions

        /// Discovers every installed app that declares `http`/`https` handling, via Launch Services —
        /// no hardcoded browser list, so Firefox, Chrome, Safari, Orion, Brave, and anything else the
        /// user has installed all show up the same way. Sorted by display name.
        static func discoverAll() -> [InstalledBrowser] {
            guard let probeURL = URL(string: "https://example.com") else {
                return []
            }

            let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)

            let browsers = appURLs.compactMap { appURL -> InstalledBrowser? in
                guard let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier else {
                    return nil
                }

                let name = FileManager.default
                    .displayName(atPath: appURL.path)
                    .replacingOccurrences(of: ".app", with: "")

                return InstalledBrowser(bundleID: bundleID, name: name, appURL: appURL)
            }

            var seen = Set<String>()

            return browsers
                .filter { seen.insert($0.bundleID).inserted }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    // MARK: - BrowserChooserModifier

    /// Routes `http`/`https` link opens within a subtree to the user's chosen browser (`AppSettings
    /// .macBrowserBundleID`), macOS only.
    ///
    /// It overrides the `openURL` environment action so that both imperative `openURL(_:)` calls and
    /// SwiftUI `Link`s below it are intercepted from one place, the same pattern the iOS in-app-browser
    /// modifier uses, leaving the shared bookmark views untouched. A `nil` bundle identifier (the
    /// default) or a bundle identifier that no longer resolves to an installed app both fall through to
    /// `.systemAction`, silently opening in the system default browser: there is no chosen browser to
    /// launch, or the one previously chosen was uninstalled. Only `http`/`https` URLs are intercepted;
    /// every other scheme passes straight through to the system unmodified.
    private struct BrowserChooserModifier: ViewModifier {

        // MARK: SwiftUI Properties

        @Environment(AppSettings.self) private var settings

        // MARK: Content Methods

        func body(content: Content) -> some View {
            content
                .environment(\.openURL, OpenURLAction { url in
                    guard
                        let scheme = url.scheme?.lowercased(),
                        scheme == "http" || scheme == "https",
                        let bundleID = settings.macBrowserBundleID,
                        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                    else {
                        return .systemAction
                    }

                    NSWorkspace.shared.open(
                        [url],
                        withApplicationAt: appURL,
                        configuration: NSWorkspace.OpenConfiguration()
                    )

                    return .handled
                })
        }
    }

    extension View {

        /// Presents `http`/`https` link opens in the user's chosen browser (`AppSettings
        /// .macBrowserBundleID`), falling back to the system default browser when unset or unresolvable.
        /// Apply above the whole `NavigationSplitView`, not inside its `detail:` column: a `NavigationStack`
        /// hosted as a split view's detail column does not reliably propagate an `openURL` override down
        /// into its own `NavigationLink`-pushed destinations. macOS only.
        func macBrowserChooser() -> some View {
            modifier(BrowserChooserModifier())
        }
    }

#endif
