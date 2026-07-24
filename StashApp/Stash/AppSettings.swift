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

    /// The instance's accent theme, fetched from `GET /api/v1/instance` by `InstanceRepository` and
    /// applied at the app root via `\.instanceAccent`/`\.instanceAccentTextColor` — deliberately not
    /// `.tint(...)`, which would also recolour unstyled system chrome (toolbars, menus, standard
    /// buttons) that should stay neutral. Starts from whatever was last persisted
    /// (or `.default`, a neutral gray, on first launch) so the UI never flashes a branded colour that
    /// might clash with the instance's actual theme while the fetch is in flight, and is written
    /// straight back to the shared defaults on every update.
    var accent: InstanceAccent {
        didSet {
            accent.saveShared(to: defaults)
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

        accent = InstanceAccent.loadShared(from: defaults)
    }
}
