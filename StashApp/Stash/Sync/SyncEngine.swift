// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

/// Coordinates pull and push between the local SwiftData store and the server.
///
/// A cycle always **pulls first, then pushes** (last-write-wins on `updatedAt`): the pull applies
/// server changes — skipping records whose local edit is newer than the server's — and removes
/// tombstoned bookmarks; the push then sweeps every record with a queued offline change (creates,
/// updates, deletes) up to the server. `lastSyncedAt` is the delta cursor, persisted in the App Group
/// defaults; the first cycle (cursor `nil`) pulls the full library, subsuming the initial seed. The
/// engine is `@MainActor` and single-flight — concurrent callers await the in-flight cycle. Client
/// provisioning mirrors the repositories (`StashClientProvider` + `SessionRefreshing`) rather than the
/// brief's raw `StashClient`, so a silent refresh runs first.
///
/// A full `sync()` cycle also does a best-effort Smart View definitions refresh (`SmartViewRepository
/// .reload()`) right after the bookmark pull/push, so every existing sync trigger (launch, reconnect,
/// background refresh, manual "Sync Now") keeps Smart View rules fresh too, not just each sidebar's own
/// first-appearance load. A failed refresh there is swallowed — Smart Views already have their own
/// on-disk cache and don't need to fail the whole cycle. `pushPending()` skips this, since it runs right
/// after a local write with nothing new to pull, so there's nothing about Smart View rules to refresh
/// either.
@MainActor
@Observable
final class SyncEngine {

    // MARK: Static Properties

    private static let perPage = 500

    // MARK: Properties

    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastSyncError: Error?
    private(set) var pendingCount = 0
    private(set) var failedCount = 0

    private let clientProvider: StashClientProvider
    private let session: SessionRefreshing
    private let localStore: LocalStore
    private let connectivity: ConnectivityMonitor
    private let defaults: UserDefaults
    private let smartViewRepository: SmartViewRepository
    private var inflightSync: Task<Void, Never>?

    /// Bumped each time a cycle is registered in `inflightSync`. A finishing cycle clears the slot only
    /// when the generation still matches its own, so a cycle that `reset()` cancelled mid-flight cannot
    /// null out a newer cycle's registration on resume — which would otherwise let a third caller start
    /// a second concurrent cycle.
    private var syncGeneration = 0

    // MARK: Computed Properties

    /// Whether a successful cycle has ever completed. `false` means the local store still needs its
    /// first full pull, so the UI blocks on it before showing content.
    var hasSyncedBefore: Bool {
        lastSyncedAt != nil
    }

    /// The signed-in user's server ID, or `""` when unauthenticated. Used to tag pulled records and to
    /// scope the push/pending queries so a previous user's writes are never pushed under this user.
    private var currentUserID: String {
        clientProvider.currentUserID() ?? ""
    }

    // MARK: Lifecycle

    init(
        clientProvider: StashClientProvider,
        session: SessionRefreshing,
        localStore: LocalStore,
        connectivity: ConnectivityMonitor,
        defaults: UserDefaults,
        smartViewRepository: SmartViewRepository
    ) {
        self.clientProvider = clientProvider
        self.session = session
        self.localStore = localStore
        self.connectivity = connectivity
        self.defaults = defaults
        self.smartViewRepository = smartViewRepository
        lastSyncedAt = defaults.object(forKey: AppGroup.lastSyncedAtKey) as? Date
        let userID = clientProvider.currentUserID() ?? ""
        pendingCount = localStore.pendingCount(userID: userID)
        failedCount = localStore.failedCount(userID: userID)
    }

    // MARK: Static Functions

    /// Whether a push error will never succeed on retry, so the record should be marked failed and
    /// removed from the queue rather than retried forever. Connectivity, auth, and transient server
    /// (5xx) errors are recoverable and left pending; a `422`/`403`/etc. the server keeps rejecting is
    /// permanent. A `token_expired`/`token_invalid` reaching here has *already* been retried once by
    /// `AuthorizedClient` after a forced refresh, so it means the refresh could not recover the session
    /// this cycle — still recoverable (the next cycle re-tries with a token from a fresh login).
    private static func isPermanentFailure(_ error: Error) -> Bool {
        guard let apiError = error as? StashAPIError else {
            return false
        }

        switch apiError {
        case .unknown, .serverError, .tokenExpired, .tokenInvalid, .accountSuspended:
            return false
        case .validationFailed, .forbidden, .notFound, .duplicateURL,
             .usernameTaken, .invalidCredentials, .totpRequired, .totpInvalid:
            return true
        }
    }

    // MARK: Functions

