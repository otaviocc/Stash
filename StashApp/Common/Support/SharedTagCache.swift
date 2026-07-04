// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

/// A snapshot of the user's tags, shared from the app to the Share Extension through the App Group
/// `UserDefaults` suite.
///
/// The extension is a separate process and cannot open the app's private SwiftData store, so it can't
/// derive tags the way `TagRepository` does. Instead the app writes its derived tag list here on every
/// `derive()`, and the extension seeds its picker from the last snapshot — so tags are available even
/// when the backend is unreachable. This mirrors how the tokens and server URL are shared across the
/// two processes (see `AppGroup`). The snapshot is bounded by the app's last sync, exactly like the
/// app's own offline tags.
enum SharedTagCache {

    /// Persists the given tags as the shared snapshot, JSON-encoded under `AppGroup.knownTagsKey`.
    /// Called by the app whenever it recomputes its tag list.
    static func write(
        _ tags: [Tag]
    ) {
        guard let data = try? JSONEncoder().encode(tags) else {
            return
        }

        AppGroup.makeSharedDefaults().set(data, forKey: AppGroup.knownTagsKey)
    }

    /// Reads the last shared snapshot, returning an empty list if none was written or it cannot be
    /// decoded. Called by the extension to seed its tag picker before any network request.
    static func read() -> [Tag] {
        guard
            let data = AppGroup.makeSharedDefaults().data(forKey: AppGroup.knownTagsKey),
            let tags = try? JSONDecoder().decode([Tag].self, from: data)
        else {
            return []
        }

        return tags
    }

    /// Clears the shared snapshot, so the next user's extension never sees the previous user's tags.
    /// Called by the app on sign-out.
    static func clear() {
        AppGroup.makeSharedDefaults().removeObject(forKey: AppGroup.knownTagsKey)
    }
}
