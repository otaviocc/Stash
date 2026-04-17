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
