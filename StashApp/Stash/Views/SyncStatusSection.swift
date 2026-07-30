// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - SyncStatusSection

/// The Settings "Sync" section for the iOS settings screen (a grouped `Form` section). A thin wrapper
/// around `SyncStatusRows`; the macOS General tab — which is a `ScrollView`/`VStack`, not a `Form` —
/// renders `SyncStatusRows` directly under its own header, so the two platforms share the row content
/// while keeping their native containers.
struct SyncStatusSection: View {

    // MARK: Content

    var body: some View {
        Section("Sync") {
            SyncStatusRows()
        }
    }
}

// MARK: - SyncStatusRows

/// The "Sync" rows shared by the iOS `Form` section and the macOS General tab's `VStack`.
///
/// Shows when the last sync completed, how many changes are queued (only when any are), a manual
/// "Sync Now" control, and — if the last attempt failed — a dismissible inline notice. Sync is a
/// background concern, so errors are surfaced here rather than as a blocking modal. The rows are a
/// flat `Group` so a `Form` renders them as separate cells while a `VStack` stacks them.
struct SyncStatusRows: View {

    // MARK: Static Properties

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    // MARK: SwiftUI Properties

    @Environment(AppEnvironment.self) private var environment

    // MARK: Computed Properties

    private var pendingChangesText: String {
        let count = environment.syncEngine.pendingCount

        return count == 1 ? "1 bookmark" : "\(count) bookmarks"
    }

    private var failedChangesText: String {
        let count = environment.syncEngine.failedCount

        return count == 1 ? "1 bookmark" : "\(count) bookmarks"
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        LabeledContent("Last synced") {
            makeLastSyncedValue()
        }
        .task {
            environment.syncEngine.refreshPendingCount()
        }

        if environment.syncEngine.pendingCount > 0 {
            LabeledContent("Pending changes", value: pendingChangesText)
        }

        if environment.syncEngine.failedCount > 0 {
            makeFailedRow()
        }

        if environment.syncEngine.lastSyncFailed {
            makeErrorNotice()
        }

        makeSyncButton()
    }

    // MARK: Content Methods

    /// The "Last synced" value, refreshed once a second by a `TimelineView` so the relative phrasing
    /// ("5 seconds ago" → "2 minutes ago") advances on screen instead of freezing at render time.
    @ViewBuilder
    private func makeLastSyncedValue() -> some View {
        if let lastSyncedAt = environment.syncEngine.lastSyncedAt {
            TimelineView(.periodic(from: lastSyncedAt, by: 1)) { context in
                Text(Self.relativeFormatter.localizedString(for: lastSyncedAt, relativeTo: context.date))
            }
        } else {
            Text("Never")
        }
    }

    private func makeFailedRow() -> some View {
        LabeledContent("Failed to sync") {
            HStack(spacing: 12) {
                Text(failedChangesText)
                    .foregroundStyle(.secondary)
                Button("Clear") {
                    environment.syncEngine.clearFailedRecords()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func makeErrorNotice() -> some View {
        HStack(spacing: 8) {
            Label("Sync failed — tap Sync Now to retry", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .font(.footnote)
            Spacer()
            Button {
                environment.syncEngine.dismissError()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
    }

    private func makeSyncButton() -> some View {
        HStack {
            Button(action: syncNow) {
                if environment.syncEngine.isSyncing {
                    ProgressView()
                } else {
                    Text("Sync Now")
                }
            }
            .buttonStyle(.bordered)
            .disabled(environment.syncEngine.isSyncing)

            Spacer()
        }
    }

    // MARK: Functions

    private func syncNow() {
        Task {
            await environment.syncEngine.sync()
            environment.syncEngine.refreshPendingCount()
        }
    }
}

#if DEBUG
    #Preview {
        Form {
            SyncStatusSection()
        }
        .formStyle(.grouped)
        .environment(AppEnvironment.preview)
    }
#endif
