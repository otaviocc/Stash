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
import SwiftData

/// Owns the SwiftData `ModelContainer` for the local bookmark copy and vends its main context.
///
/// The container is created once by `AppEnvironment` and shared by every `BookmarkRepository` and the
/// `TagRepository`, so all reads see the same store. All access runs on the main actor — the store is
/// small (one user's bookmarks) and the repositories that touch it are `@MainActor`. The Share
/// Extension stays online-only and never opens this store.
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

    /// Initialises the SwiftData container for the local bookmark store.
    ///
    /// If container creation fails (corrupt file, incompatible schema), the store is deleted and
    /// recreated from scratch and `didResetOnInit` is set. The `SyncEngine` re-seeds from the server on
    /// the next sync cycle. This is preferable to crashing, since the local store is a disposable cache;
    /// a `fatalError` remains only for the case where even a fresh store cannot be created.
    init(inMemory: Bool = false) {
        let schema = Schema([LocalBookmark.self])
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

    /// All bookmarks the user still has locally — those not soft-deleted offline.
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

    /// Removes every record matching `serverID` (the server confirmed the deletion).
    func remove(serverID: UUID) {
        let descriptor = FetchDescriptor<LocalBookmark>(
            predicate: #Predicate { $0.serverID == serverID }
        )
        for record in (try? mainContext.fetch(descriptor)) ?? [] {
            mainContext.delete(record)
        }
    }

    /// Deletes the already-synced local bookmarks, used on sign-out so the next sign-in starts from a
    /// fresh copy — but **preserves any record with a queued offline change** (`pendingSyncAt != nil`,
    /// which also covers offline soft-deletes). Unpushed writes therefore survive a forced logout from
    /// an involuntary session expiry and push on the next sign-in, rather than being silently lost.
    ///
    /// When `currentUserID` is known, only that user's pending records are preserved — any other user's
    /// leftover pending records are also dropped. When it is `nil` (the usual case at involuntary
    /// expiry, where tokens are already cleared), it conservatively preserves all pending records; the
    /// per-user push filter (`fetchPending(userID:)`) still prevents pushing them under the wrong user.
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
    /// Used on explicit sign-out so the next user starts from a complete clean slate.
    func wipeAll() {
        try? mainContext.delete(model: LocalBookmark.self)
        try? mainContext.save()
    }

    func save() {
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
