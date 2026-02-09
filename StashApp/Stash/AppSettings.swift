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

// MARK: - AppAppearance

/// The user's appearance preference. Mirrors the web frontend's Light / Dark / Auto choice, but is
/// stored in `UserDefaults` rather than a cookie (no browser on the native clients).
enum AppAppearance: String, CaseIterable, Identifiable {

    case system
    case light
    case dark

    // MARK: Computed Properties

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

// MARK: - AppSettings

/// Holds app-wide configuration persisted in UserDefaults.
///
/// `serverURL` is a tracked `@Observable` property backed by UserDefaults rather than `@AppStorage`:
/// an `@ObservationIgnored @AppStorage` property is excluded from observation, so mutating it would
/// not notify SwiftUI and `RootView` would never re-route after setup. It is written through to the
/// App Group's `UserDefaults` suite so both `StashClientProvider` and the Share Extension (a
/// separate process) read the server the user configured. `appearance` is app-only (the extension
/// never themes), so it lives in standard `UserDefaults`.
@MainActor
@Observable
final class AppSettings {

    // MARK: Static Properties

    private static let appearanceKey = "appearance"

    // MARK: Properties

    var serverURL: String {
        didSet {
            AppGroup.sharedDefaults.set(serverURL, forKey: AppGroup.serverURLKey)
        }
    }

    var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    // MARK: Computed Properties

    var isConfigured: Bool {
        !serverURL.isEmpty
    }

    // MARK: Lifecycle

    init() {
        serverURL = AppGroup.sharedDefaults.string(forKey: AppGroup.serverURLKey) ?? ""
        let storedAppearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
        appearance = storedAppearance.flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
}
