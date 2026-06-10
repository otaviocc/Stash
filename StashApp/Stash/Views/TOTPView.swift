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

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Button(action: verify) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Text("Verify")
                }
            }
            .disabled(!canSubmit)

            NavigationLink("Use a recovery code") {
                RecoveryCodeView(tempToken: tempToken)
            }
        }
        .navigationTitle("Two-Factor")
        .inlineNavigationTitleStyle()
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
