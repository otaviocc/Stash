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
            Section {
                TextField("XXXX-XXXX", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } header: {
                Text("Recovery code")
            } footer: {
                Text("Enter one of the recovery codes you saved when enabling two-factor authentication.")
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
        }
        .navigationTitle("Recovery Code")
        .navigationBarTitleDisplayMode(.inline)
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
