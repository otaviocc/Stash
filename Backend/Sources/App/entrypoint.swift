// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

/// Shared in-memory log buffer backing the `/admin/logs` viewer (Feature #8). Declared as a
/// plain module-level constant — not `Application.storage` — because it must be reachable both
/// here at bootstrap time (before any `Application` exists) and later from the admin route
/// handler. `Application.storage` cannot hold this because storage doesn't exist yet when
/// `LoggingSystem.bootstrap` runs. See DECISIONS.md, "Feature #8: System Logs".
let sharedLogBuffer = LogRingBuffer()

/// Process entry point: bootstraps the environment, builds the application, and runs it.
@main
enum Entrypoint {

    static func main() async throws {
        var env = try Environment.detect()

        try LoggingSystem.bootstrap(from: &env) { level in
            let console = Terminal()
            return { (label: String) in
                MultiplexLogHandler([
                    ConsoleLogger(label: label, console: console, level: level),
                    RingBufferLogHandler(label: label, buffer: sharedLogBuffer, logLevel: level)
                ])
            }
        }

        let app = try await Application.make(env)
        do {
            try await configure(app)
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
