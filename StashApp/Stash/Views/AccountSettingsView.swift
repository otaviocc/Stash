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

// MARK: - AccountSettingsView

/// The Account screen: change the password and manage two-factor authentication (enrol or disable).
struct AccountSettingsView: View {

    // MARK: Static Properties

    private static let minimumPasswordLength = 12

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment

    @State private var user: CurrentUser?
    @State private var isLoadingUser = true
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordMessage: String?
    @State private var passwordSucceeded = false
    @State private var isSavingPassword = false
    @State private var disableCode = ""
    @State private var twoFactorMessage: String?
    @State private var isDisabling = false
    @State private var showingEnroll = false

    // MARK: Computed Properties

    private var canChangePassword: Bool {
        !currentPassword.isEmpty
            && newPassword.count >= Self.minimumPasswordLength
            && newPassword == confirmPassword
            && !isSavingPassword
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Form {
            makeChangePasswordSection()
            makeTwoFactorSection()
        }
        .formStyle(.grouped)
        .formChromeStyle()
        .task {
            await loadUser()
        }
        .sheet(isPresented: $showingEnroll) {
            TwoFactorEnrollView(auth: environment.authRepository) {
                Task { await loadUser() }
            }
        }
    }

    // MARK: Content Methods

    private func makeChangePasswordSection() -> some View {
        Section {
            SecureField("Current password", text: $currentPassword)
            SecureField("New password", text: $newPassword)
            SecureField("Confirm new password", text: $confirmPassword)

            if let passwordMessage {
                Text(passwordMessage)
                    .font(.footnote)
                    .foregroundStyle(passwordSucceeded ? .green : .red)
            }

            Button("Change Password", action: changePassword)
                .disabled(!canChangePassword)
        } header: {
            Text("Change Password")
        } footer: {
            Text("At least \(Self.minimumPasswordLength) characters.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func makeTwoFactorSection() -> some View {
        Section("Two-Factor Authentication") {
            makeTwoFactorContent()
        }
    }

    @ViewBuilder
    private func makeTwoFactorContent() -> some View {
        if isLoadingUser {
            ProgressView()
        } else if user?.isTOTPEnabled == true {
            Text("Two-factor authentication is on.")
                .foregroundStyle(.secondary)
            TextField("Current 6-digit code", text: $disableCode)
                .oneTimeCodeFieldStyle()
            Button("Disable Two-Factor", role: .destructive, action: disableTwoFactor)
                .disabled(disableCode.isEmpty || isDisabling)
        } else {
            Text("Two-factor authentication is off.")
                .foregroundStyle(.secondary)
            Button("Enable Two-Factor") {
                showingEnroll = true
            }
        }

        if let twoFactorMessage {
            Text(twoFactorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    // MARK: Functions

    private func loadUser() async {
        do {
            user = try await environment.authRepository.currentUser()
        } catch {
            twoFactorMessage = error.stashUserMessage
        }

        isLoadingUser = false
    }

    private func changePassword() {
        passwordMessage = nil
        passwordSucceeded = false
        isSavingPassword = true

        Task {
            defer { isSavingPassword = false }

            do {
                try await environment.authRepository.changePassword(current: currentPassword, new: newPassword)
                currentPassword = ""
                newPassword = ""
                confirmPassword = ""
                passwordSucceeded = true
                passwordMessage = "Password changed."
            } catch {
                passwordMessage = error.stashUserMessage
            }
        }
    }

    private func disableTwoFactor() {
        twoFactorMessage = nil
        isDisabling = true

        Task {
            defer { isDisabling = false }

            do {
                try await environment.authRepository.disableTOTP(code: disableCode)
                disableCode = ""
                await loadUser()
            } catch {
                twoFactorMessage = error.stashUserMessage
            }
        }
    }
}

// MARK: - TwoFactorEnrollView

/// The 2FA enrollment sheet: shows the QR code and secret, verifies a code, then displays the
/// one-time recovery codes.
private struct TwoFactorEnrollView: View {

    // MARK: SwiftUI Properties

    @Environment(\.dismiss) private var dismiss

    @State private var setup: TOTPSetup?
    @State private var code = ""
    @State private var recoveryCodes: [String]?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var didCopySecret = false

    // MARK: Properties

    let auth: AuthRepository
    let onEnrolled: () -> Void

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        NavigationStack {
            makeContent()
                .padding()
                .enrollSheetSize()
                .navigationTitle("Two-Factor Authentication")
                .inlineNavigationTitleStyle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .task {
                    await beginSetup()
                }
        }
    }

    // MARK: Content Methods

    @ViewBuilder
    private func makeContent() -> some View {
        if let recoveryCodes {
            makeRecoveryCodesView(recoveryCodes)
        } else if let setup {
            makeSetupView(setup)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func makeSetupView(_ setup: TOTPSetup) -> some View {
        VStack(spacing: 16) {
            Text("Scan this code with your authenticator app, or enter the key manually.")
                .font(.callout)
                .multilineTextAlignment(.center)

            QRCodeView(string: setup.otpauthURI)
                .frame(width: 160, height: 160)

            Button {
                copySecret(setup.secret)
            } label: {
                HStack(spacing: 6) {
                    Text(setup.secret)
                        .font(.system(.footnote, design: .monospaced))
                    Image(systemName: didCopySecret ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityLabel(didCopySecret ? "Setup key copied" : "Copy setup key")

            TextField("6-digit code", text: $code)
                .multilineTextAlignment(.center)
                .oneTimeCodeFieldStyle()

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button("Verify", action: verify)
                .disabled(code.isEmpty || isWorking)
                .keyboardShortcut(.defaultAction)

            Spacer()
        }
    }

    private func makeRecoveryCodesView(_ codes: [String]) -> some View {
        VStack(spacing: 16) {
            Text("Save your recovery codes")
                .font(.headline)
            Text("Each code works once if you lose access to your authenticator. They won't be shown again.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(codes, id: \.self) { code in
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .textSelection(.enabled)

            Spacer()

            Button("Done") {
                onEnrolled()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Functions

    private func copySecret(_ secret: String) {
        copyToPasteboard(secret)

        withAnimation {
            didCopySecret = true
        }

        Task {
            try? await Task.sleep(for: .seconds(2))

            withAnimation {
                didCopySecret = false
            }
        }
    }

    private func beginSetup() async {
        guard setup == nil else {
            return
        }

        do {
            setup = try await auth.beginTOTPSetup()
        } catch {
            errorMessage = error.stashUserMessage
        }
    }

    private func verify() {
        errorMessage = nil
        isWorking = true

        Task {
            defer { isWorking = false }

            do {
                recoveryCodes = try await auth.completeTOTPSetup(code: code)
            } catch {
                errorMessage = error.stashUserMessage
            }
        }
    }
}

// MARK: - Platform Chrome

private extension View {

    /// The account form's outer chrome: macOS pads the form inside the settings window; iOS lets
    /// the grouped `Form` provide its own insets.
    @ViewBuilder
    func formChromeStyle() -> some View {
        #if os(macOS)
            padding()
        #else
            self
        #endif
    }

    /// The 2FA enrollment sheet is fixed-size in the macOS settings window; on iOS it sizes itself
    /// as a standard sheet.
    @ViewBuilder
    func enrollSheetSize() -> some View {
        #if os(macOS)
            frame(width: 380, height: 460)
        #else
            self
        #endif
    }
}

#if DEBUG
    #Preview {
        AccountSettingsView()
            .environment(AppEnvironment.preview)
    }
#endif
