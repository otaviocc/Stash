// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

extension Color {

    // MARK: Lifecycle

    /// Parses a `#rrggbb` hex string into a `Color`. Returns `nil` for anything else (short forms,
    /// alpha, or malformed input) — the accent-theme hex values served by the backend
    /// (`AccentTheme`) are always this exact 7-character shape.
    init?(hex: String) {
        guard hex.count == 7, hex.first == "#",
              let value = Int(hex.dropFirst(), radix: 16)
        else {
            return nil
        }

        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    // MARK: Static Functions

    /// Builds a `Color` that resolves to `light` or `dark` depending on the active colour scheme,
    /// mirroring the web frontend's `[data-theme]`/`prefers-color-scheme` accent resolution
    /// (`layout.leaf`). SwiftUI has no cross-platform "light/dark pair" initializer, so this bridges
    /// through `UIColor`/`NSColor`'s dynamic providers — the one place those per-platform types are
    /// touched for accent colours.
    static func dynamic(light: Color, dark: Color) -> Color {
        #if os(iOS)
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
            })
        #elseif os(macOS)
            Color(NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
            })
        #endif
    }
}
