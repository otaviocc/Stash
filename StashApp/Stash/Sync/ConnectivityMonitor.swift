// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import Network

/// Watches the network path via `NWPathMonitor` and reports whether the device is online, firing
/// `onReconnect` when the path transitions from unsatisfied to satisfied.
///
/// `isOnline` drives the offline banner (`MainFlowView`) and gates `SyncEngine`'s cycle attempts;
/// `onReconnect` is wired to trigger a sync as soon as connectivity returns. `BookmarkRepository`
/// does not use it; writes are unconditionally optimistic-local and reconciled by the sync engine.
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
