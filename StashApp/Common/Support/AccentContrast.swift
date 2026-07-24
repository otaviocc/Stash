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

    /// Nudges a colour that will be used as its *own* foreground/text/icon colour — not as a fill —
    /// toward white (on a dark background) or black (on a light one) just enough to stay legible,
    /// while keeping its hue/identity otherwise intact. Unlike `readableTextHex`, which picks between
    /// two fixed neutrals for text sitting on a solid accent fill, this is for accent colour used
    /// directly as text/icon tint on the app's own surface — e.g. a theme with an identical, very dark
    /// hex for both light and dark mode (a brand navy, say) reads fine on white but is nearly invisible
    /// as text on the app's near-black dark-mode background.
    static func legibleForegroundHex(_ hex: String, forDarkBackground isDarkBackground: Bool) -> String {
        guard let (red, green, blue) = rgb(fromHex: hex) else {
            return hex
        }

        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

        if isDarkBackground {
            let target = 0.5
            guard luminance < target else {
                return hex
            }

            let fraction = min(1, max(0, (target - luminance) / (1 - luminance)))

            return hexString(
                red: red + fraction * (1 - red),
                green: green + fraction * (1 - green),
                blue: blue + fraction * (1 - blue)
            )
        } else {
            let target = 0.75
            guard luminance > target else {
                return hex
            }

            let fraction = min(1, max(0, (luminance - target) / luminance))

            return hexString(
                red: red * (1 - fraction),
                green: green * (1 - fraction),
                blue: blue * (1 - fraction)
            )
        }
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

    private static func hexString(red: Double, green: Double, blue: Double) -> String {
        func channel(_ value: Double) -> Int {
            max(0, min(255, Int((value * 255).rounded())))
        }

        return String(format: "#%02x%02x%02x", channel(red), channel(green), channel(blue))
    }
}
