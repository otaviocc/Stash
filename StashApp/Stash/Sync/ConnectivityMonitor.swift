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
import Network

/// Watches the network path via `NWPathMonitor` and reports whether the device is online, firing
/// `onReconnect` when the path transitions from unsatisfied to satisfied.
///
/// `isOnline` drives the offline banner (`MainFlowView`) and gates `SyncEngine`'s cycle attempts;
/// `onReconnect` is wired to trigger a sync as soon as connectivity returns. `BookmarkRepository`
/// does not use it — writes are unconditionally optimistic-local and reconciled by the sync engine.
/// Starts optimistically online; `NWPathMonitor` corrects it on the first path update.
@MainActor
@Observable
final class ConnectivityMonitor {

    // MARK: Properties

    private(set) var isOnline = true

    @ObservationIgnored var onReconnect: (() -> Void)?

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.example.otavio.stash.connectivity")

    // MARK: Lifecycle

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.update(isOnline: online)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    // MARK: Functions

    private func update(isOnline online: Bool) {
        let wasOnline = isOnline
        isOnline = online

        if online, !wasOnline {
            onReconnect?()
        }
    }
}
