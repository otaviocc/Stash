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

import Fluent
import Foundation
import Vapor

// MARK: - SiteSettingsSnapshot

/// An immutable, `Sendable` copy of the instance settings, cached on the `Application` so page
/// renders never hit the database. Built from the single `SiteSettings` row.
struct SiteSettingsSnapshot {

    // MARK: Static Properties

    static let `default` = SiteSettingsSnapshot(
        accentTheme: AccentTheme.default.id,
        aboutText: nil,
        footerCustomLabel: nil,
        footerCustomURL: nil
    )

    // MARK: Properties

    let accentTheme: String
    let aboutText: String?
    let footerCustomLabel: String?
    let footerCustomURL: String?

    // MARK: Lifecycle

    init(accentTheme: String, aboutText: String?, footerCustomLabel: String?, footerCustomURL: String?) {
        self.accentTheme = accentTheme
        self.aboutText = aboutText
        self.footerCustomLabel = footerCustomLabel
        self.footerCustomURL = footerCustomURL
    }

    init(_ settings: SiteSettings) {
        self.init(
            accentTheme: settings.accentTheme,
            aboutText: settings.aboutText,
            footerCustomLabel: settings.footerCustomLabel,
            footerCustomURL: settings.footerCustomURL
        )
    }
}

// MARK: - SiteSettingsCache

/// Thread-safe holder for the cached settings snapshot, stored on `Application.storage`. The
/// snapshot is loaded once at boot and replaced whenever the admin saves the appearance form.
final class SiteSettingsCache: @unchecked Sendable {

    // MARK: Properties

    private let lock = NSLock()
    private var snapshot: SiteSettingsSnapshot

    // MARK: Computed Properties

    var current: SiteSettingsSnapshot {
        lock.withLock { snapshot }
    }

    // MARK: Lifecycle

    init(_ snapshot: SiteSettingsSnapshot) {
        self.snapshot = snapshot
    }

    // MARK: Functions

    func update(_ snapshot: SiteSettingsSnapshot) {
        lock.withLock { self.snapshot = snapshot }
    }
}

// MARK: - SiteSettingsCacheKey

/// Storage key for the cached site settings snapshot.
struct SiteSettingsCacheKey: StorageKey {

    typealias Value = SiteSettingsCache
}

// MARK: - SiteSettingsService

/// Loads, caches, and updates the single `SiteSettings` row. The row always exists; it is created
/// on first access if somehow missing so callers never deal with an empty table.
enum SiteSettingsService {

    static func current(on db: any Database) async throws -> SiteSettings {
        if let existing = try await SiteSettings.query(on: db).first() {
            return existing
        }

        let settings = SiteSettings(accentTheme: AccentTheme.default.id)
        try await settings.save(on: db)
        return settings
    }

    static func loadAndCache(on app: Application) async throws {
        let settings = try await current(on: app.db)
        app.storage[SiteSettingsCacheKey.self] = SiteSettingsCache(SiteSettingsSnapshot(settings))
    }

    /// Replaces the cached snapshot in place after the admin saves the appearance form.
    ///
    /// The cache is seeded by `loadAndCache` during `configure`, before the server accepts
    /// connections, so the holder always exists by the time any request can call this. Updating it in
    /// place only touches the `NSLock`-guarded snapshot — it never mutates `Application.storage`, which
    /// is an unsynchronized dictionary that must not be written while request handlers read it
    /// concurrently. If the holder is somehow absent, page renders fall back to `.default` until the
    /// next boot rather than racing a runtime `storage` write.
    static func refreshCache(with settings: SiteSettings, on app: Application) {
        guard let cache = app.storage[SiteSettingsCacheKey.self] else {
            app.logger.error("SiteSettingsCache missing at refresh; it is seeded at boot by loadAndCache")
            return
        }

        cache.update(SiteSettingsSnapshot(settings))
    }
}
