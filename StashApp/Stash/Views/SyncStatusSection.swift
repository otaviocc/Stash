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

import SwiftUI

// MARK: - SyncStatusSection

/// The Settings "Sync" section, shared by the iOS settings screen and the macOS General tab.
///
/// Shows when the last sync completed, how many changes are queued (only when any are), a manual
/// "Sync Now" control, and — if the last attempt failed — a dismissible inline notice. Sync is a
/// background concern, so errors are surfaced here rather than as a blocking modal.
struct SyncStatusSection: View {

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
        Section("Sync") {
            LabeledContent("Last synced") {
                makeLastSyncedValue()
            }

            if environment.syncEngine.pendingCount > 0 {
                LabeledContent("Pending changes", value: pendingChangesText)
            }

            if environment.syncEngine.failedCount > 0 {
                makeFailedRow()
            }

            if environment.syncEngine.lastSyncError != nil {
                makeErrorNotice()
            }

            makeSyncButton()
        }
        .task {
            environment.syncEngine.refreshPendingCount()
        }
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
        Button(action: syncNow) {
            if environment.syncEngine.isSyncing {
                ProgressView()
            } else {
                Text("Sync Now")
            }
        }
        .disabled(environment.syncEngine.isSyncing)
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
