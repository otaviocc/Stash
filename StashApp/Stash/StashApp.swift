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

import SwiftUI

// MARK: - StashApp

/// The Stash app entry point. Builds the shared settings and dependency container once at launch
/// and injects them into the SwiftUI environment. The same `App` serves iOS and macOS; macOS adds a
/// `Settings` scene (⌘,) and a minimum window size.
@main
struct StashApp: App {

    // MARK: SwiftUI Properties

    @State private var appSettings: AppSettings
    @State private var appEnvironment: AppEnvironment

    // MARK: Computed Properties

    // MARK: Content

    var body: some Scene {
        #if os(macOS)
            WindowGroup {
                rootView
                    .frame(minWidth: 800, minHeight: 500)
            }
            .defaultSize(width: 1000, height: 650)
            .windowResizability(.contentMinSize)
            .windowToolbarStyle(.unified)
            .commands {
                SidebarCommands()
            }

            Settings {
                MacSettingsView()
                    .environment(appSettings)
                    .environment(appEnvironment)
                    .preferredColorScheme(appSettings.appearance.colorScheme)
            }
        #else
            WindowGroup {
                rootView
            }
        #endif
    }

    // MARK: Lifecycle

    init() {
        let settings = AppSettings()
        _appSettings = State(initialValue: settings)
        _appEnvironment = State(initialValue: AppEnvironment())
    }

    // MARK: Content Properties

    private var rootView: some View {
        RootView()
            .environment(appSettings)
            .environment(appEnvironment)
            .preferredColorScheme(appSettings.appearance.colorScheme)
    }
}

// MARK: - AppAppearance + ColorScheme

extension AppAppearance {

    /// The SwiftUI color scheme to force, or `nil` to follow the system (Auto).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
