// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - LoginView

/// Username and password sign-in. Pushes the TOTP screen when the server requests 2FA.
struct LoginView: View {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment
    @Environment(AppSettings.self) private var settings

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var path: [LoginRoute] = []

    // MARK: Computed Properties

    private var isServerURLValid: Bool {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    private var canSubmit: Bool {
        isServerURLValid
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !isSubmitting
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                makeServerSection()
                makeCredentialsSection()
                makeErrorMessage()
                makeSignInButton()
            }
            .formStyle(.grouped)
            .navigationTitle("Sign In")
            .onAppear {
                if serverURL.isEmpty {
                    serverURL = settings.serverURL
                }
            }
            .navigationDestination(for: LoginRoute.self) { route in
                switch route {
                case let .twoFactor(tempToken):
                    TOTPView(tempToken: tempToken)
                }
            }
        }
    }

    // MARK: Content Methods

    private func makeServerSection() -> some View {
        Section {
            TextField("URL", text: $serverURL)
                .urlFieldStyle()
        } header: {
            Text("Server")
        } footer: {
            Text("The address of your Stash server, including http:// or https://.")
        }
    }

    private func makeCredentialsSection() -> some View {
        Section {
            TextField("Username", text: $username)
                .usernameFieldStyle()
            SecureField("Password", text: $password)
                .passwordFieldStyle()
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

    private func makeSignInButton() -> some View {
        Button(action: signIn) {
            if isSubmitting {
                ProgressView()
            } else {
                Text("Sign In")
            }
        }
        .disabled(!canSubmit)
    }

    // MARK: Functions

    private func signIn() {
        errorMessage = nil
        isSubmitting = true

        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL != settings.serverURL {
            settings.serverURL = trimmedURL
        }

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
            .environment(AppSettings.preview)
    }
#endif
