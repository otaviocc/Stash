// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
#if os(iOS)
    import BackgroundTasks
#endif

// MARK: - BackgroundSyncScheduler

/// Schedules the recurring background-refresh sync. The matching handler is registered by the
/// `.backgroundTask(.appRefresh:)` scene modifier in `StashApp`.
///
/// iOS-only by design: `BGAppRefreshTask` and SwiftUI's `.appRefresh` background task live in
/// `BackgroundTasks.framework`, which does not exist on macOS. macOS instead syncs on launch,
/// reconnect, and foreground; no background mechanism is needed or planned there. `taskIdentifier`
/// is declared in both `Info.plist`s under `BGTaskSchedulerPermittedIdentifiers`.
enum BackgroundSyncScheduler {

    // MARK: Static Properties

    static let taskIdentifier = "\(AppGroup.bundleBase).backgroundSync"

    // MARK: Static Functions

    static func schedule() {
        #if os(iOS)
            let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
            try? BGTaskScheduler.shared.submit(request)
        #endif
    }
}
