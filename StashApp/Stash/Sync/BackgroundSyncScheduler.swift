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
/// reconnect, and foreground — no background mechanism is needed or planned there. `taskIdentifier`
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
