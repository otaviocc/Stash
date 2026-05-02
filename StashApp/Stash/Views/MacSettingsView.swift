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

#if os(macOS)
    import SwiftUI

    // MARK: - MacSettingsView

    /// The macOS `Settings` scene (⌘,): General, Account, and Smart Views tabs.
    ///
    /// The signed-in/out switch lives here, above the `TabView`, not inside the tabs: `TabView`
    /// caches its tab content, so a guard inside a tab would not re-render when `isAuthenticated`
    /// flips (e.g. on sign-out). Swapping the whole `TabView` for the signed-out view — the way
    /// `RootView` swaps its top-level content — re-evaluates reliably.
    struct MacSettingsView: View {

        // MARK: SwiftUI Properties

        @Environment(AppEnvironment.self) private var environment

        // MARK: Content Properties

        // MARK: Content

        var body: some View {
            if environment.authRepository.isAuthenticated {
                makeSettingsTabs()
            } else {
                makeSignedOutView()
            }
        }

        // MARK: Content Methods

        private func makeSettingsTabs() -> some View {
            TabView {
                Tab("General", systemImage: "gearshape") {
                    GeneralSettingsView()
                }

                Tab("Account", systemImage: "person.crop.circle") {
                    AccountSettingsView()
                }

                Tab("Smart Views", systemImage: "line.3.horizontal.decrease.circle") {
                    SmartViewManagementView()
                }
            }
            .frame(width: 460, height: 420)
        }

        private func makeSignedOutView() -> some View {
            ContentUnavailableView {
                Label("Not Signed In", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Sign in from the main Stash window to manage your settings.")
            }
            .frame(width: 460, height: 420)
        }
    }

    // MARK: - GeneralSettingsView

    /// The General tab: the configured server URL and a sign-out action.
    private struct GeneralSettingsView: View {

        // MARK: SwiftUI Properties

        @Environment(AppEnvironment.self) private var environment
        @Environment(AppSettings.self) private var settings

        @State private var isSigningOut = false

        // MARK: Content Properties

        // MARK: Content

        var body: some View {
            @Bindable var settings = settings

            Form {
                Section("Server") {
                    TextField("URL", text: $settings.serverURL)
                        .urlFieldStyle()
                }

                SyncStatusSection()

                Section {
                    Button(role: .destructive, action: signOut) {
                        Text("Sign Out")
                    }
                    .disabled(isSigningOut)
                }
            }
            .formStyle(.grouped)
            .padding()
        }

        // MARK: Functions

        private func signOut() {
            isSigningOut = true

            Task {
                defer { isSigningOut = false }

                try? await environment.authRepository.logout()
            }
        }
    }

    #if DEBUG
        #Preview {
            MacSettingsView()
                .environment(AppEnvironment.preview)
                .environment(AppSettings.preview)
        }
    #endif

#endif