    /// Full sync cycle: pull then push. Safe to call concurrently — subsequent calls await the
    /// in-flight cycle rather than starting a second one.
    func sync() async {
        if let inflightSync {
            await inflightSync.value
            return
        }

        syncGeneration += 1
        let generation = syncGeneration
        let task = Task { await performSync() }
        inflightSync = task
        await task.value

        if syncGeneration == generation {
            inflightSync = nil
        }
    }

    /// Pushes queued local changes **without** a preceding pull. Used after a write: the device just
    /// produced the change, so there is nothing new to pull, and skipping the pull avoids an
    /// unnecessary round-trip and a redundant list refresh per write. Shares the single-flight
    /// `inflightSync` guard — if any cycle is already running this is a no-op, because that cycle's
    /// push phase fetches the pending records fresh and therefore includes this write.
    func pushPending() async {
        guard inflightSync == nil else {
            return
        }

        syncGeneration += 1
        let generation = syncGeneration
        let task = Task { await performPush() }
        inflightSync = task
        await task.value

        if syncGeneration == generation {
            inflightSync = nil
        }
    }

    /// Runs a cycle and then schedules the next background refresh. Called from the background-refresh
    /// handler; the SwiftUI `.backgroundTask` modifier marks the task complete when this returns.
    func syncInBackground() async {
        await sync()
        scheduleBackgroundRefresh()
    }

    /// Asks the system for another background refresh opportunity (~15 minutes out). A no-op where the
    /// background-task entitlement is absent (the submit throws and is ignored).
    func scheduleBackgroundRefresh() {
        BackgroundSyncScheduler.schedule()
    }

    /// Recomputes the queued-change count from the store. Called when the sync status UI appears, so
    /// it reflects offline writes made since the last cycle.
    func refreshPendingCount() {
        let userID = currentUserID
        pendingCount = localStore.pendingCount(userID: userID)
        failedCount = localStore.failedCount(userID: userID)
    }

    /// Dismisses the last sync error (the inline Settings alert). The next cycle also clears it.
    func dismissError() {
        lastSyncError = nil
    }

    /// Deletes the current user's permanently-failed records. The user acknowledges that the
    /// unrecoverable offline changes are lost.
    func clearFailedRecords() {
        localStore.clearFailed(userID: currentUserID)
        refreshPendingCount()
    }

    /// Clears the sync cursor and pending count on sign-out so the next user starts from a full pull.
    ///
    /// Cancels any in-flight cycle first: without this, a cycle racing the sign-out wipe would resume,
    /// `save()` the records the wipe just deleted, and re-persist the cursor — leaving the next user
    /// browsing the previous user's bookmarks. `SyncEngine` is `@MainActor`, so the cancel and the
    /// caller's subsequent wipe run without interleaving, and the cancelled cycle aborts at its next
    /// `pull()`/`push()` cancellation check rather than completing.
    func reset() {
        inflightSync?.cancel()
        inflightSync = nil
        lastSyncedAt = nil
        lastSyncError = nil
        pendingCount = 0
        defaults.removeObject(forKey: AppGroup.lastSyncedAtKey)
    }

    // MARK: - Cycle

    private func performSync() async {
        guard connectivity.isOnline else {
            return
        }

        isSyncing = true
        lastSyncError = nil
        let cycleStart = Date()

        let userID = currentUserID

        do {
            let client = try await session.authorizedClient()
            try await pull(client: client, since: lastSyncedAt, userID: userID)
            localStore.save()
            try await push(client: client, userID: userID)
            localStore.save()
            setLastSyncedAt(cycleStart)
        } catch {
            lastSyncError = error
        }

        try? await smartViewRepository.reload()

        refreshPendingCount()
        isSyncing = false
    }

    private func performPush() async {
        guard connectivity.isOnline else {
            return
        }

        isSyncing = true
        lastSyncError = nil
        let userID = currentUserID

        do {
            let client = try await session.authorizedClient()
            try await push(client: client, userID: userID)
            localStore.save()
        } catch {
            lastSyncError = error
        }

        refreshPendingCount()
        isSyncing = false
    }

    // MARK: - Pull

    private func pull(client: AuthorizedClient, since: Date?, userID: String) async throws {
        try Task.checkCancellation()

        var afterUpdatedAt: String?
        var afterId: UUID?

        while true {
            let request = BookmarkRequestFactory.makeChangesRequest(
                since: since,
                afterUpdatedAt: afterUpdatedAt,
                afterId: afterId,
                perPage: Self.perPage
            )
            let result = try await client.run(request).value
            for dto in result.items {
                mergePulled(dto, userID: userID)
            }

            guard result.hasMore else {
                break
            }

            afterUpdatedAt = result.nextAfterUpdatedAt
            afterId = result.nextAfterId
        }

        let tombstones = try await client.run(BookmarkRequestFactory.makeDeletedRequest(since: since)).value
        for tombstone in tombstones {
            applyTombstone(tombstone)
        }
    }

