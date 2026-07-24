// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

/// Holds all app-wide dependencies.
///
/// Constructed once at launch and injected into the SwiftUI environment. The token stores use the
/// `AppGroup.identifier` (`group.<STASH_BUNDLE_PREFIX>.stash`) Keychain access group so the Share
/// Extension reads the same tokens the app writes.
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
    let instanceRepository: InstanceRepository
    let connectivityMonitor: ConnectivityMonitor
    let syncEngine: SyncEngine
    let notificationCenter: NotificationCenter

    private let clientProvider: StashClientProvider
    private let localStore: LocalStore
    private let defaults: UserDefaults

    // MARK: Lifecycle

    init(
        defaults: UserDefaults,
        notificationCenter: NotificationCenter = .default,
        inMemory: Bool = false
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter

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

        if localStore.didResetOnInit {
            defaults.removeObject(forKey: AppGroup.lastSyncedAtKey)
        }

        let connectivityMonitor = ConnectivityMonitor()
        self.connectivityMonitor = connectivityMonitor

        let authRepository = AuthRepository(
            clientProvider: clientProvider,
            tokenManager: tokenManager
        )
        self.authRepository = authRepository

        let tagRepository = TagRepository(localStore: localStore)
        self.tagRepository = tagRepository

        let smartViewRepository = SmartViewRepository(session: authRepository)
        self.smartViewRepository = smartViewRepository

        instanceRepository = InstanceRepository(clientProvider: clientProvider)

        let syncEngine = SyncEngine(
            clientProvider: clientProvider,
            session: authRepository,
            localStore: localStore,
            connectivity: connectivityMonitor,
            defaults: defaults
        )
        self.syncEngine = syncEngine

        authRepository.onSessionCleared = { [weak self] in
            self?.tagRepository.reset()
            self?.smartViewRepository.reset()
            self?.localStore.wipe(currentUserID: self?.clientProvider.currentUserID())
            self?.syncEngine.reset()
        }

        authRepository.onExplicitLogout = { [weak self] in
            self?.tagRepository.reset()
            self?.smartViewRepository.reset()
            self?.localStore.wipeAll()
            self?.syncEngine.reset()
        }

        connectivityMonitor.onReconnect = { [weak self] in
            Task { await self?.syncEngine.sync() }
        }
    }

    // MARK: Functions

    /// Builds a fresh `BookmarkRepository` with its own list state, sharing the app's client, session,
    /// local store, and sync engine. Each bookmark list owns one so their contents stay independent.
    func makeBookmarkRepository() -> BookmarkRepository {
        BookmarkRepository(
            clientProvider: clientProvider,
            session: authRepository,
            localStore: localStore,
            syncEngine: syncEngine
        )
    }

    #if DEBUG
        func seedPreviewData(_ bookmarks: [Bookmark]) {
            localStore.insertPreviewSamples(bookmarks)
            tagRepository.refresh()
        }
    #endif
}
