// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Logging
import Testing
@testable import App

// MARK: - LogRingBufferTests

/// Verifies `LogRingBuffer`'s capacity, ordering, and filtering behavior.
@Suite("LogRingBuffer")
struct LogRingBufferTests {

    @Test("append adds an entry retrievable via snapshot")
    func appendAndSnapshot() {
        // Given
        let buffer = LogRingBuffer()

        // When
        buffer.append(.init(timestamp: Date(), level: .info, label: "App", message: "hello"))

        // Then
        let entries = buffer.snapshot()
        #expect(entries.count == 1, "It should retain the appended entry")
        #expect(entries.first?.message == "hello", "It should preserve the message")
        #expect(entries.first?.level == .info, "It should preserve the level")
        #expect(entries.first?.label == "App", "It should preserve the label")
    }

    @Test("snapshot returns newest first")
    func snapshotOrdering() {
        // Given
        let buffer = LogRingBuffer()
        buffer.append(.init(timestamp: Date(), level: .info, label: "App", message: "first"))
        buffer.append(.init(timestamp: Date(), level: .info, label: "App", message: "second"))
        buffer.append(.init(timestamp: Date(), level: .info, label: "App", message: "third"))

        // When
        let entries = buffer.snapshot()

        // Then
        #expect(entries.first?.message == "third", "It should return the most recently appended entry first")
        #expect(entries.last?.message == "first", "It should return the oldest entry last")
    }

    @Test("capacity caps the buffer and drops oldest entries")
    func capacityEviction() {
        // Given
        let buffer = LogRingBuffer(capacity: 3)

        // When
        for index in 1...5 {
            buffer.append(.init(timestamp: Date(), level: .info, label: "App", message: "entry-\(index)"))
        }

        // Then
        let entries = buffer.snapshot()
        #expect(entries.count == 3, "It should cap the buffer at the configured capacity")
        #expect(!entries.contains { $0.message == "entry-1" }, "It should drop the oldest entry")
        #expect(!entries.contains { $0.message == "entry-2" }, "It should drop the second-oldest entry")
        #expect(entries.contains { $0.message == "entry-5" }, "It should retain the newest entry")
    }

    @Test("snapshot filters by minimum level")
    func levelFiltering() {
        // Given
        let buffer = LogRingBuffer()
        buffer.append(.init(timestamp: Date(), level: .debug, label: "App", message: "debug"))
        buffer.append(.init(timestamp: Date(), level: .info, label: "App", message: "info"))
        buffer.append(.init(timestamp: Date(), level: .warning, label: "App", message: "warning"))
        buffer.append(.init(timestamp: Date(), level: .error, label: "App", message: "error"))

        // When
        let entries = buffer.snapshot(level: .warning)

        // Then
        #expect(entries.count == 2, "It should only include entries at or above the minimum level")
        #expect(entries.allSatisfy { $0.level >= .warning }, "It should exclude entries below the minimum level")
    }

    @Test("snapshot with nil level returns every buffered entry regardless of level")
    func noFilterReturnsAll() {
        // Given
        let buffer = LogRingBuffer()
        buffer.append(.init(timestamp: Date(), level: .debug, label: "App", message: "debug"))
        buffer.append(.init(timestamp: Date(), level: .error, label: "App", message: "error"))

        // When
        let entries = buffer.snapshot(level: nil)

        // Then
        #expect(entries.count == 2, "It should return every buffered entry when no level filter is given")
    }
}

// MARK: - RingBufferLogHandlerTests

/// Verifies `RingBufferLogHandler` forwards log calls into the shared buffer.
@Suite("RingBufferLogHandler")
struct RingBufferLogHandlerTests {

    @Test("logging through the handler appends to the shared buffer")
    func handlerAppendsToBuffer() {
        // Given
        let buffer = LogRingBuffer()
        let handler = RingBufferLogHandler(label: "test", buffer: buffer)

        // When
        handler.log(event: LogEvent(
            level: .info,
            message: "hello",
            metadata: nil,
            source: "test",
            file: "x.swift",
            function: "f()",
            line: 1
        ))

        // Then
        let entries = buffer.snapshot()
        #expect(entries.count == 1, "It should append one entry per log call")
        #expect(entries.first?.message == "hello", "It should forward the message")
        #expect(entries.first?.label == "test", "It should forward the handler's label")
    }
}
