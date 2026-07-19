// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - SetupView

/// Collects the server URL on first launch.
struct SetupView: View {

    // MARK: SwiftUI Properties

    @Environment(AppSettings.self) private var settings

    @State private var serverURL = ""
    @State private var errorMessage: String?

    // MARK: Computed Properties

    private var isValid: Bool {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        NavigationStack {
            Form {
                makeServerSection()
                makeErrorMessage()

                Button("Continue", action: save)
                    .disabled(!isValid)
            }
            .formStyle(.grouped)
            .navigationTitle("Welcome to Stash")
        }
    }

    // MARK: Content Methods

    private func makeServerSection() -> some View {
        Section {
            TextField("URL", text: $serverURL)
                .urlFieldStyle()
        } header: {
            Text("Server URL")
        } footer: {
            Text("Enter the address of your Stash server, including http:// or https://.")
        }
    }

    @ViewBuilder
    private func makeErrorMessage() -> some View {
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .font(.footnote)
        }
    }

    // MARK: Functions

    private func save() {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid else {
            errorMessage = "The URL must start with http:// or https://."
            return
        }

        settings.serverURL = trimmed
    }
}

#if DEBUG
    #Preview {
        SetupView()
            .environment(AppSettings.preview)
    }
#endif