    private func mergePulled(_ dto: BookmarkDTO, userID: String) {
        guard let local = localStore.record(forServerID: dto.id) else {
            localStore.insert(LocalBookmark(from: dto, userID: userID))
            return
        }
        guard dto.updatedAt > local.serverUpdatedAt else {
            return
        }
        guard let pendingSyncAt = local.pendingSyncAt else {
            local.apply(dto)
            return
        }

        if dto.updatedAt > pendingSyncAt {
            local.apply(dto)
        }
    }

    private func applyTombstone(_ tombstone: DeletedBookmarkDTO) {
        guard let local = localStore.record(forServerID: tombstone.id) else {
            return
        }

        localStore.delete(local)
    }

    // MARK: - Push

    private func push(client: AuthorizedClient, userID: String) async throws {
        try Task.checkCancellation()

        for record in localStore.fetchPending(userID: userID) {
            try await push(record, client: client)
        }
    }

    private func push(_ record: LocalBookmark, client: AuthorizedClient) async throws {
        do {
            if record.locallyDeletedAt != nil {
                try await pushDelete(record, client: client)
            } else if record.isLocalOnly {
                try await pushCreate(record, client: client)
            } else {
                try await pushUpdate(record, client: client)
            }
        } catch let error where error.isConnectivityError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Self.isPermanentFailure(error) {
                record.syncError = error.stashUserMessage
                record.pendingSyncAt = nil
                localStore.save()
            }

            return
        }
    }

    private func pushCreate(_ record: LocalBookmark, client: AuthorizedClient) async throws {
        let request = BookmarkRequestFactory.makeCreateRequest(
            CreateBookmarkRequest(
                url: record.url,
                title: record.title,
                description: record.bookmarkDescription,
                tags: record.tags.isEmpty ? nil : record.tags,
                fetchMetadata: record.wantsMetadataFetch,
                isArchived: record.isArchived,
                isReadLater: record.isReadLater
            )
        )

        do {
            let dto = try await client.run(request).value
            record.apply(dto)
        } catch let StashAPIError.duplicateURL(existingID) {
            try await resolveDuplicate(record, existingID: existingID, client: client)
        }
    }

    private func pushUpdate(_ record: LocalBookmark, client: AuthorizedClient) async throws {
        let request = BookmarkRequestFactory.makeUpdateRequest(
            id: record.serverID,
            body: UpdateBookmarkRequest(
                title: record.title,
                description: record.bookmarkDescription,
                tags: record.tags,
                isArchived: record.isArchived,
                isReadLater: record.isReadLater
            )
        )

        do {
            let dto = try await client.run(request).value
            record.apply(dto)
        } catch StashAPIError.notFound {
            localStore.delete(record)
        }
    }

    private func pushDelete(_ record: LocalBookmark, client: AuthorizedClient) async throws {
        guard !record.isLocalOnly else {
            localStore.delete(record)
            return
        }

        do {
            _ = try await client.run(BookmarkRequestFactory.makeDeleteRequest(id: record.serverID))
            localStore.delete(record)
        } catch StashAPIError.notFound {
            localStore.delete(record)
        }
    }

    /// Resolves a `409 duplicate_url` from pushing an offline-created bookmark: the URL already exists
    /// server-side (saved on another device). Local content wins — we `PUT` the local title,
    /// description, and tags onto the existing server record, then collapse onto whichever local copy
    /// holds that server ID.
    private func resolveDuplicate(_ record: LocalBookmark, existingID: UUID, client: AuthorizedClient) async throws {
        let request = BookmarkRequestFactory.makeUpdateRequest(
            id: existingID,
            body: UpdateBookmarkRequest(
                title: record.title,
                description: record.bookmarkDescription,
                tags: record.tags,
                isArchived: record.isArchived,
                isReadLater: record.isReadLater
            )
        )
        let dto = try await client.run(request).value

        if let existing = localStore.record(forServerID: existingID), existing !== record {
            existing.apply(dto)
            localStore.delete(record)
        } else {
            record.apply(dto)
        }
    }

    // MARK: - Helpers

    private func setLastSyncedAt(_ date: Date) {
        lastSyncedAt = date
        defaults.set(date, forKey: AppGroup.lastSyncedAtKey)
    }
}
