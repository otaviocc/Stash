// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Logging

// MARK: - LogRingBuffer

/// Fixed-capacity, thread-safe holder for recent log lines, used by the `/admin/logs` viewer.
/// Mirrors the `NSLock`-guarded holder idiom used by `SiteSettingsCache`
/// (`Core/Services/SiteSettingsService.swift`) rather than an actor or `DispatchQueue`, to stay
/// consistent with the rest of the codebase. Entries are appended by `RingBufferLogHandler` on
/// every log call across the whole app; oldest entries are dropped once `capacity` is exceeded.
/// This is deliberately ephemeral — nothing here is ever written to disk or the database. See
/// DECISIONS.md, "Feature #8: System Logs" for why.
final class LogRingBuffer: @unchecked Sendable {

    // MARK: Nested Types

    // MARK: - Entry

    struct Entry: Sendable {

        let timestamp: Date
        let level: Logger.Level
        let label: String
        let message: String
    }

    // MARK: Properties

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let capacity: Int

    // MARK: Lifecycle

    init(capacity: Int = 1000) {
        self.capacity = capacity
    }

    // MARK: Functions

    /// Appends a new entry, dropping the oldest entries first if `capacity` would be exceeded.
    func append(_ entry: Entry) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)

        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// Returns a snapshot of buffered entries, newest first, optionally filtered to `level` and
    /// above (`Logger.Level` is `Comparable`, so `>=` works directly — `.error` is "greater than"
    /// `.info`).
    func snapshot(level: Logger.Level? = nil) -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        let filtered = level.map { minLevel in entries.filter { $0.level >= minLevel } } ?? entries

        return Array(filtered.reversed())
    }
}
