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

    // MARK: Computed Properties

    var mainContext: ModelContext {
        container.mainContext
    }

    // MARK: Lifecycle

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
            fatalError("Failed to create the local bookmark store: \(error)")
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

    /// Every record with a queued offline change waiting to be pushed.
    func fetchPending() -> [LocalBookmark] {
        let descriptor = FetchDescriptor<LocalBookmark>(
            predicate: #Predicate { $0.pendingSyncAt != nil }
        )

        return (try? mainContext.fetch(descriptor)) ?? []
    }

    /// The number of records waiting to be pushed.
    func pendingCount() -> Int {
        let descriptor = FetchDescriptor<LocalBookmark>(
            predicate: #Predicate { $0.pendingSyncAt != nil }
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

    /// Inserts the bookmark, or applies the DTO to the existing record with the same `serverID`.
    func upsert(_ dto: BookmarkDTO) {
        if let existing = record(forServerID: dto.id) {
            existing.apply(dto)
        } else {
            mainContext.insert(LocalBookmark(from: dto))
        }
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

    /// Deletes every local bookmark — used on sign-out so the next user starts clean.
    func wipe() {
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
