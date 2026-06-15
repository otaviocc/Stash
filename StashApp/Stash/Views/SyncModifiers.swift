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
