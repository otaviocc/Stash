// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit
import SwiftData

/// Owns the SwiftData `ModelContainer` for the local bookmark and Smart View copy, and vends its main
/// context.
///
/// The container is created once by `AppEnvironment` and shared by every `BookmarkRepository`, the
/// `TagRepository`, and `SmartViewRepository`, so all reads see the same store. All access runs on the
/// main actor: the store is small (one user's bookmarks and Smart Views) and the repositories that
/// touch it are `@MainActor`. The Share Extension stays online-only and never opens this store.
@MainActor
final class LocalStore {

    // MARK: Properties

    let container: ModelContainer

    /// True when the on-disk store was corrupt/incompatible and had to be deleted and recreated during
    /// `init`. `AppEnvironment` reads this to drop the sync cursor so the next sync is a full pull that
    /// rebuilds the now-empty store, rather than a delta that would leave it incomplete.
    private(set) var didResetOnInit = false

    // MARK: Computed Properties

    var mainContext: ModelContext {
        container.mainContext
    }

    // MARK: Lifecycle

    /// If container creation fails (corrupt file, incompatible schema), the store is deleted and
    /// recreated from scratch and `didResetOnInit` is set. The `SyncEngine` re-seeds from the server on
    /// the next sync cycle. This is preferable to crashing, since the local store is a disposable cache;
    /// a `fatalError` remains only for the case where even a fresh store cannot be created.
    init(inMemory: Bool = false) {
        let schema = Schema([LocalBookmark.self, LocalSmartView.self])
        let configuration = ModelConfiguration(
            "StashLocal",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            Self.removeStoreFiles(at: configuration.url)
            didResetOnInit = true

            do {
                container = try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("LocalStore: failed to create ModelContainer even after wipe: \(error)")
            }
        }
    }

    // MARK: Static Functions

