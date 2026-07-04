// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

extension View {

    /// Runs `action` each time a sync cycle finishes — the sync engine transitioning from syncing back
    /// to idle. Views backed by a local-store-derived repository (the bookmark list, the tag sidebars)
    /// use this to re-derive once a pull may have changed their source data, rather than re-inlining the
    /// same `onChange(of: syncEngine.isSyncing)` observation at every call site.
    func onSyncCompleted(perform action: @escaping () -> Void) -> some View {
        modifier(SyncCompletionModifier(action: action))
    }
}

// MARK: - SyncCompletionModifier

/// Observes `SyncEngine.isSyncing` and fires `action` on the syncing-to-idle transition.
private struct SyncCompletionModifier: ViewModifier {

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment

    // MARK: Properties

    let action: () -> Void

    // MARK: Content Methods

    func body(content: Content) -> some View {
        content
            .onChange(of: environment.syncEngine.isSyncing) { _, isSyncing in
                if !isSyncing {
                    action()
                }
            }
    }
}
