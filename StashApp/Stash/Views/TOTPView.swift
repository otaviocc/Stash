// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - TOTPView

/// Collects a six-digit TOTP code after a 2FA challenge.
struct TOTPView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    // MARK: Properties

    let tempToken: String

    // MARK: Computed Properties

    private var canSubmit: Bool {
        code.count == 6 && !isSubmitting
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Form {
            makeCodeSection()
            makeErrorMessage()
            makeVerifyButton()

            NavigationLink("Use a recovery code") {
                RecoveryCodeView(tempToken: tempToken)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Two-Factor")
        .inlineNavigationTitleStyle()
    }

    // MARK: Content Methods

    private func makeCodeSection() -> some View {
        Section {
            TextField("000000", text: $code)
                .oneTimeCodeFieldStyle()
                .onChange(of: code) { _, newValue in
                    code = String(newValue.filter(\.isNumber).prefix(6))
                }
        } header: {
            Text("Authentication code")
        } footer: {
            Text("Enter the six-digit code from your authenticator app.")
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
                try await environment.authRepository.submitTOTP(tempToken: tempToken, code: code)
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            TOTPView(tempToken: "preview-temp-token")
        }
        .environment(AppEnvironment.preview)
    }
#endif
