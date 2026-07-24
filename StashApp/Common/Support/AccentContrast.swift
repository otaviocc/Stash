// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

/// Ports the web frontend's "Accent-aware button text contrast" rule (`layout.leaf`'s inline
/// script) to native code, so a solid accent-filled background (e.g. `TagCountBadge`) picks
/// readable text on light instance themes (Sunny, Gold, Coral) instead of assuming white.
enum AccentContrast {

    /// WCAG relative-luminance weights on 0–1 sRGB channels, threshold `0.4` — identical to the web
    /// script — deciding near-black (`#1a1a1a`) vs white (`#ffffff`) text for a given accent hex.
    static func readableTextHex(forBackgroundHex hex: String) -> String {
        guard let (red, green, blue) = rgb(fromHex: hex) else {
            return "#ffffff"
        }

        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

        return luminance > 0.4 ? "#1a1a1a" : "#ffffff"
    }

    private static func rgb(fromHex hex: String) -> (Double, Double, Double)? {
        guard hex.count == 7, hex.first == "#",
              let value = Int(hex.dropFirst(), radix: 16)
        else {
            return nil
        }

        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}
