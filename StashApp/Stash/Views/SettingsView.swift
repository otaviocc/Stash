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

// MARK: - SettingsView

/// The settings screen: the configured server URL, account management (password and 2FA), and a
/// sign-out action.
struct SettingsView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment
    @Environment(AppSettings.self) private var settings

    @State private var isSigningOut = false

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Form {
            makeServerSection()
            makeAccountSection()
            makeSmartViewsSection()
            makeSignOutSection()
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    // MARK: Content Methods

    private func makeServerSection() -> some View {
        Section("Server") {
            LabeledContent("URL", value: settings.serverURL)
        }
    }

    private func makeAccountSection() -> some View {
        Section("Account") {
            NavigationLink("Account") {
                AccountSettingsView()
                    .navigationTitle("Account")
            }
        }
    }

    private func makeSmartViewsSection() -> some View {
        Section("Smart Views") {
            NavigationLink("Smart Views") {
                SmartViewManagementView()
            }
        }
    }

    private func makeSignOutSection() -> some View {
        Section {
            Button(role: .destructive, action: signOut) {
                if isSigningOut {
                    ProgressView()
                } else {
                    Text("Sign Out")
                }
            }
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
        NavigationStack {
            SettingsView()
        }
        .environment(AppEnvironment.preview)
        .environment(AppSettings.preview)
    }
#endif
