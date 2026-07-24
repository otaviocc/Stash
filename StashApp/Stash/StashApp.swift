// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

#if os(macOS)
    import AppKit
#endif

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
                    .environment(\.instanceAccent, appSettings.accent.color)
                    .environment(\.instanceAccentTextColor, appSettings.accent.textColor)
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
        #if os(macOS)
            .onReceive(appEnvironment.notificationCenter
                .publisher(for: NSApplication.didBecomeActiveNotification))
            { _ in
                syncIfAuthenticated()
            }
        #endif
    }

    // MARK: Functions

    private func handleScenePhase(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active where oldPhase == .background:
            syncIfAuthenticated()
        case .background:
            appEnvironment.syncEngine.scheduleBackgroundRefresh()
        default:
            break
        }
    }

    private func syncIfAuthenticated() {
        guard appEnvironment.authRepository.isAuthenticated else { return }

        Task { await appEnvironment.syncEngine.sync() }
    }
}
