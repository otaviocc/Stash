// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - RootView

/// Routes between the setup, login, and main app flows based on configuration and auth state.
struct RootView: View {

    // MARK: SwiftUI Properties

    @Environment(AppSettings.self) private var settings
    @Environment(AppEnvironment.self) private var environment

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Group {
            if !settings.isConfigured {
                SetupView()
            } else if !environment.authRepository.isAuthenticated {
                LoginView()
            } else {
                MainFlowView()
            }
        }
        .environment(\.instanceAccent, settings.accent.color)
        .environment(\.instanceAccentTextColor, settings.accent.textColor)
        .environment(\.instanceAccentForeground, settings.accent.foregroundColor)
        .task(id: settings.serverURL) {
            await refreshAccent()
        }
        .onChange(of: environment.connectivityMonitor.isOnline) { _, isOnline in
            guard isOnline else { return }

            Task { await refreshAccent() }
        }
    }

    // MARK: Functions

    /// Fetches the current instance accent and applies it, or leaves `settings.accent` untouched on
    /// failure. Called at launch (keyed on the server URL) and again whenever connectivity returns
    /// (`ConnectivityMonitor.isOnline`), so an initial fetch that failed offline — or on a transient
    /// server error — gets retried as soon as the network comes back, instead of leaving the app
    /// stuck on `.default` for the rest of the session.
    private func refreshAccent() async {
        guard settings.isConfigured else { return }

        if let accent = await environment.instanceRepository.fetchAccent() {
            settings.accent = accent
        }
    }
}

// MARK: - MainFlowView

/// The authenticated app, gated behind the one-time local-store seed. On first launch (or after a
/// sign-out reset the cursor) it blocks on the full pull so the bookmark lists read a populated store
/// rather than flashing empty; on later launches the store is already populated, so content shows
/// immediately while a delta sync runs in the background.
private struct MainFlowView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment
    @State private var isReady = false

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Group {
            if isReady {
                makeContent()
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .task {
            if environment.syncEngine.hasSyncedBefore {
                isReady = true
                await environment.syncEngine.sync()
            } else {
                await environment.syncEngine.sync()
                isReady = true
            }
        }
    }

    // MARK: Content Methods

    @ViewBuilder
    private func makeContent() -> some View {
        #if os(macOS)
            MacContentView()
        #else
            MainView()
        #endif
    }
}

#if DEBUG
    #Preview {
        RootView()
            .environment(AppEnvironment.preview)
            .environment(AppSettings.preview)
    }
#endif
