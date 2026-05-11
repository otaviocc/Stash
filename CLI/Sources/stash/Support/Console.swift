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
