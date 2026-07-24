// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - InstanceAccent

/// The instance's accent theme, resolved from `GET /api/v1/instance`: a light-mode and dark-mode
/// hex pair plus the readable text colour for each, mirroring the web frontend's `--accent` /
/// `--btn-text` CSS variables. Persisted to the shared App Group defaults so the app (and Share
/// Extension) show the right colour immediately at next launch, with no flash while the network
/// fetch is in flight.
struct InstanceAccent: Equatable {

    // MARK: Static Properties

    /// The built-in default — a neutral gray, deliberately *not* one of the backend's named
    /// `AccentTheme`s, so an app that has never reached the server (or is showing the login screen
    /// pre-fetch) doesn't clash with whatever instance colour arrives a moment later. Matches the
    /// asset-catalog `AccentColor`, which carries the same light/dark gray pair for previews and any
    /// system chrome this environment value doesn't reach.
    static let `default` = InstanceAccent(theme: "default", light: "#8e8e93", dark: "#98989d")

    // MARK: Properties

    let theme: String
    let light: String
    let dark: String

    // MARK: Computed Properties

    /// The accent colour, resolving to `light` or `dark` per the active colour scheme.
    var color: Color {
        .dynamic(
            light: Color(hex: light) ?? .accentColor,
            dark: Color(hex: dark) ?? .accentColor
        )
    }

    /// Readable text for content on a *solid* accent-filled background, per the active colour
    /// scheme (see `AccentContrast`).
    var textColor: Color {
        .dynamic(
            light: Color(hex: AccentContrast.readableTextHex(forBackgroundHex: light)) ?? .white,
            dark: Color(hex: AccentContrast.readableTextHex(forBackgroundHex: dark)) ?? .white
        )
    }

    // MARK: Static Functions

    /// Reads the last-known instance accent from the shared App Group defaults, falling back to
    /// `.default` when nothing has been fetched yet (first launch, or a server that predates this
    /// endpoint).
    static func loadShared(from defaults: UserDefaults) -> InstanceAccent {
        guard let theme = defaults.string(forKey: AppGroup.instanceAccentThemeKey),
              let light = defaults.string(forKey: AppGroup.instanceAccentLightKey),
              let dark = defaults.string(forKey: AppGroup.instanceAccentDarkKey)
        else {
            return .default
        }

        return InstanceAccent(theme: theme, light: light, dark: dark)
    }

    // MARK: Functions

    /// Writes this accent to the shared App Group defaults so the Share Extension (a separate
    /// process) and the next launch see it without a network round trip.
    func saveShared(to defaults: UserDefaults) {
        defaults.set(theme, forKey: AppGroup.instanceAccentThemeKey)
        defaults.set(light, forKey: AppGroup.instanceAccentLightKey)
        defaults.set(dark, forKey: AppGroup.instanceAccentDarkKey)
    }
}
