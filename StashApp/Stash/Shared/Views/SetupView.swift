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
                Section {
                    TextField("https://stash.example.com", text: $serverURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server URL")
                } footer: {
                    Text("Enter the address of your Stash server, including http:// or https://.")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                Button("Continue", action: save)
                    .disabled(!isValid)
            }
            .navigationTitle("Welcome to Stash")
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
