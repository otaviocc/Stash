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

/// Holds all app-wide dependencies.
///
/// Constructed once at launch and injected into the SwiftUI environment. The token stores use the
/// default (no access group) so the app works standalone; M9 will supply the `group.cc.otavio.stash`
/// access group to share the tokens with the Share Extension.
@MainActor
@Observable
final class AppEnvironment {

    // MARK: Properties

    let authRepository: AuthRepository
    let bookmarkRepository: BookmarkRepository
    let tagRepository: TagRepository

    // MARK: Lifecycle

    init() {
        let accessTokenStore = KeychainStore("cc.otavio.stash.accessToken")
        let refreshTokenStore = KeychainStore("cc.otavio.stash.refreshToken")
        let tokenManager = TokenManager(
            accessTokenStore: accessTokenStore,
            refreshTokenStore: refreshTokenStore
        )
        let clientProvider = StashClientProvider(tokenManager: tokenManager)

        let authRepository = AuthRepository(
            clientProvider: clientProvider,
            tokenManager: tokenManager
        )

        self.authRepository = authRepository
        bookmarkRepository = BookmarkRepository(
            clientProvider: clientProvider,
            session: authRepository
        )
        tagRepository = TagRepository(
            clientProvider: clientProvider,
            session: authRepository
        )
    }
}
