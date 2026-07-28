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
        if !settings.isConfigured {
            SetupView()
        } else if !environment.authRepository.isAuthenticated {
            LoginView()
        } else {
            MainFlowView()
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
