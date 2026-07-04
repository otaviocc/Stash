// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - RecoveryCodeView

/// Collects a single-use recovery code as an alternative to a TOTP code.
struct RecoveryCodeView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    // MARK: Properties

    let tempToken: String

    // MARK: Computed Properties

    private var canSubmit: Bool {
        !code.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Form {
            makeCodeSection()
            makeErrorMessage()
            makeVerifyButton()
        }
        .formStyle(.grouped)
        .navigationTitle("Recovery Code")
        .inlineNavigationTitleStyle()
    }

    // MARK: Content Methods

    private func makeCodeSection() -> some View {
        Section {
            TextField("XXXX-XXXX", text: $code)
                .uppercasedFieldStyle()
        } header: {
            Text("Recovery code")
        } footer: {
            Text("Enter one of the recovery codes you saved when enabling two-factor authentication.")
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

    private func makeVerifyButton() -> some View {
        Button(action: verify) {
            if isSubmitting {
                ProgressView()
            } else {
                Text("Verify")
            }
        }
        .disabled(!canSubmit)
    }

    // MARK: Functions

    private func verify() {
        errorMessage = nil
        isSubmitting = true

        Task {
            defer { isSubmitting = false }

            do {
                try await environment.authRepository.submitRecoveryCode(
                    tempToken: tempToken,
                    code: code.trimmingCharacters(in: .whitespaces)
                )
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            RecoveryCodeView(tempToken: "preview-temp-token")
        }
        .environment(AppEnvironment.preview)
    }
#endif
