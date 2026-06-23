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
    }
}
