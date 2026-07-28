// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - BrowserPreference

/// Where the app opens a bookmark's link. `inApp` presents an in-app Safari view
/// (`SFSafariViewController`, iOS/iPadOS only); `defaultBrowser` hands off to the system default
/// browser. The setting is unused on macOS, which always uses the default browser.
enum BrowserPreference: String, CaseIterable, Identifiable {

    case inApp
    case defaultBrowser

    // MARK: Computed Properties

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .inApp: "In-App"
        case .defaultBrowser: "Default Browser"
        }
    }
}

// MARK: - AppSettings

/// Holds app-wide configuration persisted in UserDefaults.
///
/// `serverURL` is a tracked `@Observable` property backed by UserDefaults rather than `@AppStorage`:
/// an `@ObservationIgnored @AppStorage` property is excluded from observation, so mutating it would
/// not notify SwiftUI and `RootView` would never re-route after setup. It is written through to the
/// injected `UserDefaults` (the App Group suite) so both `StashClientProvider` and the Share
/// Extension (a separate process) read the server the user configured.
@MainActor
@Observable
final class AppSettings {

    // MARK: Properties

    var serverURL: String {
        didSet {
            defaults.set(
                serverURL,
                forKey: AppGroup.serverURLKey
            )
        }
    }

    var browserPreference: BrowserPreference {
        didSet {
            defaults.set(
                browserPreference.rawValue,
                forKey: AppGroup.browserPreferenceKey
            )
        }
    }

    var readerMode: Bool {
        didSet {
            defaults.set(
                readerMode,
                forKey: AppGroup.readerModeKey
            )
        }
    }

    /// The bundle identifier of the user's chosen browser on macOS, or `nil` for the system default
    /// browser. Unused on iOS/iPadOS, which use `browserPreference` instead.
    var macBrowserBundleID: String? {
        didSet {
            defaults.set(
                macBrowserBundleID,
                forKey: AppGroup.macBrowserKey
            )
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: Computed Properties

    var isConfigured: Bool {
        !serverURL.isEmpty
    }

    // MARK: Lifecycle

    init(
        defaults: UserDefaults
    ) {
        self.defaults = defaults

        serverURL = defaults
            .string(forKey: AppGroup.serverURLKey) ?? ""

        browserPreference = defaults
            .string(forKey: AppGroup.browserPreferenceKey)
            .flatMap(BrowserPreference.init(rawValue:)) ?? .inApp

        readerMode = defaults.bool(forKey: AppGroup.readerModeKey)

        macBrowserBundleID = defaults.string(forKey: AppGroup.macBrowserKey)
    }
}
