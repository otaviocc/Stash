// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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
            Form {
                makeServerSection()
                SyncStatusSection()
                makeSignOutSection()
            }
            .formStyle(.grouped)
        }

        // MARK: Content Methods

        private func makeServerSection() -> some View {
            Section {
                LabeledContent("URL") {
                    Text(settings.serverURL)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Sign out to connect to a different server.")
            }
        }

        private func makeSignOutSection() -> some View {
            Section {
                Button(action: signOut) {
                    if isSigningOut {
                        ProgressView()
                    } else {
                        Text("Sign Out")
                    }
                }
                .formButtonRowStyle(isDestructive: true)
                .disabled(isSigningOut)
            }
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
