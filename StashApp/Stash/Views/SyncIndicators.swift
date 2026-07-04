// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - OfflineBanner

/// A slim, informational banner shown at the top of the app shell while the device is offline.
///
/// Muted rather than alarming — being offline is a supported state, and queued changes sync on
/// reconnect. Applied as a `.safeAreaInset(edge: .top)` on the main shells, which animate it in and
/// out as connectivity changes.
struct OfflineBanner: View {

    // MARK: Content

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.circle")
            Text("Working offline — changes will sync when reconnected")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(.bar)
    }
}

// MARK: - PendingSyncBadge

/// A small trailing indicator for a bookmark's sync state. Muted when a local change is still waiting
/// to be pushed; an orange warning when the push failed permanently. It carries no action —
/// interaction with the bookmark is never blocked — and disappears once the change syncs or is cleared.
struct PendingSyncBadge: View {

    // MARK: Properties

    let failed: Bool

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Image(systemName: failed ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
            .font(.caption)
            .foregroundStyle(failed ? Color.orange : Color.secondary)
            .accessibilityLabel(failed ? "Sync failed" : "Waiting to sync")
    }
}

#if DEBUG
    #Preview {
        VStack(spacing: 0) {
            OfflineBanner()
            Spacer()
            PendingSyncBadge(failed: false)
            PendingSyncBadge(failed: true)
            Spacer()
        }
    }
#endif
