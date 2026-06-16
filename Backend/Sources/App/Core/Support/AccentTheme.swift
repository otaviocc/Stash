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

// MARK: - AccentTheme

/// One of the named accent colour themes the admin can pick for the instance. Each theme
/// carries a light-mode and a dark-mode hex value; the active value is selected client-side via
/// the `data-theme` attribute. `ocean` is the default and matches the app's original accent.
struct AccentTheme: Equatable {

    // MARK: Static Properties

    static let all: [AccentTheme] = [
        AccentTheme(id: "ocean", name: "Ocean", light: "#0a84ff", dark: "#409cff"),
        AccentTheme(id: "sunny", name: "Sunny", light: "#f59e0b", dark: "#fbbf24"),
        AccentTheme(id: "forest", name: "Forest", light: "#16a34a", dark: "#4ade80"),
        AccentTheme(id: "ember", name: "Ember", light: "#dc2626", dark: "#f87171"),
        AccentTheme(id: "aurora", name: "Aurora", light: "#7c3aed", dark: "#a78bfa"),
        AccentTheme(id: "arctic", name: "Arctic", light: "#0891b2", dark: "#22d3ee"),
        AccentTheme(id: "rose", name: "Rose", light: "#be185d", dark: "#f472b6"),
        AccentTheme(id: "dusk", name: "Dusk", light: "#b45309", dark: "#d97706"),
        AccentTheme(id: "slate", name: "Slate", light: "#475569", dark: "#94a3b8"),
        AccentTheme(id: "terracotta", name: "Terracotta", light: "#d17e4c", dark: "#d17e4c")
    ]

    static let `default` = all[0]

    static let validIdentifiers = Set(all.map(\.id))

    // MARK: Properties

    let id: String
    let name: String
    let light: String
    let dark: String

    // MARK: Static Functions

    static func theme(for id: String) -> AccentTheme {
        all.first { $0.id == id } ?? .default
    }
}
