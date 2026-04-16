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
import StashKit

/// Holds all app-wide dependencies.
///
/// Constructed once at launch and injected into the SwiftUI environment. The token stores use the
/// `group.cc.otavio.stash` Keychain access group so the Share Extension reads the same tokens the
/// app writes.
///
/// `authRepository` and `tagRepository` are shared singletons (auth state and the tag cache are
/// global), but bookmark-list state is *not*: each independent list (the Bookmarks tab, a tag drill-in
/// in the Tags tab, the iPad detail column) gets its own `BookmarkRepository` via
/// `makeBookmarkRepository()`, so browsing in one does not mutate the others. All of them read from
/// the one shared `LocalStore`.
@MainActor
@Observable
final class AppEnvironment {

    // MARK: Properties

    let authRepository: AuthRepository
    let tagRepository: TagRepository
    let smartViewRepository: SmartViewRepository

    private let clientProvider: StashClientProvider
    private let localStore: LocalStore
    private let defaults: UserDefaults

    // MARK: Lifecycle

    init(defaults: UserDefaults, inMemory: Bool = false) {
        self.defaults = defaults

        let accessTokenStore = KeychainStore(
            AppGroup.accessTokenKey,
            accessGroup: AppGroup.identifier
        )

        let refreshTokenStore = KeychainStore(
            AppGroup.refreshTokenKey,
            accessGroup: AppGroup.identifier
        )

        let tokenManager = TokenManager(
            accessTokenStore: accessTokenStore,
            refreshTokenStore: refreshTokenStore
        )

        let clientProvider = StashClientProvider(
            tokenManager: tokenManager,
            defaults: defaults
        )
        self.clientProvider = clientProvider

        let localStore = LocalStore(inMemory: inMemory)
        self.localStore = localStore

        let authRepository = AuthRepository(
            clientProvider: clientProvider,
            tokenManager: tokenManager
        )
        self.authRepository = authRepository

        let tagRepository = TagRepository(localStore: localStore)
        self.tagRepository = tagRepository

        let smartViewRepository = SmartViewRepository(
            clientProvider: clientProvider,
            session: authRepository
        )
        self.smartViewRepository = smartViewRepository

        authRepository.onSessionCleared = { [weak tagRepository, weak smartViewRepository, weak localStore, defaults] in
            tagRepository?.reset()
            smartViewRepository?.reset()
            localStore?.wipe()
            defaults.set(false, forKey: AppGroup.localStoreSyncedKey)
        }
    }

    // MARK: Functions

    /// Builds a fresh `BookmarkRepository` with its own list state, sharing the app's client, session,
    /// and the one local store. Each bookmark list owns one so their contents stay independent.
    func makeBookmarkRepository() -> BookmarkRepository {
        BookmarkRepository(
            clientProvider: clientProvider,
            session: authRepository,
            localStore: localStore
        )
    }

    /// Performs the one-time full fetch that seeds the local store on first launch (or after a
    /// sign-out wiped it). Subsequent launches return immediately and read straight from the store.
    /// On failure (e.g. offline) the synced flag is left unset so the next launch retries.
    func bootstrapLocalStore() async {
        guard !defaults.bool(forKey: AppGroup.localStoreSyncedKey) else {
            return
        }

        do {
            try await fetchAllBookmarks()
            defaults.set(true, forKey: AppGroup.localStoreSyncedKey)
        } catch {
            return
        }
    }

    #if DEBUG
        func seedPreviewData(_ bookmarks: [Bookmark]) {
            localStore.insertPreviewSamples(bookmarks)
            tagRepository.refresh()
        }
    #endif

    // MARK: Private

    private func fetchAllBookmarks() async throws {
        try await authRepository.refreshIfNeeded()

        guard let client = clientProvider.client() else {
            throw AppError.notConfigured
        }

        let perPage = 200
        var page = 1

        while true {
            let request = BookmarkRequestFactory.makeChangesRequest(since: nil, page: page, perPage: perPage)
            let result = try await client.run(request).value
            for dto in result.items {
                localStore.upsert(dto)
            }

            guard result.items.count == perPage, page * perPage < result.metadata.total else {
                break
            }

            page += 1
        }

        localStore.save()
        tagRepository.refresh()
    }
}
