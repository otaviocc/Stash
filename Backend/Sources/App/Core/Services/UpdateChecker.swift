// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Vapor

// MARK: - UpdateStatus

/// A snapshot of the update-check result, cached on the `Application` so page renders never block
/// on a network call. A failed check (`checkFailed`) leaves the previously known `latestVersion` /
/// `updateAvailable` / `releaseURL` in place; only `lastCheckedAt` and `checkFailed` change, so a
/// single transient GitHub outage doesn't erase a real "update available" the last successful check
/// found.
struct UpdateStatus: Sendable {

    // MARK: Properties

    let currentVersion: String
    let latestVersion: String?
    let updateAvailable: Bool
    let releaseURL: String?
    let lastCheckedAt: Date?
    let checkFailed: Bool

    // MARK: Static Functions

    static func unknown(current: String) -> UpdateStatus {
        UpdateStatus(
            currentVersion: current,
            latestVersion: nil,
            updateAvailable: false,
            releaseURL: nil,
            lastCheckedAt: nil,
            checkFailed: false
        )
    }
}

// MARK: - UpdateStatusCache

/// Thread-safe holder for the cached update status, mirroring `SiteSettingsCache`'s shape, plus a
/// single-flight "checking" flag so `refreshIfStale` never starts a second concurrent check while
/// one is already in progress.
final class UpdateStatusCache: @unchecked Sendable {

    // MARK: Properties

    private let lock = NSLock()
    private var status: UpdateStatus
    private var checking = false

    // MARK: Computed Properties

    var current: UpdateStatus {
        lock.withLock { status }
    }

    // MARK: Lifecycle

    init(_ status: UpdateStatus) {
        self.status = status
    }

    // MARK: Functions

    func update(_ status: UpdateStatus) {
        lock.withLock { self.status = status }
    }

    /// Atomically claims the "checking" flag. Returns `false` (and claims nothing) if a check is
    /// already in flight.
    func beginCheckIfIdle() -> Bool {
        lock.withLock {
            guard !checking else { return false }

            checking = true
            return true
        }
    }

    func endCheck() {
        lock.withLock { checking = false }
    }
}

// MARK: - UpdateStatusCacheKey

/// Storage key for the cached update status.
struct UpdateStatusCacheKey: StorageKey {

    typealias Value = UpdateStatusCache
}

// MARK: - GitHubRelease

/// Decoded shape of GitHub's `GET /repos/:owner/:repo/releases/latest` response: only the two
/// fields this feature actually needs.
private struct GitHubRelease: Decodable {

    // MARK: Nested Types

    enum CodingKeys: String, CodingKey {

        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    // MARK: Properties

    let tagName: String
    let htmlURL: String
}

// MARK: - UpdateChecker

/// Checks GitHub Releases for a newer `StashRepo.path` release than the one currently running
/// (`AppVersionKey` / the `VERSION` file), and caches the result so admin page renders never block
/// on network. Modeled on `SiteSettingsService`'s app-level-cache pattern and
/// `WaybackSubmitter`'s detached-refresh pattern. A container can't self-update, so this only ever
/// surfaces "a newer version exists"; the actual upgrade is a `docker/podman compose pull && up
/// -d` the admin runs by hand; see `/admin/health`.
enum UpdateChecker {

    // MARK: Static Properties

    /// How long a cached result is considered fresh before `refreshIfStale` kicks off another check.
    /// Checking once a day is generous enough that a real release is noticed promptly without
    /// hammering the GitHub API on every dashboard/health page view.
    static let staleAfter: TimeInterval = 24 * 60 * 60

    private static let releaseAPIURL = "https://api.github.com/repos/\(StashRepo.path)/releases/latest"

    // MARK: Static Functions

    /// Seeds the cache with an "unknown" status and, outside `.testing`, kicks one detached check so
    /// the dashboard/health pages have a real answer shortly after boot rather than only after an
    /// admin happens to load a page more than a day later. Call once, from `configure.swift`, after
    /// the site-settings cache is seeded (the enabled/disabled toggle lives there).
    static func bootstrap(on app: Application) {
        let current = app.storage[AppVersionKey.self] ?? "dev"
        app.storage[UpdateStatusCacheKey.self] = UpdateStatusCache(.unknown(current: current))

        refreshIfStale(on: app)
    }

