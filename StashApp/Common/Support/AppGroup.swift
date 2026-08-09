// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

/// Shared App Group configuration used by both the main app and the Share Extension.
///
/// The two processes share the access token, refresh token, and configured server URL through this
/// group: the tokens via a Keychain access group (`KeychainStore(accessGroup:)`) and the server URL
/// via the group's `UserDefaults` suite. The main app writes them; the extension reads them.
enum AppGroup {

    // MARK: Static Properties

    /// The reverse-DNS bundle base (everything before the per-identifier suffix), e.g.
    /// `com.example.otavio.stash` by default, or `com.yourname.stash` once you've set your own
    /// `STASH_BUNDLE_PREFIX`. Read from the `STBundleBase` Info.plist key, which the build injects
    /// from the `STASH_BUNDLE_PREFIX` xcconfig setting (`$(STASH_BUNDLE_PREFIX).stash`), so the App
    /// Group, Keychain access group, and defaults suite stay in lockstep with the bundle IDs and
    /// entitlements across machines. The key is absent only in SwiftUI previews (which have no real
    /// bundle), where it falls back to the default prefix; a real app or extension bundle that is
    /// missing it asserts, because silently resolving to the fallback prefix would point at an App
    /// Group the entitlement does not grant.
    static let bundleBase: String = {
        guard
            let base = Bundle.main.object(forInfoDictionaryKey: "STBundleBase") as? String,
            !base.isEmpty
        else {
            assert(
                ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1",
                "STBundleBase missing from Info.plist; the App Group would silently use the fallback prefix"
            )

            return "com.example.otavio.stash"
        }

        return base
    }()

    static let identifier = "group.\(bundleBase)"
    static let accessTokenKey = "\(bundleBase).accessToken"
    static let refreshTokenKey = "\(bundleBase).refreshToken"
    static let serverURLKey = "serverURL"

    /// The user's preferred browser for opening bookmark links (in-app or default). App-only; the
    /// Share Extension does not open links.
    static let browserPreferenceKey = "browserPreference"

    /// Whether in-app links open in Safari's Reader mode where available. App-only.
    static let readerModeKey = "readerMode"

    /// The bundle identifier of the user's chosen browser for opening bookmark links on macOS. `nil`
    /// (the key absent) means the system default browser. App-only, macOS-only: iOS/iPadOS use
    /// `browserPreferenceKey` instead.
    static let macBrowserKey = "macBrowser"

    /// The `SyncEngine` delta cursor: the start time of the last successful sync, used as `since=` on
    /// the next pull. Absent until the first full sync completes; reset on sign-out. App-only; the
    /// Share Extension does not read it.
    static let lastSyncedAtKey = "\(bundleBase).lastSyncedAt"

    /// The user's tag list, cached by the app (`TagRepository.derive()`) so the Share Extension can
    /// offer the tag picker offline; the extension cannot open the app's private SwiftData store, so
    /// it seeds from this snapshot instead. Written on every derive, cleared on sign-out; read by the
    /// extension via `SharedTagCache`.
    static let knownTagsKey = "\(bundleBase).knownTags"

    // MARK: Static Functions

    /// Builds the `UserDefaults` suite backed by the App Group, so the server URL is visible to both
    /// the main app and the extension. Falls back to `.standard` if the suite cannot be opened. Call
    /// once at a composition root and inject the result.
    static func makeSharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
