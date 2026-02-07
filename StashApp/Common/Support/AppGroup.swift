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

/// Shared App Group configuration used by both the main app and the Share Extension.
///
/// The two processes share the access token, refresh token, and configured server URL through this
/// group: the tokens via a Keychain access group (`KeychainStore(accessGroup:)`) and the server URL
/// via the group's `UserDefaults` suite. The main app writes them; the extension reads them.
enum AppGroup {

    // MARK: Static Properties

    static let identifier = "group.cc.otavio.stash"
    static let accessTokenKey = "cc.otavio.stash.accessToken"
    static let refreshTokenKey = "cc.otavio.stash.refreshToken"
    static let serverURLKey = "serverURL"

    // MARK: Static Computed Properties

    /// The `UserDefaults` suite backed by the App Group, so the server URL is visible to both the
    /// main app and the extension. Falls back to `.standard` if the suite cannot be opened.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