    /// Kicks off a detached background check when update-checking is enabled and the cached result
    /// is missing or stale. Safe to call on every dashboard/health render: it's a cheap no-op when a
    /// check is already fresh, already in flight, disabled by the admin, or under `.testing`.
    static func refreshIfStale(on app: Application) {
        guard app.environment != .testing else { return }
        guard app.storage[SiteSettingsCacheKey.self]?.current.updateCheckEnabled ?? true else { return }
        guard let cache = app.storage[UpdateStatusCacheKey.self] else { return }

        if let lastCheckedAt = cache.current.lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < staleAfter {
            return
        }

        guard cache.beginCheckIfIdle() else { return }

        Task.detached {
            await check(on: app)
            cache.endCheck()
        }
    }

    /// Forces an immediate check regardless of staleness (the admin's "Check now" button on
    /// `/admin/health`), still respecting the enable/disable toggle and the single-flight guard so it
    /// can't race a background `refreshIfStale` check. Suppressed under `.testing`, the same as every
    /// other outbound call this app makes (`WaybackSubmitter.kick`, `FaviconFetcher`'s detached
    /// fetches), so the test suite never makes a real network call.
    ///
    /// Returns whether a check actually ran, so the caller can tell the admin apart "just checked"
    /// from "skipped" (disabled, or a check was already in flight) rather than always claiming
    /// success.
    @discardableResult
    static func forceCheck(on app: Application) async -> Bool {
        guard app.environment != .testing else { return false }
        guard app.storage[SiteSettingsCacheKey.self]?.current.updateCheckEnabled ?? true else { return false }
        guard let cache = app.storage[UpdateStatusCacheKey.self] else { return false }
        guard cache.beginCheckIfIdle() else { return false }

        await check(on: app)
        cache.endCheck()
        return true
    }

    /// Parses `v1.2.3` / `1.2.3`-style versions into `(major, minor, patch)` and returns whether
    /// `latest` is strictly newer than `current`. A `current` of `"dev"` (no `VERSION` file, a
    /// from-source dev build) never reports an update available, since there's no meaningful released
    /// version to compare against. An unparseable `current` or `latest` also never reports an update,
    /// rather than risking a false positive from a malformed tag. Pure and unit-tested independent of
    /// any network call.
    static func compareSemver(current: String, latest: String) -> Bool {
        guard current != "dev", let currentParts = parse(current), let latestParts = parse(latest) else {
            return false
        }

        return latestParts > currentParts
    }

    /// Performs the actual GitHub API call and writes the result into the cache. Never throws: any
    /// failure (network, non-2xx, decode) is recorded as `checkFailed` rather than propagated, since a
    /// failed update check must never affect anything else on the page, matching the same
    /// never-throws contract `MetadataFetcher.fetch` and `FaviconFetcher` already follow for their own
    /// outbound calls.
    private static func check(on app: Application) async {
        guard let cache = app.storage[UpdateStatusCacheKey.self] else { return }

        let current = app.storage[AppVersionKey.self] ?? "dev"

        do {
            var headers = HTTPHeaders()
            headers.add(name: .userAgent, value: StashUserAgent.value)
            headers.add(name: .accept, value: "application/vnd.github+json")

            let response = try await app.client.get(URI(string: releaseAPIURL), headers: headers)
            guard response.status == .ok, let body = response.body else {
                throw Abort(.badGateway)
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(buffer: body))
            let available = compareSemver(current: current, latest: release.tagName)

            cache.update(UpdateStatus(
                currentVersion: current,
                latestVersion: release.tagName,
                updateAvailable: available,
                releaseURL: release.htmlURL,
                lastCheckedAt: Date(),
                checkFailed: false
            ))
        } catch {
            app.logger.notice("Update check failed: \(String(reflecting: error))")
            let previous = cache.current
            cache.update(UpdateStatus(
                currentVersion: current,
                latestVersion: previous.latestVersion,
                updateAvailable: previous.updateAvailable,
                releaseURL: previous.releaseURL,
                lastCheckedAt: Date(),
                checkFailed: true
            ))
        }
    }

    /// Every component must be a clean integer: a qualifier like `3rc` or `3-beta` makes the whole
    /// tag unparseable rather than silently truncating to patch `3`, which could make a
    /// pre-release/qualified tag compare as equal to (and so hide) a genuine new release.
    private static func parse(_ raw: String) -> (Int, Int, Int)? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }

        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2])
        else {
            return nil
        }

        return (major, minor, patch)
    }
}