    /// Removes the SQLite store file and its `-wal` / `-shm` sidecars, so a retry starts clean.
    private static func removeStoreFiles(at url: URL?) {
        guard let url else { return }

        let manager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let sidecar = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + suffix)
            try? manager.removeItem(at: sidecar)
        }
    }

    // MARK: Functions

    /// All bookmarks the user still has locally: those not soft-deleted offline.
    func fetchActive() -> [LocalBookmark] {
        let descriptor = FetchDescriptor<LocalBookmark>(
            predicate: #Predicate { $0.locallyDeletedAt == nil }
        )

        return (try? mainContext.fetch(descriptor)) ?? []
    }

    /// The given user's records with a queued offline change waiting to be pushed. Scoped by `userID`
    /// so a previous user's preserved writes are never pushed under the current user's token.
    func fetchPending(userID: String) -> [LocalBookmark] {
        let descriptor = FetchDescriptor<LocalBookmark>(
            predicate: #Predicate { $0.pendingSyncAt != nil && $0.userID == userID }
        )

        return (try? mainContext.fetch(descriptor)) ?? []
    }

    /// The number of the given user's records waiting to be pushed.
    func pendingCount(userID: String) -> Int {
        let descriptor = FetchDescriptor<LocalBookmark>(
            predicate: #Predicate { $0.pendingSyncAt != nil && $0.userID == userID }
        )

        return (try? mainContext.fetchCount(descriptor)) ?? 0
    }

    /// The number of the given user's records that failed to push permanently.
    func failedCount(userID: String) -> Int {
        let descriptor = FetchDescriptor<LocalBookmark>(
            predicate: #Predicate { $0.syncError != nil && $0.userID == userID }
        )

        return (try? mainContext.fetchCount(descriptor)) ?? 0
    }

    /// Deletes the given user's permanently-failed records; the user has acknowledged losing the
    /// unrecoverable offline changes.
    func clearFailed(userID: String) {
        try? mainContext.delete(
            model: LocalBookmark.self,
            where: #Predicate { $0.syncError != nil && $0.userID == userID }
        )
        try? mainContext.save()
    }

    func record(forServerID serverID: UUID) -> LocalBookmark? {
        let descriptor = FetchDescriptor<LocalBookmark>(
            predicate: #Predicate { $0.serverID == serverID }
        )

        return try? mainContext.fetch(descriptor).first
    }

    func insert(_ record: LocalBookmark) {
        mainContext.insert(record)
    }

    func delete(_ record: LocalBookmark) {
        mainContext.delete(record)
    }

    /// Deletes the already-synced local bookmarks, used on sign-out so the next sign-in starts from a
    /// fresh copy, but **preserves any record with a queued offline change** (`pendingSyncAt != nil`,
    /// which also covers offline soft-deletes). Unpushed writes therefore survive a forced logout from
    /// an involuntary session expiry and push on the next sign-in, rather than being silently lost.
    ///
    /// When `currentUserID` is known, only that user's pending records are preserved; any other user's
    /// leftover pending records are also dropped. When it is `nil` (the usual case at involuntary
    /// expiry, where tokens are already cleared), it conservatively preserves all pending records; the
    /// per-user push filter (`fetchPending(userID:)`) still prevents pushing them under the wrong user.
    ///
    /// Deliberately leaves every `LocalSmartView` row untouched, unlike `wipeAll()`. There is no
    /// "pending" state to preserve for Smart Views (they are never authored offline), so the only
    /// question is whether a stale cache can leak to a different user, and it cannot, since every
    /// Smart View read is scoped by `userID` (`fetchSmartViews(userID:)`). Leaving the cache in place
    /// means the *same* user's Smart Views survive an involuntary session clear and are available
    /// immediately, offline, the moment they sign back in.
    func wipe(currentUserID: String?) {
        if let currentUserID {
            try? mainContext.delete(
                model: LocalBookmark.self,
                where: #Predicate { $0.pendingSyncAt == nil || $0.userID != currentUserID }
            )
        } else {
            try? mainContext.delete(
                model: LocalBookmark.self,
                where: #Predicate { $0.pendingSyncAt == nil }
            )
        }
        try? mainContext.save()
    }

    /// Deletes every local bookmark unconditionally, including records with pending offline writes.
    /// Used on explicit sign-out so the next user starts from a complete clean slate. Also wipes every
    /// cached `LocalSmartView`, unlike `wipe(currentUserID:)`; see that method's doc comment for why
    /// Smart Views are treated differently there.
    func wipeAll() {
        try? mainContext.delete(model: LocalBookmark.self)
        try? mainContext.delete(model: LocalSmartView.self)
        try? mainContext.save()
    }

    func save() {
        try? mainContext.save()
    }

    // MARK: - Smart Views

    /// The given user's cached Smart View definitions, sorted by name. Scoped by `userID` from the
    /// start (unlike `LocalBookmark`, whose read path was left unscoped and later logged as a residual
    /// gap), so a previous user's rows left behind by `wipe(currentUserID:)` are never visible to a
    /// different signed-in user.
    func fetchSmartViews(userID: String) -> [LocalSmartView] {
        let descriptor = FetchDescriptor<LocalSmartView>(
            predicate: #Predicate { $0.userID == userID },
            sortBy: [SortDescriptor(\.name)]
        )

        return (try? mainContext.fetch(descriptor)) ?? []
    }

    /// Full-replace reconciliation against the given user's cached Smart Views: `GET /smart-views`
    /// always returns the complete, unpaginated list, so, unlike bookmarks, there is no delta/
    /// tombstone endpoint to reconcile against. Existing rows are updated in place, new ones inserted,
    /// and any local row absent from `dtos` (deleted elsewhere: the web, another device) is removed.
    func replaceSmartViews(_ dtos: [SmartViewDTO], userID: String) {
        var existingByID = Dictionary(
            uniqueKeysWithValues: fetchSmartViews(userID: userID).map { ($0.id, $0) }
        )

        for dto in dtos {
            if let existing = existingByID.removeValue(forKey: dto.id) {
                existing.apply(dto)
            } else {
                mainContext.insert(LocalSmartView(dto: dto, userID: userID))
            }
        }

        for orphan in existingByID.values {
            mainContext.delete(orphan)
        }

        try? mainContext.save()
    }

    /// Inserts or updates a single cached Smart View, used right after an authored create/update so the
    /// on-disk cache reflects the change immediately rather than waiting for the next full list refresh.
    func upsertSmartView(_ dto: SmartViewDTO, userID: String) {
        let id = dto.id
        let descriptor = FetchDescriptor<LocalSmartView>(predicate: #Predicate { $0.id == id })

        if let existing = try? mainContext.fetch(descriptor).first {
            existing.apply(dto)
        } else {
            mainContext.insert(LocalSmartView(dto: dto, userID: userID))
        }

        try? mainContext.save()
    }

    /// Removes a single cached Smart View, used right after a successful authored delete.
    func deleteSmartView(id: UUID) {
        try? mainContext.delete(model: LocalSmartView.self, where: #Predicate { $0.id == id })
        try? mainContext.save()
    }

    #if DEBUG
        func insertPreviewSamples(_ bookmarks: [Bookmark]) {
            for bookmark in bookmarks {
                mainContext.insert(LocalBookmark(previewBookmark: bookmark))
            }
            save()
        }
    #endif
}
