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

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    makeServerSection(serverURL: $settings.serverURL)
                    makeSyncSection()
                    makeSignOutButton()
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        // MARK: Content Methods

        private func makeSectionHeader(_ title: String) -> some View {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func makeServerSection(serverURL: Binding<String>) -> some View {
            VStack(alignment: .leading, spacing: 16) {
                makeSectionHeader("Server")
                LabeledContent("URL") {
                    TextField("URL", text: serverURL)
                        .urlFieldStyle()
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                }
            }
        }

        private func makeSyncSection() -> some View {
            VStack(alignment: .leading, spacing: 16) {
                makeSectionHeader("Sync")
                SyncStatusRows()
            }
        }

        private func makeSignOutButton() -> some View {
            Button(action: signOut) {
                if isSigningOut {
                    ProgressView()
                } else {
                    Text("Sign Out")
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isSigningOut)
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
