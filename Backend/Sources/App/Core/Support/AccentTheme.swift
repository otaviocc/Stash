// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

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
        AccentTheme(id: "teal", name: "Teal", light: "#0d9488", dark: "#2dd4bf"),
        AccentTheme(id: "coral", name: "Coral", light: "#f97316", dark: "#fb923c"),
        AccentTheme(id: "lavender", name: "Lavender", light: "#8b5cf6", dark: "#c4b5fd"),
        AccentTheme(id: "gold", name: "Gold", light: "#eab308", dark: "#facc15"),
        AccentTheme(id: "apple-music", name: "Music", light: "#FC3C44", dark: "#FC3C44"),
        AccentTheme(id: "spotify", name: "Spotify", light: "#1DB954", dark: "#1DB954"),
        AccentTheme(id: "obsidian", name: "Obsidian", light: "#6C31E3", dark: "#6C31E3"),
        AccentTheme(id: "discord", name: "Discord", light: "#5865F2", dark: "#5865F2"),
        AccentTheme(id: "starbucks", name: "Starbucks", light: "#00704a", dark: "#00704a"),
        AccentTheme(id: "t-mobile", name: "T-Mobile", light: "#e20074", dark: "#e20074"),
        AccentTheme(id: "tumblr", name: "Tumblr", light: "#35465c", dark: "#35465c"),
        AccentTheme(id: "whatsapp", name: "WhatsApp", light: "#075e54", dark: "#075e54"),
        AccentTheme(id: "android", name: "Android", light: "#a4c639", dark: "#a4c639"),
        AccentTheme(id: "boeing", name: "Boeing", light: "#0033a1", dark: "#0033a1")
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
