// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - Favicon endpoint

extension URL {

    /// Builds the Stash favicon endpoint URL (`<base>/api/v1/favicons/<domain>`) for a domain against a
    /// server base, normalizing the base (trim whitespace, strip trailing slashes). Returns `nil` when
    /// the domain or the resolved base is empty. Shared by the app's `FaviconView` (base from
    /// `AppSettings`) and the extension-safe `MetadataFaviconView` (base from the App Group defaults).
    static func stashFavicon(base: String, domain: String?) -> URL? {
        guard let domain, !domain.isEmpty else {
            return nil
        }

        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)

        while trimmed.hasSuffix("/") {
            trimmed = String(trimmed.dropLast())
        }
        guard !trimmed.isEmpty else {
            return nil
        }

        return URL(string: "\(trimmed)/api/v1/favicons/\(domain)")
    }
}

// MARK: - RoundFaviconModifier

/// Applies standard favicon styling: a square frame with rounded corners over an always-light
/// background, so favicons designed for white backdrops stay legible in dark mode. Defaults to the
/// 18×18 list/detail size; the add form's metadata preview opts into a larger one. Lives in `Common`
/// so the app's `FaviconView` and the extension-safe `MetadataFaviconView` share one look.
struct RoundFaviconModifier: ViewModifier {

    // MARK: Properties

    var size: CGFloat = 18

    // MARK: Content Methods

    func body(content: Content) -> some View {
        content
            .frame(width: size - 2, height: size - 2)
            .padding(1)
            .background(.white)
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.22))
    }
}

// MARK: - View + RoundedFavicon

extension View {

    func roundedFavicon(size: CGFloat = 18) -> some View {
        modifier(RoundFaviconModifier(size: size))
    }
}

// MARK: - FaviconMonogram

/// The favicon fallback shown while loading and when the instance has no cached icon (404): a rounded
/// square holding the domain's first letter. Calmer than a broken-link glyph and shared by both
/// favicon views.
struct FaviconMonogram: View {

    // MARK: Properties

    let domain: String?
    var size: CGFloat = 18

    // MARK: Computed Properties

    private var letter: String {
        guard let first = domain?.first else { return "?" }

        return String(first).uppercased()
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22)
            .fill(.quaternary)
            .frame(width: size, height: size)
            .overlay {
                Text(letter)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }
}
