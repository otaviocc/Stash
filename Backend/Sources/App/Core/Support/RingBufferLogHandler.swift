// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Logging

// MARK: - RingBufferLogHandler

/// A `LogHandler` that appends every log line it receives to a shared `LogRingBuffer`, so the
/// `/admin/logs` page has something to display. This handler is never installed alone — it is
/// always combined with the existing console handler via `MultiplexLogHandler` in
/// `entrypoint.swift`, so it is purely additive and never replaces stdout logging.
struct RingBufferLogHandler: LogHandler {

    // MARK: Properties

    let label: String
    let buffer: LogRingBuffer
    var logLevel: Logger.Level = .info
    var metadata: Logger.Metadata = [:]

    // MARK: Functions

    // MARK: Subscript

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        buffer.append(
            .init(timestamp: Date(), level: event.level, label: label, message: event.message.description)
        )
    }
}
