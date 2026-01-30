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

import Foundation

/// Holds app-wide configuration persisted in UserDefaults.
///
/// `serverURL` is a tracked `@Observable` property backed by UserDefaults rather than `@AppStorage`:
/// an `@ObservationIgnored @AppStorage` property is excluded from observation, so mutating it would
/// not notify SwiftUI and `RootView` would never re-route after setup. Writing through to the same
/// `serverURL` key keeps it readable by `StashClientProvider`, which reads UserDefaults directly.
@MainActor
@Observable
final class AppSettings {

    // MARK: Static Properties

    private static let serverURLKey = "serverURL"

    // MARK: Properties

    var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: Self.serverURLKey)
        }
    }

    // MARK: Computed Properties

    var isConfigured: Bool {
        !serverURL.isEmpty
    }

    // MARK: Lifecycle

    init() {
        serverURL = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? ""
    }
}
