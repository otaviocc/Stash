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

// MARK: - LoginView

/// Username and password sign-in. Pushes the TOTP screen when the server requests 2FA.
struct LoginView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment
    @Environment(AppSettings.self) private var settings

    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var path: [LoginRoute] = []

    // MARK: Computed Properties

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !isSubmitting
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .usernameFieldStyle()
                    SecureField("Password", text: $password)
                        .passwordFieldStyle()
                } footer: {
                    Text(settings.serverURL)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                Button(action: signIn) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(!canSubmit)
            }
            .formStyle(.grouped)
            .navigationTitle("Sign In")
            .navigationDestination(for: LoginRoute.self) { route in
                switch route {
                case let .twoFactor(tempToken):
                    TOTPView(tempToken: tempToken)
                }
            }
        }
    }

    // MARK: Functions

    private func signIn() {
        errorMessage = nil
        isSubmitting = true

        Task {
            defer { isSubmitting = false }

            do {
                let result = try await environment.authRepository.login(
                    username: username.trimmingCharacters(in: .whitespaces),
                    password: password
                )

                if case let .requires2FA(tempToken) = result {
                    path.append(.twoFactor(tempToken: tempToken))
                }
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }
}

// MARK: - LoginRoute

/// A destination pushed onto the login navigation stack.
private enum LoginRoute: Hashable {

    case twoFactor(tempToken: String)
}

#if DEBUG
    #Preview {
        LoginView()
            .environment(AppEnvironment.preview)
            .environment(AppSettings())
    }
#endif
