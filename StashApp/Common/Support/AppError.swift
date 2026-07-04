// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

/// An app-level error raised by the repository layer.
enum AppError: Error {

    case notConfigured
    case sessionExpired
    case unexpectedResponse
}
