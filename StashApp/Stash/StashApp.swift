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
/// `Settings` scene (⌘,) and a minimum window size. Both platforms follow the system appearance.
@main
struct StashApp: App {

    // MARK: SwiftUI Properties

    @State private var appSettings: AppSettings
    @State private var appEnvironment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    // MARK: Computed Properties

    // MARK: Content

    var body: some Scene {
        #if os(macOS)
            WindowGroup {
                makeRootView()
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
            }
        #else
            WindowGroup {
                makeRootView()
            }
            .backgroundTask(.appRefresh(BackgroundSyncScheduler.taskIdentifier)) {
                await appEnvironment.syncEngine.syncInBackground()
            }
        #endif
    }

    // MARK: Lifecycle

    init() {
        let defaults = AppGroup.makeSharedDefaults()
        _appSettings = State(initialValue: AppSettings(defaults: defaults))
        _appEnvironment = State(initialValue: AppEnvironment(defaults: defaults))
    }

    // MARK: Content Methods

    private func makeRootView() -> some View {
        RootView()
            .environment(appSettings)
            .environment(appEnvironment)
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhase(from: oldPhase, to: newPhase)
            }
    }

    // MARK: Functions

    private func handleScenePhase(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active where oldPhase == .background:
            guard appEnvironment.authRepository.isAuthenticated else { return }

            Task { await appEnvironment.syncEngine.sync() }
        case .background:
            appEnvironment.syncEngine.scheduleBackgroundRefresh()
        default:
            break
        }
    }
}
