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

    /// The macOS `Settings` scene (⌘,): General, Account, and Appearance tabs.
    struct MacSettingsView: View {

        // MARK: Content

        var body: some View {
            TabView {
                GeneralSettingsView()
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }

                AccountSettingsView()
                    .tabItem {
                        Label("Account", systemImage: "person.crop.circle")
                    }

                AppearanceSettingsView()
                    .tabItem {
                        Label("Appearance", systemImage: "paintbrush")
                    }
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
                    TextField("https://stash.example.com", text: $settings.serverURL)
                        .urlFieldStyle()
                }

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

    // MARK: - AppearanceSettingsView

    /// The Appearance tab: Light / Dark / Auto, stored in `UserDefaults` (no theme cookie on native).
    private struct AppearanceSettingsView: View {

        // MARK: SwiftUI Properties

        @Environment(AppSettings.self) private var settings

        // MARK: Content Properties

        // MARK: Content

        var body: some View {
            @Bindable var settings = settings

            Form {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.inline)
            }
            .formStyle(.grouped)
            .padding()
        }
    }

#endif
