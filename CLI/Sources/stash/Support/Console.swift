// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

// MARK: - Console

/// Terminal input and output helpers.
///
/// Results are written to stdout; prompts, confirmations, and errors are written to stderr so a
/// command's machine-readable output (a table or `--json`) can be piped without interleaving with
/// interactive text.
enum Console {

    static func out(_ message: String) {
        print(message)
    }

    static func error(_ message: String) {
        write(message + "\n", to: FileHandle.standardError)
    }

    static func prompt(_ label: String) -> String? {
        write(label, to: FileHandle.standardError)

        return readLine(strippingNewline: true)
    }

    static func promptHidden(_ label: String) -> String {
        guard let raw = getpass(label) else {
            return ""
        }

        return String(cString: raw)
    }

    static func confirm(_ question: String) -> Bool {
        guard let answer = prompt(question) else {
            return false
        }

        let normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return normalized == "y" || normalized == "yes"
    }

    private static func write(_ string: String, to handle: FileHandle) {
        handle.write(Data(string.utf8))
    }
}
